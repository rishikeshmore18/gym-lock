import Foundation
import Testing
@testable import GymLock

/// `docs/FLOW.md`, Flow 3 and "Goes to the gym in sleep hours anyway": when a
/// gym visit counts, what it sends, and what "verified" means.
@MainActor
struct GymVisitTests {
    private let calendar = Calendar.current

    private func minutes(_ value: Double) -> TimeInterval { value * 60 }

    /// Today at 10:00, so every test stays inside one day and one week.
    private var arrived: Date {
        calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private func workout(startOffset: Double, length: Double, handTyped: Bool = false, from anchor: Date? = nil) -> DetectedWorkout {
        let start = (anchor ?? arrived).addingTimeInterval(minutes(startOffset))
        return DetectedWorkout(
            activityName: "Strength Training",
            startedAt: start,
            endedAt: start.addingTimeInterval(minutes(length)),
            source: "Apple Watch",
            wasUserEntered: handTyped
        )
    }

    // MARK: - Apple Health rules

    @Test func nineteenMinutesInHealthIsNotEnoughTwentyIs() {
        #expect(!WorkoutRules.healthQualifies(workout(startOffset: 0, length: 19), arrivedAt: arrived))
        #expect(WorkoutRules.healthQualifies(workout(startOffset: 0, length: 20), arrivedAt: arrived))
    }

    @Test func aHandTypedWorkoutIsIgnored() {
        #expect(!WorkoutRules.healthQualifies(workout(startOffset: 0, length: 60, handTyped: true), arrivedAt: arrived))
    }

    @Test func aWorkoutMayStartAtMostFifteenMinutesBeforeArrival() {
        #expect(WorkoutRules.healthQualifies(workout(startOffset: -15, length: 30), arrivedAt: arrived))
        #expect(!WorkoutRules.healthQualifies(workout(startOffset: -16, length: 30), arrivedAt: arrived))
    }

    @Test func healthIsCheckedForFiveHoursAfterArrival() {
        #expect(WorkoutRules.healthQualifies(workout(startOffset: 300, length: 25), arrivedAt: arrived))
        #expect(!WorkoutRules.healthQualifies(workout(startOffset: 301, length: 25), arrivedAt: arrived))
    }

    @Test func anOldSessionsWorkoutDecodesAsNotHandTyped() throws {
        let json = #"{"activityName":"Run","startedAt":800000000,"endedAt":800003600,"source":"Apple Watch"}"#
        let decoded = try JSONDecoder().decode(DetectedWorkout.self, from: Data(json.utf8))
        #expect(!decoded.wasUserEntered)
    }

    // MARK: - Time at the gym, through the tracker

    private func makeStore() -> (AppStore, GymVisitTracker, UserDefaults) {
        let suite = "gym-visit-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return (AppStore(defaults: defaults), GymVisitTracker(defaults: defaults, notifier: nil), defaults)
    }

    /// An arrival recorded as a visit that does not count yet.
    private func begin(
        _ tracker: GymVisitTracker,
        store: AppStore,
        timeCounts: Bool = true,
        manualAt: Date? = nil,
        sleepBedtime: String? = nil
    ) -> GymVisit {
        let day = calendar.startOfDay(for: arrived)
        let outcome = SessionOutcome(date: arrived, kind: .showedUp, countsOn: day, proof: .unproven)
        store.log.record(outcome)
        let visit = GymVisit(
            outcomeID: outcome.id,
            sessionID: nil,
            countsOn: day,
            arrivedAt: arrived,
            timeCounts: timeCounts,
            manualAt: manualAt,
            sleepBedtime: sleepBedtime
        )
        tracker.begin(visit)
        return visit
    }

    private func current(_ tracker: GymVisitTracker, _ id: UUID) -> GymVisit? {
        tracker.visits.first { $0.id == id }
    }

    @Test func arrivingAloneDoesNotCount() {
        let (store, tracker, _) = makeStore()
        let visit = begin(tracker, store: store)
        tracker.evaluate(now: arrived.addingTimeInterval(minutes(5)), store: store, photos: [], calendar: calendar)
        #expect(current(tracker, visit.id)?.isCounted == false)
        #expect(store.log.outcomes.last?.counts == false)
        #expect(store.log.outcomes.last?.isVerifiedWorkout == false)
    }

    @Test func twentyMinutesWithNoExitCounts() {
        let (store, tracker, _) = makeStore()
        let visit = begin(tracker, store: store)
        tracker.evaluate(now: arrived.addingTimeInterval(minutes(19)), store: store, photos: [], calendar: calendar)
        #expect(current(tracker, visit.id)?.isCounted == false)

        tracker.evaluate(now: arrived.addingTimeInterval(minutes(20)), store: store, photos: [], calendar: calendar)
        #expect(current(tracker, visit.id)?.proof == .timeAtGym)
        #expect(store.log.outcomes.last?.counts == true)
        #expect(store.log.outcomes.last?.proof == .timeAtGym)
    }

    @Test func aThreeMinuteTripOutsideDoesNotResetTheClock() {
        let (store, tracker, _) = makeStore()
        let visit = begin(tracker, store: store)
        tracker.noteExit(at: arrived.addingTimeInterval(minutes(10)), now: arrived.addingTimeInterval(minutes(10)), calendar: calendar)
        tracker.noteEntry(at: arrived.addingTimeInterval(minutes(13)))
        tracker.evaluate(now: arrived.addingTimeInterval(minutes(20)), store: store, photos: [], calendar: calendar)

        let settled = current(tracker, visit.id)
        #expect(settled?.leftAt == nil)
        #expect(settled?.proof == .timeAtGym)
    }

    @Test func aSixMinuteExitAtTwelveMinutesIsLeaving() {
        let (store, tracker, _) = makeStore()
        let visit = begin(tracker, store: store)
        let exit = arrived.addingTimeInterval(minutes(12))
        tracker.noteExit(at: exit, now: exit, calendar: calendar)
        tracker.evaluate(now: arrived.addingTimeInterval(minutes(18)), store: store, photos: [], calendar: calendar)

        let settled = current(tracker, visit.id)
        #expect(settled?.leftAt == exit)
        #expect(settled?.isCounted == false)
        // "you left after 12 min" at the moment leaving is known; no done line.
        #expect(settled?.shortFireAt == exit.addingTimeInterval(minutes(5)))
        #expect(settled?.minutesBeforeLeaving == 12)
        #expect(settled?.doneFireAt == nil)
        #expect(WorkoutDoneLine.shortVisit(minutes: 12) == "you left after 12 min. 20 minutes makes it count.")
    }

    @Test func aHealthWorkoutAfterAShortVisitStillCountsLater() {
        let (store, tracker, _) = makeStore()
        let visit = begin(tracker, store: store)
        let exit = arrived.addingTimeInterval(minutes(12))
        tracker.noteExit(at: exit, now: exit, calendar: calendar)
        tracker.evaluate(now: arrived.addingTimeInterval(minutes(18)), store: store, photos: [], calendar: calendar)

        let syncedAt = arrived.addingTimeInterval(minutes(90))
        tracker.add([workout(startOffset: 2, length: 25)], now: syncedAt)
        tracker.evaluate(now: syncedAt, store: store, photos: [], calendar: calendar)

        let settled = current(tracker, visit.id)
        #expect(settled?.proof == .health)
        #expect(store.log.outcomes.last?.workoutDetected == true)
        // The workout-done line goes when Health confirms it.
        #expect(settled?.doneFireAt == syncedAt)
    }

    @Test func twelveMinutesInHealthPlusThirtyFiveAtTheGymCounts() {
        let (store, tracker, _) = makeStore()
        let visit = begin(tracker, store: store)
        tracker.add([workout(startOffset: 0, length: 12)], now: arrived)
        let exit = arrived.addingTimeInterval(minutes(35))
        tracker.noteExit(at: exit, now: exit, calendar: calendar)
        tracker.evaluate(now: arrived.addingTimeInterval(minutes(41)), store: store, photos: [], calendar: calendar)
        #expect(current(tracker, visit.id)?.proof == .timeAtGym)
    }

    @Test func healthAloneCountsWithNoTimeAtTheGym() {
        let (store, tracker, _) = makeStore()
        let visit = begin(tracker, store: store, timeCounts: false)
        tracker.evaluate(now: arrived.addingTimeInterval(minutes(40)), store: store, photos: [], calendar: calendar)
        #expect(current(tracker, visit.id)?.isCounted == false)

        tracker.add([workout(startOffset: 1, length: 22)], now: arrived.addingTimeInterval(minutes(40)))
        tracker.evaluate(now: arrived.addingTimeInterval(minutes(41)), store: store, photos: [], calendar: calendar)
        #expect(current(tracker, visit.id)?.proof == .health)
    }

    @Test func theDoneNoticeIsScheduledForThirtyMinutesOrLeavingWhicheverIsFirst() {
        let stay = GymVisit(outcomeID: UUID(), sessionID: nil, countsOn: arrived, arrivedAt: arrived, timeCounts: true)
        #expect(stay.doneNoticeDate() == arrived.addingTimeInterval(minutes(30)))

        var leaves = stay
        leaves.leftAt = arrived.addingTimeInterval(minutes(22))
        #expect(leaves.doneNoticeDate() == arrived.addingTimeInterval(minutes(27)))

        var short = stay
        short.leftAt = arrived.addingTimeInterval(minutes(12))
        #expect(short.doneNoticeDate() == nil)
    }

    // MARK: - The notification line

    @Test func theLineUsesTheRealCountThisWeek() {
        #expect(WorkoutDoneLine.countLine(2) == "2 of 3 this week. share your progress.")
        #expect(WorkoutDoneLine.countLine(3) == "that's 3. this one keeps your streak.")
        #expect(WorkoutDoneLine.countLine(4) == "4 this week. that's a bonus day.")
        #expect(WorkoutDoneLine.countLine(1) == "1 of 3 this week. share your progress.")
    }

    @Test func comingBackAfterAMissGetsItsOwnLine() {
        #expect(WorkoutDoneLine.pick(countThisWeek: 2, cameBack: true, last: nil) == WorkoutDoneLine.cameBack)
        #expect(WorkoutDoneLine.cameBack == "you came back. that's the hardest one.")
    }

    @Test func theSameLineIsNeverSentTwiceInARow() {
        let line = WorkoutDoneLine.pick(countThisWeek: 2, cameBack: true, last: WorkoutDoneLine.cameBack)
        #expect(line == WorkoutDoneLine.countLine(2))
    }

    @Test func comebackIsTheFirstCountedDayAfterAMissedOrSkippedDay() throws {
        let today = calendar.startOfDay(for: arrived)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let missed = MomentumLog(outcomes: [SessionOutcome(date: yesterday, kind: .missed, countsOn: yesterday)])
        #expect(WorkoutDoneLine.isComeback(log: missed, day: today, calendar: calendar))

        let skipped = MomentumLog(outcomes: [SessionOutcome(date: yesterday, kind: .easySkip, countsOn: yesterday)])
        #expect(WorkoutDoneLine.isComeback(log: skipped, day: today, calendar: calendar))

        let trained = MomentumLog(outcomes: [SessionOutcome(date: yesterday, kind: .homeWorkout, countsOn: yesterday)])
        #expect(!WorkoutDoneLine.isComeback(log: trained, day: today, calendar: calendar))
    }

    @Test func theDoneLineCountsThisWorkoutAndIsRemembered() {
        let (store, tracker, _) = makeStore()
        let visit = begin(tracker, store: store)
        tracker.evaluate(now: arrived.addingTimeInterval(minutes(1)), store: store, photos: [], calendar: calendar)
        // Scheduled for 30 minutes, with this workout already in the count.
        let scheduled = current(tracker, visit.id)
        #expect(scheduled?.doneFireAt == arrived.addingTimeInterval(minutes(30)))
        #expect(scheduled?.doneLine == WorkoutDoneLine.countLine(1))
        #expect(tracker.lastLine == WorkoutDoneLine.countLine(1))
    }

    @Test func aVisitInSleepHoursGetsTheSleepLine() {
        let (store, tracker, _) = makeStore()
        let visit = begin(tracker, store: store, sleepBedtime: "23:00")
        tracker.evaluate(now: arrived.addingTimeInterval(minutes(21)), store: store, photos: [], calendar: calendar)
        let settled = current(tracker, visit.id)
        #expect(settled?.isCounted == true)
        #expect(settled?.doneLine == "workout counted. it cost you sleep though. aim to be home by 23:00.")
    }

    @Test func noGymLineUsesAnEmDash() {
        let lines = [
            WorkoutDoneLine.arrival, WorkoutDoneLine.cameBack,
            WorkoutDoneLine.countLine(2), WorkoutDoneLine.countLine(3), WorkoutDoneLine.countLine(4),
            WorkoutDoneLine.sleepLine(bedtime: "23:00"), WorkoutDoneLine.shortVisit(minutes: 12),
        ]
        for line in lines { #expect(!line.contains("\u{2014}")) }
        #expect(WorkoutDoneLine.arrival == "you're in. 20 minutes and today counts.")
    }

    // MARK: - "I'm here"

    private func photo(_ source: ProgressPhotoSource, at date: Date) -> ProgressPhoto {
        ProgressPhoto(id: UUID(), createdAt: date, fileName: "a.jpg", thumbnailName: "a-thumb.jpg", source: source)
    }

    @Test func imHereDoesNotCountWithoutHealthOrAPhoto() {
        let visit = GymVisit(outcomeID: UUID(), sessionID: nil, countsOn: arrived, arrivedAt: arrived, timeCounts: false, manualAt: arrived)
        let later = arrived.addingTimeInterval(minutes(90))
        #expect(WorkoutRules.proof(for: visit, now: later, workouts: [], photos: [], calendar: calendar) == nil)
    }

    @Test func imHereCountsWithACameraPhotoTakenAfterIt() {
        let visit = GymVisit(outcomeID: UUID(), sessionID: nil, countsOn: arrived, arrivedAt: arrived, timeCounts: false, manualAt: arrived)
        let later = arrived.addingTimeInterval(minutes(30))
        let camera = photo(.camera, at: arrived.addingTimeInterval(minutes(10)))
        #expect(WorkoutRules.proof(for: visit, now: later, workouts: [], photos: [camera], calendar: calendar) == .photo)
    }

    @Test func libraryFilesAndEarlierPhotosNeverCount() {
        let visit = GymVisit(outcomeID: UUID(), sessionID: nil, countsOn: arrived, arrivedAt: arrived, timeCounts: false, manualAt: arrived)
        let later = arrived.addingTimeInterval(minutes(30))
        let photos = [
            photo(.library, at: arrived.addingTimeInterval(minutes(10))),
            photo(.files, at: arrived.addingTimeInterval(minutes(10))),
            photo(.camera, at: arrived.addingTimeInterval(-minutes(10))),
        ]
        #expect(WorkoutRules.proof(for: visit, now: later, workouts: [], photos: photos, calendar: calendar) == nil)
    }

    @Test func imHereCountsWithTwentyMinutesInHealth() {
        let visit = GymVisit(outcomeID: UUID(), sessionID: nil, countsOn: arrived, arrivedAt: arrived, timeCounts: false, manualAt: arrived)
        let proof = WorkoutRules.proof(
            for: visit, now: arrived.addingTimeInterval(minutes(60)),
            workouts: [workout(startOffset: 5, length: 20)], photos: [], calendar: calendar
        )
        #expect(proof == .health)
    }

    @Test func imHereIgnoresTimeAtTheGym() {
        let visit = GymVisit(outcomeID: UUID(), sessionID: nil, countsOn: arrived, arrivedAt: arrived, timeCounts: false, manualAt: arrived)
        #expect(!visit.presenceQualifies(now: arrived.addingTimeInterval(minutes(60))))
    }

    // MARK: - Visits with no alarm

    private func makeCoordinator() -> (GymSessionCoordinator, AppStore) {
        let suite = "gym-visit-coordinator-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = AppStore(defaults: defaults)
        let coordinator = GymSessionCoordinator(defaults: defaults, shield: DemoShieldService(defaults: defaults))
        coordinator.bindStoreOnly(store)
        return (coordinator, store)
    }

    @Test func aVisitWithNoAlarmCountsOnTheArrivalDay() throws {
        let (coordinator, store) = makeCoordinator()
        let visit = try #require(coordinator.recordUnscheduledVisit(fromStateCheck: false, at: arrived))
        #expect(store.log.outcomes.last?.counts == false)

        coordinator.evaluateVisits(now: arrived.addingTimeInterval(minutes(21)))
        let outcome = try #require(store.log.outcomes.first { $0.id == visit.outcomeID })
        #expect(outcome.counts)
        #expect(outcome.sessionID == nil)
        #expect(outcome.countingDay(calendar: calendar) == calendar.startOfDay(for: arrived))
    }

    @Test func alreadyInsideWhenMonitoringStartedOnlyHealthCounts() throws {
        let (coordinator, store) = makeCoordinator()
        let visit = try #require(coordinator.recordUnscheduledVisit(fromStateCheck: true, at: arrived))
        #expect(!visit.timeCounts)

        coordinator.evaluateVisits(now: arrived.addingTimeInterval(minutes(60)))
        #expect(store.log.outcomes.first { $0.id == visit.outcomeID }?.counts == false)

        coordinator.visits.add([workout(startOffset: 5, length: 25)], now: arrived.addingTimeInterval(minutes(60)))
        coordinator.evaluateVisits(now: arrived.addingTimeInterval(minutes(61)))
        #expect(store.log.outcomes.first { $0.id == visit.outcomeID }?.proof == .health)
    }

    @Test func aSecondVisitWhileOneIsOpenIsNotRecorded() {
        // The coordinator holds the store weakly, so the test keeps it alive.
        let (coordinator, store) = makeCoordinator()
        #expect(coordinator.recordUnscheduledVisit(fromStateCheck: false, at: arrived) != nil)
        #expect(coordinator.recordUnscheduledVisit(fromStateCheck: false, at: arrived.addingTimeInterval(minutes(3))) == nil)
        #expect(store.log.outcomes.count == 1)
    }

    // MARK: - Old records keep counting

    @Test func oldArrivalsAndHomeWorkoutsDecodeAsLegacyAndKeepTheirStreak() throws {
        let weekCalendar = ProgressAnalytics.displayCalendar(calendar)
        let monday = try #require(StreakEngine.weekStart(containing: arrived, weekCalendar: weekCalendar))
        let days = (0..<3).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
        let kinds = ["showedUp", "homeWorkout", "showedUp"]
        let rows = zip(days, kinds).map { day, kind in
            #"{"id":"\#(UUID().uuidString)","date":\#(day.timeIntervalSinceReferenceDate),"kind":"\#(kind)","workoutDetected":false}"#
        }
        let json = #"{"outcomes":[\#(rows.joined(separator: ","))]}"#

        let old = try JSONDecoder().decode(MomentumLog.self, from: Data(json.utf8))
        #expect(old.outcomes.allSatisfy { $0.proof == .legacy && $0.counts })

        let before = MomentumLog(outcomes: zip(days, kinds).map { day, kind in
            SessionOutcome(date: day, kind: SessionOutcomeKind(rawValue: kind) ?? .showedUp)
        })
        let oldDays = StreakEngine.sessionDays(in: old, weekStarting: monday, calendar: calendar)
        let expected = StreakEngine.sessionDays(in: before, weekStarting: monday, calendar: calendar)
        #expect(oldDays == expected)
        #expect(oldDays.count == 3)
    }

    @Test func otherOldOutcomesStayUncounted() throws {
        let json = #"{"id":"\#(UUID().uuidString)","date":800000000,"kind":"missed","workoutDetected":false}"#
        let old = try JSONDecoder().decode(SessionOutcome.self, from: Data(json.utf8))
        #expect(!old.counts)
    }

    @Test func aNewOutcomeRoundTripsItsProof() throws {
        let outcome = SessionOutcome(kind: .showedUp, proof: .timeAtGym)
        let decoded = try JSONDecoder().decode(SessionOutcome.self, from: JSONEncoder().encode(outcome))
        #expect(decoded.proof == .timeAtGym)
    }

    // MARK: - Verified means workout done

    @Test func anArrivalOnlyVisitIsNotVerified() {
        let visitOnly = MomentumLog(outcomes: [SessionOutcome(date: arrived, kind: .showedUp, proof: .unproven)])
        let history = ShareContextBuilder.history(log: visitOnly, events: .empty, weeklyGoal: 3, calendar: calendar)
        #expect(!history.hasVerifiedVisit)
        #expect(history.verifiedVisitsEver == 0)
        #expect(visitOnly.totalVerifiedGymVisits == 0)
    }

    @Test func aDoneWorkoutIsVerified() {
        let done = MomentumLog(outcomes: [SessionOutcome(date: arrived, kind: .showedUp, proof: .timeAtGym)])
        let history = ShareContextBuilder.history(log: done, events: .empty, weeklyGoal: 3, calendar: calendar)
        #expect(history.hasVerifiedVisit)
        #expect(history.verifiedVisitsEver == 1)
        #expect(done.totalVerifiedGymVisits == 1)
    }

    @Test func theMilestoneSaysWorkouts() {
        #expect(Milestone(kind: .verifiedVisits(10)).title == "10 VERIFIED WORKOUTS")
        #expect(Milestone(kind: .verifiedVisits(1)).label == "VERIFIED WORKOUT")
    }

    @Test func aCountedVisitStandsForTheDayOverALaterUncountedOne() {
        let day = calendar.startOfDay(for: arrived)
        let log = MomentumLog(outcomes: [
            SessionOutcome(date: arrived, kind: .showedUp, countsOn: day, proof: .timeAtGym),
            SessionOutcome(date: arrived.addingTimeInterval(3600), kind: .showedUp, countsOn: day, proof: .unproven),
        ])
        #expect(log.outcome(on: day, calendar: calendar)?.counts == true)
    }

    // MARK: - Notification routes

    @Test func theWorkoutDoneNotificationOpensProgressAndNeverAnAlarm() {
        let day = calendar.startOfDay(for: arrived)
        let route = NotificationRoute(
            identifier: NotificationRoute.ID.workoutDone(day: day, visitID: UUID()),
            categoryIdentifier: ""
        )
        #expect(route == .workoutDone(day: day))
        #expect(!route.isAlarm)
        #expect(route.handoff(forAction: "com.apple.UNNotificationDefaultActionIdentifier", at: arrived) == nil)
    }

    @Test func theLeftEarlyNotificationCarriesItsDay() {
        let day = calendar.startOfDay(for: arrived)
        let route = NotificationRoute(
            identifier: NotificationRoute.ID.leftEarly(day: day, visitID: UUID()),
            categoryIdentifier: ""
        )
        #expect(route == .leftEarly(day: day))
    }

    @Test func tappingTheWorkoutDoneNotificationLandsOnProgress() {
        let (coordinator, store) = makeCoordinator()
        defer { withExtendedLifetime(store) {} }
        let day = calendar.startOfDay(for: arrived)
        coordinator.openProgressSpotlight(for: day)
        #expect(coordinator.requestedTab == .progress)
        #expect(coordinator.pendingSpotlightDay == day)
        #expect(coordinator.session == nil)
    }
}
