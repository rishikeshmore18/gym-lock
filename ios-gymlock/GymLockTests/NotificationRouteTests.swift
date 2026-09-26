import Foundation
import Testing
import UserNotifications
@testable import GymLock

/// `docs/FLOW.md`, item 12: only alarm notifications may start a session.
@MainActor
struct NotificationRouteTests {
    private let noCategory = ""
    private let alarmCategory = NotificationAlarmScheduler.categoryIdentifier

    private func route(_ identifier: String, category: String = "") -> NotificationRoute {
        NotificationRoute(identifier: identifier, categoryIdentifier: category)
    }

    private var allActions: [String] {
        [
            AlarmNotificationDelegate.Action.imUp,
            AlarmNotificationDelegate.Action.snooze,
            UNNotificationDefaultActionIdentifier,
            UNNotificationDismissActionIdentifier,
        ]
    }

    // MARK: - Parsing every identifier MorningNotifier sends

    @Test func departureIsASessionRoute() {
        #expect(route(NotificationRoute.ID.departure) == .session(.departure))
    }

    @Test func deadlineIsASessionRoute() {
        #expect(route(NotificationRoute.ID.deadline) == .session(.deadline))
    }

    @Test func arrivalIsASessionRoute() {
        #expect(route(NotificationRoute.ID.arrival) == .session(.arrival))
    }

    @Test func comebackIsASessionRoute() {
        #expect(route(NotificationRoute.ID.comeback) == .session(.comeback))
    }

    @Test func theOldMovedIdentifierIsNoLongerSent() {
        // "move time" and its notification were removed (FLOW, Flow 2).
        #expect(route("gymlock.session.moved") == .unknown)
    }

    @Test func aPlainWakeAlarmIsNeverAnAlarmRoute() {
        let request = GymAlarmRequest(
            slotID: WakeAlarmID.weekly,
            time: TimeOfDay(hour: 7, minute: 0),
            weekdays: [.tuesday],
            title: "Wake up",
            message: "Good morning.",
            kind: .plainWake
        )
        let parsed = route(request.notificationIdentifier(for: .tuesday))
        #expect(parsed == .plainWake)
        for action in allActions {
            #expect(parsed.handoff(forAction: action, at: Date()) == nil)
        }
    }

    @Test func theTimeToGoCategoryIsAnAlarm() {
        let slot = UUID()
        let request = GymAlarmRequest(
            slotID: slot,
            time: TimeOfDay(hour: 17, minute: 30),
            weekdays: [.monday],
            title: "Time to go",
            message: "You planned this.",
            kind: .timeToGo
        )
        let parsed = route(
            request.notificationIdentifier(for: .monday),
            category: NotificationAlarmScheduler.timeToGoCategoryIdentifier
        )
        #expect(parsed == .alarm(slotID: slot))
    }

    @Test func theMissedNoticeCarriesItsDay() throws {
        let calendar = Calendar.current
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)))
        let parsed = route(MissedNotice.identifier(forDay: day, calendar: calendar))
        #expect(parsed == .missed(day: day))
        #expect(!parsed.isAlarm)
        #expect(parsed.handoff(forAction: UNNotificationDefaultActionIdentifier, at: Date()) == nil)
    }

    @Test func theSnoozeRefireIsItsOwnRoute() {
        // Even carrying its own registered category, it is not an alarm.
        let refire = route(
            NotificationRoute.ID.snooze,
            category: AlarmNotificationDelegate.Category.snoozeRefire
        )
        #expect(refire == .snoozeRefire)
    }

    @Test func windDownIsItsOwnRoute() {
        #expect(route(NotificationRoute.ID.windDown) == .windDown)
    }

    @Test func noMorningNotifierIdentifierIsAnAlarm() {
        for id in NotificationRoute.ID.sessionScoped + [NotificationRoute.ID.windDown] {
            #expect(!route(id).isAlarm, "\(id) must never start a session")
        }
    }

    // MARK: - Alarms

    @Test func aWeeklyAlarmIdentifierIsAnAlarmWithItsSlot() {
        let slot = UUID()
        let request = GymAlarmRequest(
            slotID: slot,
            time: TimeOfDay(hour: 6, minute: 30),
            weekdays: [.monday],
            title: "Gym time",
            message: "You planned this."
        )
        let parsed = route(request.notificationIdentifier(for: .monday), category: alarmCategory)
        #expect(parsed == .alarm(slotID: slot))
    }

    @Test func aOneOffAlarmIdentifierIsAnAlarmWithItsOwnID() {
        let oneOff = UUID()
        let request = GymAlarmRequest(
            slotID: oneOff,
            time: TimeOfDay(hour: 7, minute: 15),
            weekdays: [.wednesday],
            title: "Gym time",
            message: "You planned this.",
            fireDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let parsed = route(request.notificationIdentifier(for: .wednesday), category: alarmCategory)
        #expect(parsed == .alarm(slotID: oneOff))
    }

    @Test func theAlarmPrefixAloneIsEnough() {
        let slot = UUID()
        #expect(route("gymlock.alarm.\(slot.uuidString).2") == .alarm(slotID: slot))
    }

    @Test func theAlarmCategoryAloneIsEnough() {
        #expect(route("something.else", category: alarmCategory) == .alarm(slotID: nil))
    }

    @Test func anUnknownIdentifierIsUnknown() {
        #expect(route("com.example.other") == .unknown)
        #expect(route("gymlock.session.somethingNew") == .unknown)
    }

    // MARK: - Which taps write a handoff

    @Test func onlyAnAlarmEverProducesAHandoff() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let nonAlarms: [NotificationRoute] = NotificationRoute.SessionKind.allCases.map { .session($0) }
            + [.snoozeRefire, .windDown, .unknown, .plainWake, .missed(day: Date(timeIntervalSince1970: 0))]

        for route in nonAlarms {
            for action in allActions {
                #expect(route.handoff(forAction: action, at: now) == nil)
            }
        }
    }

    @Test func alarmTapsKeepTodaysBehaviour() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let slot = UUID()
        let alarm = NotificationRoute.alarm(slotID: slot)

        let imUp = alarm.handoff(forAction: AlarmNotificationDelegate.Action.imUp, at: now)
        let body = alarm.handoff(forAction: UNNotificationDefaultActionIdentifier, at: now)
        let dismiss = alarm.handoff(forAction: UNNotificationDismissActionIdentifier, at: now)
        let snooze = alarm.handoff(forAction: AlarmNotificationDelegate.Action.snooze, at: now)

        #expect(imUp == AlarmHandoff.Pending(slotID: slot, firedAt: now, wantsSnooze: false))
        #expect(body == AlarmHandoff.Pending(slotID: slot, firedAt: now, wantsSnooze: false))
        #expect(dismiss == AlarmHandoff.Pending(slotID: slot, firedAt: now, wantsSnooze: false))
        #expect(snooze == AlarmHandoff.Pending(slotID: slot, firedAt: now, wantsSnooze: true))
    }

    @Test func anUnrecognisedActionOnAnAlarmWritesNothing() {
        let alarm = NotificationRoute.alarm(slotID: UUID())
        #expect(alarm.handoff(forAction: "gymlock.some.future.action", at: Date()) == nil)
    }

    // MARK: - The pending route

    private func makeDefaults() -> UserDefaults {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func aNonAlarmRouteIsKept() {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        PendingNotificationRoute.write(.session(.arrival), at: now, defaults: defaults)

        let entry = PendingNotificationRoute.take(defaults: defaults)
        #expect(entry == PendingNotificationRoute.Entry(route: .session(.arrival), tappedAt: now))
        #expect(PendingNotificationRoute.peek(defaults: defaults) == nil)
    }

    @Test func anAlarmRouteIsNeverKept() {
        let defaults = makeDefaults()
        PendingNotificationRoute.write(.alarm(slotID: UUID()), defaults: defaults)
        #expect(PendingNotificationRoute.peek(defaults: defaults) == nil)
    }

    @Test func everyRouteSurvivesEncoding() throws {
        let routes: [NotificationRoute] = NotificationRoute.SessionKind.allCases.map { .session($0) }
            + [.snoozeRefire, .windDown, .unknown, .alarm(slotID: UUID()), .alarm(slotID: nil),
               .plainWake, .missed(day: Date(timeIntervalSince1970: 86_400))]

        for route in routes {
            let entry = PendingNotificationRoute.Entry(route: route, tappedAt: Date(timeIntervalSince1970: 1))
            let data = try JSONEncoder().encode(entry)
            let decoded = try JSONDecoder().decode(PendingNotificationRoute.Entry.self, from: data)
            #expect(decoded == entry)
        }
    }

    @Test func aStoredHandoffFromBeforeThisChangeStillDecodes() throws {
        // The handoff format is unchanged; an existing note must still load.
        let json = #"{"slotID":"6F9619FF-8B86-D011-B42D-00C04FC964FF","firedAt":800000000,"wantsSnooze":true}"#
        let decoded = try JSONDecoder().decode(AlarmHandoff.Pending.self, from: Data(json.utf8))
        #expect(decoded.wantsSnooze)
        #expect(decoded.slotID == UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
    }
}
