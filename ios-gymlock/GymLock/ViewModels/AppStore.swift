import Foundation
import Observation

/// Where the user currently is in the app's lifecycle.
enum AppStage: String, Codable {
    case onboarding
    case scheduleSetup
    case home
}

/// Single source of truth for user-entered onboarding data, the schedule,
/// and which stage of the app should be on screen.
///
/// Persistence is deliberately narrow: only values the user would expect to
/// survive a relaunch are written to `UserDefaults`.
@Observable
final class AppStore {
    private enum Key {
        static let name = "gymlock.userName"
        static let stage = "gymlock.stage"
        static let schedule = "gymlock.schedule"
        static let profile = "gymlock.profile"
        static let plan = "gymlock.morningPlan"
        static let log = "gymlock.momentumLog"
        static let departureMessage = "gymlock.lastDepartureMessage"
        static let gym = "gymlock.primaryGym"
        static let events = "gymlock.sessionEvents"
        static let blockedAppsConfigured = "gymlock.blockedAppsConfigured"
        static let streakVault = "gymlock.streakVault"
    }

    private let defaults: UserDefaults

    var userName: String {
        didSet { defaults.set(userName, forKey: Key.name) }
    }

    var stage: AppStage {
        didSet { defaults.set(stage.rawValue, forKey: Key.stage) }
    }

    var schedule: GymSchedule {
        didSet {
            persistSchedule()
            refreshStreak()
        }
    }

    /// Everything the user told GymLock while building their system.
    var profile: OnboardingProfile {
        didSet { persistProfile() }
    }

    /// When GymLock acts: the sleep rhythm, the alarm slots, and the night lock.
    ///
    /// This extends the profile rather than competing with it. The profile is
    /// what the user said about themselves; the plan is the schedule they are
    /// actually running, seeded from those answers.
    var plan: MorningPlan {
        didSet {
            persist(plan, forKey: Key.plan)
            refreshStreak()
        }
    }

    /// The honest ledger of what happened on each planned session.
    var log: MomentumLog {
        didSet {
            persist(log, forKey: Key.log)
            refreshStreak()
        }
    }

    /// What the streak remembers between evaluations: banked freezes and the
    /// weeks they protected. The count itself is never stored — see `streak`.
    private(set) var streakVault: StreakVault {
        didSet { persist(streakVault, forKey: Key.streakVault) }
    }

    /// The streak, in kept weeks, as every screen shows it.
    ///
    /// Derived from the ledger by `StreakEngine` and refreshed whenever the
    /// ledger, the plan or the schedule changes, and on every foreground so a
    /// week that ended overnight is ruled on before anyone reads the number.
    /// Held as stored state rather than recomputed in every view body because
    /// evaluation can *spend* a freeze, and a side effect belongs in one place.
    private(set) var streak: StreakSnapshot = .empty

    /// The gym the user actually goes to.
    ///
    /// The one extra thing they configure for automatic arrival detection, set
    /// once from a map search. V1 keeps a single primary gym; the field is
    /// singular rather than a list because two gyms is a real but much rarer
    /// case, and guessing at it now would complicate every arrival decision.
    var primaryGym: GymLocation? {
        didSet {
            if let primaryGym {
                persist(primaryGym, forKey: Key.gym)
            } else {
                defaults.removeObject(forKey: Key.gym)
            }
        }
    }

    /// The behavioural record that will power the activity grid.
    var events: SessionEventLog {
        didSet { persist(events, forKey: Key.events) }
    }

    /// Whether the user has been through the blocked-apps picker.
    ///
    /// Asked exactly once. Nobody should be choosing a blocklist at 6:30 in the
    /// morning.
    var hasConfiguredBlockedApps: Bool {
        didSet { defaults.set(hasConfiguredBlockedApps, forKey: Key.blockedAppsConfigured) }
    }

    /// Index of the last departure message sent, so the next one differs.
    var lastDepartureMessageIndex: Int? {
        didSet {
            if let lastDepartureMessageIndex {
                defaults.set(lastDepartureMessageIndex, forKey: Key.departureMessage)
            } else {
                defaults.removeObject(forKey: Key.departureMessage)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        userName = defaults.string(forKey: Key.name) ?? ""

        if let raw = defaults.string(forKey: Key.stage), let stored = AppStage(rawValue: raw) {
            stage = stored
        } else {
            stage = .onboarding
        }

        if let data = defaults.data(forKey: Key.schedule),
           let decoded = try? JSONDecoder().decode(GymSchedule.self, from: data) {
            schedule = decoded
        } else {
            schedule = .default
        }

        if let data = defaults.data(forKey: Key.profile),
           let decoded = try? JSONDecoder().decode(OnboardingProfile.self, from: data) {
            profile = decoded
        } else {
            profile = .default
        }

        if let data = defaults.data(forKey: Key.plan),
           let decoded = try? JSONDecoder().decode(MorningPlan.self, from: data) {
            plan = decoded
        } else {
            plan = .default
        }

        if let data = defaults.data(forKey: Key.log),
           let decoded = try? JSONDecoder().decode(MomentumLog.self, from: data) {
            log = decoded
        } else {
            log = .empty
        }

        if let data = defaults.data(forKey: Key.gym),
           let decoded = try? JSONDecoder().decode(GymLocation.self, from: data) {
            primaryGym = decoded
        } else {
            primaryGym = nil
        }

        if let data = defaults.data(forKey: Key.events),
           let decoded = try? JSONDecoder().decode(SessionEventLog.self, from: data) {
            events = decoded
        } else {
            events = .empty
        }

        if let data = defaults.data(forKey: Key.streakVault),
           let decoded = try? JSONDecoder().decode(StreakVault.self, from: data) {
            streakVault = decoded
        } else {
            streakVault = .empty
        }

        hasConfiguredBlockedApps = defaults.bool(forKey: Key.blockedAppsConfigured)
        lastDepartureMessageIndex = defaults.object(forKey: Key.departureMessage) as? Int

        refreshStreak()
    }

    // MARK: - Streak

    /// Re-derives the streak and settles any weeks that completed since the
    /// last evaluation.
    ///
    /// The vault is only written back when evaluation actually changed it, so
    /// the common case — nothing new to rule on — costs one pass over the
    /// ledger and no disk write.
    func refreshStreak(now: Date = Date()) {
        var vault = streakVault
        let snapshot = StreakEngine.evaluate(
            log: log,
            plan: plan,
            schedule: schedule,
            vault: &vault,
            now: now
        )
        if vault != streakVault { streakVault = vault }
        if snapshot != streak { streak = snapshot }
    }

    /// Spends one banked freeze on the current week, ahead of time.
    ///
    /// The Ladder behaviour: a user who already knows this week is lost can
    /// protect the streak now instead of hoping the automatic freeze catches
    /// it. Refunded by the engine if the week turns out kept after all.
    @discardableResult
    func armFreezeForThisWeek(now: Date = Date()) -> Bool {
        guard streak.canArmFreeze else { return false }
        var vault = streakVault
        vault.freezesAvailable -= 1
        vault.preArmedWeekStart = streak.liveWeekStart
        streakVault = vault
        refreshStreak(now: now)
        return true
    }

    // MARK: - Events

    /// Records a behavioural event.
    ///
    /// Everything here is emitted by the system as the morning unfolds. There
    /// is no manual logging anywhere in GymLock, and there must never be.
    func record(_ kind: SessionEventKind, sessionID: UUID? = nil, detail: String? = nil) {
        events.record(SessionEvent(sessionID: sessionID, kind: kind, at: Date(), detail: detail))
    }

    /// Whether the passive arrival system is fully configured.
    var isAutomaticArrivalReady: Bool { primaryGym != nil }

    // MARK: - Notification taps

    /// The last non-alarm notification the app was opened from, if any.
    ///
    /// Nothing reads it yet. The workout-done notification will use it to
    /// open Progress. Alarm taps never appear here.
    var pendingNotificationRoute: PendingNotificationRoute.Entry? {
        PendingNotificationRoute.peek(defaults: defaults)
    }

    /// Reads and clears it, so one tap is acted on once.
    func takePendingNotificationRoute() -> PendingNotificationRoute.Entry? {
        PendingNotificationRoute.take(defaults: defaults)
    }

    // MARK: - Morning plan

    /// Builds the plan out of the onboarding answers the first time it is
    /// needed, so the user is never asked something they already told us.
    func seedPlanIfNeeded() {
        guard plan.slots.isEmpty else { return }
        plan = MorningPlan.seeded(from: profile, schedule: schedule)
    }

    /// Whether gym-bag missions may be offered.
    ///
    /// Nothing in onboarding asks about a bag, and requiring everyone to own one
    /// would strand the people who do not. Until there is a real signal, the
    /// mission stays out of the pool.
    var usesGymBag: Bool { false }

    /// Records a mission so the same one is not handed out twice running.
    func rememberMission(_ mission: ActivationMissionType) {
        var recent = plan.recentMissions
        recent.append(mission)
        if recent.count > 6 { recent.removeFirst(recent.count - 6) }
        plan.recentMissions = recent
    }

    /// Folds a changed rhythm back into the night lock, but only when the user
    /// has not customised it themselves.
    func applyRhythmToNightLock() {
        guard plan.nightLock.followsRhythm else { return }
        plan.nightLock.customStart = plan.rhythm.bedtime
        plan.nightLock.customEnd = plan.rhythm.wakeTime
        schedule.bedtime = plan.rhythm.bedtime
    }

    /// Trimmed display name, falling back to a neutral greeting target.
    var greetingName: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "friend" : trimmed
    }

    var hasName: Bool {
        !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toggleTrainingDay(_ day: Weekday) {
        var days = schedule.trainingDays
        if days.contains(day) {
            days.remove(day)
        } else {
            days.insert(day)
        }
        schedule.trainingDays = days
    }

    private func persistSchedule() {
        guard let data = try? JSONEncoder().encode(schedule) else { return }
        defaults.set(data, forKey: Key.schedule)
    }

    private func persistProfile() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: Key.profile)
    }

    private func persist<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    /// Folds the onboarding answers into the live schedule the rest of the app
    /// runs on, so the home screen reflects the system the user just built
    /// rather than the defaults.
    ///
    /// Training days are chosen by spreading the requested count across the week
    /// with rest days in between, which is a far better starting point than the
    /// first N weekdays and is still fully editable later.
    func applyProfileToSchedule() {
        schedule.gymTime = profile.failureTime
        if profile.wantsNightLock {
            schedule.bedtime = profile.bedtime
        }
        schedule.trainingDays = Self.spreadTrainingDays(count: profile.targetWorkoutsPerWeek)
    }

    /// Picks `count` days spread as evenly as possible across the week.
    static func spreadTrainingDays(count: Int) -> Set<Weekday> {
        let ordered = Weekday.allCases
        let clamped = min(max(count, 1), ordered.count)
        guard clamped < ordered.count else { return Set(ordered) }

        let stride = Double(ordered.count) / Double(clamped)
        let picked = (0..<clamped).map { step -> Weekday in
            let index = min(ordered.count - 1, Int((Double(step) * stride).rounded(.down)))
            return ordered[index]
        }
        return Set(picked)
    }

    /// Wipes stored progress. Used by the developer reset affordance in Settings.
    func resetAll() {
        userName = ""
        schedule = .default
        profile = .default
        plan = .default
        log = .empty
        events = .empty
        primaryGym = nil
        hasConfiguredBlockedApps = false
        lastDepartureMessageIndex = nil
        streakVault = .empty
        refreshStreak()
        stage = .onboarding
    }

    #if DEBUG
    /// Removes recent skips so the within-allowance branch can be exercised.
    func debugClearSkips() {
        let cutoff = Date().addingTimeInterval(-28 * 24 * 3600)
        log.outcomes.removeAll { $0.date >= cutoff && $0.kind.usesSkipAllowance }
    }

    /// Drops in a plausible gym so arrival can be exercised without a map.
    func debugSeedGym() {
        guard primaryGym == nil else { return }
        primaryGym = GymLocation(
            name: "Test Gym",
            subtitle: "debug fixture",
            latitude: 37.3349,
            longitude: -122.0090
        )
    }

    /// Burns through the allowance so the over-allowance branch can be seen.
    func debugExhaustSkips(count: Int) {
        debugClearSkips()
        for offset in 0..<count {
            log.record(
                SessionOutcome(
                    date: Date().addingTimeInterval(-Double(offset + 1) * 24 * 3600),
                    kind: .easySkip
                )
            )
        }
    }
    #endif
}
