import Foundation

/// Decides whether a morning should be running right now.
///
/// Pure and `nonisolated` so the rule that decides whether somebody's phone
/// locks itself can be tested against a fixed clock rather than discovered at
/// 6:30 in the morning. The coordinator does the side effects; this only
/// answers the question.
nonisolated enum SessionResume {
    /// How long after the window closes the app will still pick a morning up.
    ///
    /// Someone who opens GymLock ten minutes after their deadline is still
    /// having the morning they planned. Someone opening it at lunchtime is not,
    /// and must not be ambushed by a locked phone.
    static let resumeGrace = 30

    struct Decision: Equatable {
        enum Source: Equatable {
            /// A note left by the alarm's own button or a notification response.
            case handoff
            /// Nothing was left behind; the clock alone says a window is open.
            case clock
        }

        var slotID: UUID?
        /// When the session should be dated from. For a handoff this is when
        /// the alarm actually rang, not when the user finally looked at the
        /// phone, so the deadline is not quietly extended by ignoring it.
        var startAt: Date
        var wantsSnooze: Bool
        var source: Source
    }

    /// `"<slotID>|<yyyy-MM-dd>"`, built from components rather than a
    /// `DateFormatter` so a non-Gregorian locale cannot change the key.
    static func resolvedKey(slotID: UUID?, day: Date, calendar: Calendar = .current) -> String {
        "\(slotID?.uuidString ?? "none")|\(dayKey(for: day, calendar: calendar))"
    }

    static func dayKey(for day: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }

    /// The whole rule, in one place.
    ///
    /// - Parameters:
    ///   - isSessionLive: A live morning is never restarted or overwritten.
    ///   - handoff: Peeked, not taken. Consuming is the caller's job, and only
    ///     on the path that actually acts on it.
    ///   - resolvedKeys: Slots already finished today. Without this, someone who
    ///     says "can't today" at 6:35 and reopens the app at 6:50 gets their
    ///     apps locked again.
    static func decide(
        now: Date,
        isSessionLive: Bool,
        handoff: AlarmHandoff.Pending?,
        slots: [AlarmSlot],
        windowMinutes: Int,
        resolvedKeys: Set<String>,
        calendar: Calendar = .current
    ) -> Decision? {
        // A live session wins over everything, and the note is deliberately
        // left where it is. It may belong to a later slot that becomes
        // actionable once this morning resolves, and `staleAfter` already
        // bounds how long it can sit there.
        guard !isSessionLive else { return nil }

        if let handoff {
            return Decision(
                slotID: handoff.slotID,
                startAt: handoff.firedAt,
                wantsSnooze: handoff.wantsSnooze,
                source: .handoff
            )
        }

        guard let today = Weekday(rawValue: calendar.component(.weekday, from: now)) else {
            return nil
        }

        let open = slots
            .filter { $0.isEnabled && $0.days.contains(today) }
            .compactMap { slot -> (slot: AlarmSlot, firedAt: Date)? in
                guard let firedAt = calendar.date(
                    bySettingHour: slot.alarmTime.hour,
                    minute: slot.alarmTime.minute,
                    second: 0,
                    of: now
                ) else { return nil }

                guard firedAt <= now else { return nil }

                let closesAt = firedAt.addingTimeInterval(
                    Double(windowMinutes + resumeGrace) * 60
                )
                guard now < closesAt else { return nil }

                let key = resolvedKey(slotID: slot.id, day: now, calendar: calendar)
                guard !resolvedKeys.contains(key) else { return nil }

                return (slot, firedAt)
            }

        // The most recent open window, so a day with a morning and an evening
        // slot resumes the one the user is actually in.
        guard let chosen = open.max(by: { $0.firedAt < $1.firedAt }) else { return nil }

        return Decision(
            slotID: chosen.slot.id,
            startAt: chosen.firedAt,
            wantsSnooze: false,
            source: .clock
        )
    }
}
