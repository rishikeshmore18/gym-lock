//
//  WakeFactsProvider.swift
//  GymLock · the "I'm up" wake page
//
//  Builds `WakeFacts` from the real app state, with the same definitions the rest of the app uses,
//  and picks the concept. No placeholder data: a fact the app does not have is nil and the copy
//  drops its words (WakeCopy).
//
//  Field by field:
//    name          AppStore.userName, only when AppStore.hasName (never greetingName's "friend")
//    gymName       AppStore.primaryGym?.name
//    gymTime       session.deadline ?? session.arrivalTarget (what HeroDayFacts.gymBy reads), then
//                  the day's rhythm `MorningPlan.rhythm(at:).gymByTime`
//    leaveBy       nil. MorningRhythm keeps one Time to Gym (get ready and travel together) and the
//                  session's old travelMinutes is private and nil on new sessions, so there is no
//                  honest leave-by. The copy says "Gym by 7:05." (RESEARCH.md §4.2, conflict 1).
//    mission       session.mission (assigned in commitToGoing via assignMission), the same fallback
//                  ActivationMissionView shows (.universalFallback) when missions are on; with
//                  missions off the next act is "Shoes on" handing off to the countdown (RESEARCH §2.5)
//    missionSteps  ActivationMissionType.stepTarget (20 or 30)
//    weekDone      HeroDayFacts.weekCount   = store.streak.thisWeekSessionDays
//    weekGoal      HeroDayFacts.weekGoal    = store.streak.weeklyGoal
//    habitDay      HeroDayFacts.habitDay(_:) (days since the first counted session, the hero card's day)
//    streakWeeks   HeroDayFacts.streakWeeks = store.streak.weeks
//    isFirst       HeroDayFacts.neverCounted (no counted session yet)
//    isComeback    HeroMomentResolver.comebackLapse(_:cal:) != nil (the hero card's comeback rule)
//    snoozed       session.hasSnoozed
//
//  Depends on: AppStore, GymSessionCoordinator, GymSession, ActivationMissionType, HeroMomentResolver
//  (gather, comebackLapse, displayCalendar), HeroRotationStore, HeroCardStyle, WakeStage.swift.
//

import Foundation

@MainActor
enum WakeFactsProvider {
    /// The facts for this session, read once when the page starts.
    static func facts(
        store: AppStore,
        coordinator: GymSessionCoordinator,
        session: GymSession,
        now: Date = Date()
    ) -> WakeFacts {
        let cal = HeroMomentResolver.displayCalendar()
        // The hero card's own read of the app: the week, the run, the streak, the history. Read-only.
        let day = HeroMomentResolver.gather(store: store, coordinator: coordinator, now: now, cal: cal, rotation: .shared)

        let name = store.hasName ? store.userName.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let gymTime = session.deadline
            ?? session.arrivalTarget
            ?? store.plan.rhythm(at: now, calendar: .current).gymByTime.asDateToday

        let mission = missionParts(
            session.mission ?? (store.plan.missionsEnabled ? ActivationMissionType.universalFallback : nil)
        )

        return WakeFacts(
            name: name,
            gymName: store.primaryGym?.name,
            gymTime: gymTime,
            leaveBy: nil,
            missionTitle: mission.title,
            missionKind: mission.kind,
            missionSteps: mission.steps,
            weekDone: day.weekCount,
            weekGoal: day.weekGoal,
            habitDay: day.habitDay(cal) ?? 1,
            streakWeeks: day.streakWeeks,
            isFirst: day.neverCounted,
            isComeback: HeroMomentResolver.comebackLapse(day, cal: cal) != nil,
            snoozed: session.hasSnoozed
        ).normalized()
    }

    /// The concept for today.
    ///
    /// Ridge or Matrix follows the user's hero card style (`gymlock.home.cardStyle`, Ridge by default).
    /// A (the plan) by default; B (progress) for users past day 8 of their run, on alternate mornings.
    /// The alternation follows the habit day's parity, so it is fixed for the whole day and flips daily.
    static func concept(for facts: WakeFacts, defaults: UserDefaults = .standard) -> WakeConcept {
        let style = defaults.string(forKey: HeroCardStyle.storageKey).flatMap(HeroCardStyle.init(rawValue:)) ?? .default
        let progress = !facts.isFirst && facts.habitDay > 8 && facts.habitDay % 2 == 0
        switch style {
        case .matrix: return progress ? .matrixB : .matrixA
        case .ridge: return progress ? .ridgeB : .ridgeA
        }
    }

    /// The mission's sentence-case title, its visual, and its step count.
    ///
    /// The app's titles are lowercase chrome ("take 20 steps"); this page is sentence case (RESEARCH
    /// §2.3), so only the first letter changes. Mirror has no visual of its own and takes the
    /// prototype's default (the shoe), as model.ts does for any title it does not recognise.
    static func missionParts(_ mission: ActivationMissionType?) -> (title: String, kind: WakeMissionKind, steps: Int) {
        guard let mission else { return ("Shoes on", .shoe, 0) }
        let kind: WakeMissionKind
        switch mission {
        case .twentySteps, .walkToDoor: kind = .steps
        case .gymBag: kind = .bag
        case .grabWater: kind = .water
        case .showGymShoes, .shoesOn, .mirrorBoost: kind = .shoe
        }
        return (sentenceCase(mission.title), kind, mission.stepTarget ?? 0)
    }

    /// The SF Symbol the app already uses for this kind of mission (ActivationMissionType.icon).
    static func symbol(for kind: WakeMissionKind) -> String {
        switch kind {
        case .steps: "figure.walk"
        case .bag: "bag.fill"
        case .water: "waterbottle.fill"
        case .shoe: "shoe.2"
        }
    }

    /// One row of the mission capsule's reel: the mission's own icon and its sentence-case title.
    static func reelItem(for mission: ActivationMissionType) -> WakeReelItem {
        WakeReelItem(id: mission.rawValue, title: sentenceCase(mission.title), symbol: mission.icon)
    }

    private static func sentenceCase(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}
