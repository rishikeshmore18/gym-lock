import Foundation

/// Follows every gym visit from arrival until it is settled (FLOW, Flow 3).
///
/// iOS won't run the app on a timer, so nothing here waits. Region events,
/// Health updates, saved photos and foregrounds all call `evaluate`, which
/// works out from the clock what has happened. The notifications that must
/// arrive while the app is asleep (the workout-done line at 30 minutes, "you
/// left after") are scheduled ahead and moved or cancelled as facts change.
@MainActor
final class GymVisitTracker {
    private enum Key {
        static let visits = "gymlock.gymVisits"
        static let workouts = "gymlock.recentWorkouts"
        static let lastLine = "gymlock.lastWorkoutDoneLine"
    }

    private let defaults: UserDefaults
    /// Nil in tests: the notification decisions are still made and stored.
    private let notifier: MorningNotifier?

    private(set) var visits: [GymVisit]
    /// Health workouts seen recently, kept so a visit can be settled on any
    /// later run of the app.
    private(set) var workouts: [DetectedWorkout]

    init(defaults: UserDefaults, notifier: MorningNotifier?) {
        self.defaults = defaults
        self.notifier = notifier
        visits = Self.decode([GymVisit].self, from: defaults.data(forKey: Key.visits)) ?? []
        workouts = Self.decode([DetectedWorkout].self, from: defaults.data(forKey: Key.workouts)) ?? []
    }

    /// The workout-done line sent last, so the next one differs.
    var lastLine: String? { defaults.string(forKey: Key.lastLine) }

    // MARK: - Visits

    /// The visit still running: arrived, not left, not closed.
    func openVisit(now: Date, calendar: Calendar) -> GymVisit? {
        visits.last { $0.leftAt == nil && now < $0.closesAt(calendar: calendar) }
    }

    func begin(_ visit: GymVisit) {
        visits.append(visit)
        persist()
    }

    /// The phone left the gym area. Only a candidate for 5 minutes.
    func noteExit(at date: Date, now: Date, calendar: Calendar) {
        guard let index = visits.lastIndex(where: { $0.leftAt == nil && now < $0.closesAt(calendar: calendar) }),
              visits[index].pendingExitAt == nil,
              date >= visits[index].arrivedAt
        else { return }
        visits[index].pendingExitAt = date
        persist()
    }

    /// The phone came back. Within 5 minutes the trip didn't happen; later
    /// than that, they had really left.
    func noteEntry(at date: Date) {
        guard let index = visits.lastIndex(where: { $0.leftAt == nil && $0.pendingExitAt != nil }),
              let exit = visits[index].pendingExitAt
        else { return }
        if date.timeIntervalSince(exit) >= WorkoutRules.shortTripGrace {
            visits[index].leftAt = exit
        }
        visits[index].pendingExitAt = nil
        persist()
    }

    // MARK: - Health

    /// Adds workouts, once each, keeping the last two days.
    func add(_ new: [DetectedWorkout], now: Date) {
        var merged = workouts
        for workout in new where !merged.contains(where: {
            $0.startedAt == workout.startedAt && $0.endedAt == workout.endedAt && $0.source == workout.source
        }) {
            merged.append(workout)
        }
        let cutoff = now.addingTimeInterval(-2 * 24 * 3600)
        merged.removeAll { $0.endedAt < cutoff }
        guard merged != workouts else { return }
        workouts = merged
        if let data = try? JSONEncoder().encode(workouts) { defaults.set(data, forKey: Key.workouts) }
    }

    // MARK: - Settling

    /// Settles every open visit against the clock, Health and photos, and
    /// moves the notifications to match. Returns the visits that counted on
    /// this call.
    @discardableResult
    func evaluate(now: Date, store: AppStore, photos: [ProgressPhoto], calendar: Calendar) -> [GymVisit] {
        var newlyCounted: [GymVisit] = []
        var changed = false

        for index in visits.indices {
            var visit = visits[index]
            let before = visit
            guard now < visit.closesAt(calendar: calendar).addingTimeInterval(3600) else { continue }

            visit.settleExit(now: now)

            if !visit.isCounted,
               let proof = WorkoutRules.proof(for: visit, now: now, workouts: workouts, photos: photos, calendar: calendar) {
                visit.proof = proof
                visit.countedAt = now
                markCounted(visit, proof: proof, store: store)
                newlyCounted.append(visit)
            }

            if workouts.contains(where: { WorkoutRules.healthQualifies($0, arrivedAt: visit.healthAnchor) }) {
                var log = store.log
                if log.markWorkoutDetected(outcomeID: visit.outcomeID) { store.log = log }
            }

            syncNotices(&visit, now: now, store: store, calendar: calendar)

            if visit != before {
                visits[index] = visit
                changed = true
            }
        }

        // Kept a day past closing for the debug panel, then dropped.
        let kept = visits.filter { now < $0.closesAt(calendar: calendar).addingTimeInterval(24 * 3600) }
        if kept.count != visits.count {
            visits = kept
            changed = true
        }
        if changed { persist() }
        return newlyCounted
    }

    /// Marks the arrival counted, or writes it now for a visit with no alarm,
    /// which only reaches the log once the workout is done.
    private func markCounted(_ visit: GymVisit, proof: WorkoutProof, store: AppStore) {
        var log = store.log
        if log.outcomes.contains(where: { $0.id == visit.outcomeID }) {
            guard log.markCounted(outcomeID: visit.outcomeID, proof: proof) else { return }
        } else {
            log.record(
                SessionOutcome(
                    id: visit.outcomeID,
                    date: visit.arrivedAt,
                    kind: .showedUp,
                    sessionID: visit.sessionID,
                    workoutDetected: proof == .health,
                    countsOn: visit.countsOn,
                    proof: proof
                )
            )
        }
        store.log = log
        store.record(.workoutCounted, sessionID: visit.sessionID, detail: proof.rawValue)
    }

    // MARK: - Notifications

    private func syncNotices(_ visit: inout GymVisit, now: Date, store: AppStore, calendar: Calendar) {
        let doneID = NotificationRoute.ID.workoutDone(day: visit.countsOn, visitID: visit.id, calendar: calendar)
        let desiredDone = visit.doneNoticeDate()
        if desiredDone != visit.doneFireAt, !Self.hasFired(visit.doneFireAt, now: now) {
            if let desiredDone {
                if visit.doneLine == nil {
                    let line = line(for: visit, store: store, calendar: calendar)
                    visit.previousLastLine = lastLine
                    visit.doneLine = line
                    defaults.set(line, forKey: Key.lastLine)
                }
                visit.doneFireAt = desiredDone
                let body = visit.doneLine ?? ""
                Task { [notifier] in await notifier?.scheduleGymNotice(id: doneID, at: desiredDone, body: body) }
            } else {
                visit.doneFireAt = nil
                if let line = visit.doneLine, lastLine == line {
                    defaults.set(visit.previousLastLine, forKey: Key.lastLine)
                }
                visit.doneLine = nil
                Task { [notifier] in await notifier?.cancelGymNotice(id: doneID) }
            }
        }

        let leftID = NotificationRoute.ID.leftEarly(day: visit.countsOn, visitID: visit.id, calendar: calendar)
        let desiredShort = visit.shortNoticeDate()
        if desiredShort != visit.shortFireAt, !Self.hasFired(visit.shortFireAt, now: now) {
            visit.shortFireAt = desiredShort
            if let desiredShort {
                let body = WorkoutDoneLine.shortVisit(minutes: visit.minutesBeforeLeaving)
                Task { [notifier] in await notifier?.scheduleGymNotice(id: leftID, at: desiredShort, body: body) }
            } else {
                Task { [notifier] in await notifier?.cancelGymNotice(id: leftID) }
            }
        }
    }

    /// A notification whose time has passed was delivered; it is never moved.
    private static func hasFired(_ date: Date?, now: Date) -> Bool {
        date.map { $0 <= now } ?? false
    }

    /// The line, with the real numbers as they will be once this workout
    /// counts. A visit in sleep hours gets the sleep line instead.
    private func line(for visit: GymVisit, store: AppStore, calendar: Calendar) -> String {
        if let bedtime = visit.sleepBedtime { return WorkoutDoneLine.sleepLine(bedtime: bedtime) }
        var counted = store.log
        if !counted.markCounted(outcomeID: visit.outcomeID, proof: .timeAtGym),
           !counted.outcomes.contains(where: { $0.id == visit.outcomeID }) {
            counted.record(SessionOutcome(id: visit.outcomeID, date: visit.arrivedAt, kind: .showedUp, countsOn: visit.countsOn, proof: .timeAtGym))
        }
        let count = WorkoutDoneLine.countThisWeek(log: counted, day: visit.countsOn, calendar: calendar)
        let comeback = WorkoutDoneLine.isComeback(log: store.log, day: visit.countsOn, calendar: calendar)
        return WorkoutDoneLine.pick(countThisWeek: count, cameBack: comeback, last: lastLine)
    }

    // MARK: - Storage

    private func persist() {
        guard let data = try? JSONEncoder().encode(visits) else { return }
        defaults.set(data, forKey: Key.visits)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    #if DEBUG
    func debugClear() {
        visits = []
        workouts = []
        defaults.removeObject(forKey: Key.visits)
        defaults.removeObject(forKey: Key.workouts)
    }
    #endif
}
