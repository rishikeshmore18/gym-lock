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

    /// What to do with the pending handoff, alongside whether to start.
    ///
    /// Split out because a handoff can now be thrown away without anything
    /// starting: a note for a slot already settled that day, or a second note
    /// for the morning that is already running.
    struct Resolution: Equatable {
        var decision: Decision?
        /// The caller clears the handoff when this is true.
        var clearsHandoff: Bool

        static let nothing = Resolution(decision: nil, clearsHandoff: false)
        static let discardHandoff = Resolution(decision: nil, clearsHandoff: true)
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

    /// Whether to start, without the handoff bookkeeping. Kept for callers
    /// and tests that only care about the decision.
    static func decide(
        now: Date,
        isSessionLive: Bool,
        liveSlotID: UUID? = nil,
        liveSessionDay: Date? = nil,
        handoff: AlarmHandoff.Pending?,
        slots: [AlarmSlot],
        windowMinutes: Int,
        resolvedKeys: Set<String>,
        alarmSlotIDs: [UUID: UUID] = [:],
        calendar: Calendar = .current
    ) -> Decision? {
        resolve(
            now: now,
            isSessionLive: isSessionLive,
            liveSlotID: liveSlotID,
            liveSessionDay: liveSessionDay,
            handoff: handoff,
            slots: slots,
            windowMinutes: windowMinutes,
            resolvedKeys: resolvedKeys,
            alarmSlotIDs: alarmSlotIDs,
            calendar: calendar
        ).decision
    }

    /// The whole rule, in one place.
    ///
    /// - Parameters:
    ///   - isSessionLive: A live morning is never restarted or overwritten.
    ///   - liveSlotID: The live session's slot, so a second note for the same
    ///     morning can be told apart from a note for a different slot.
    ///   - liveSessionDay: The live session's day. A note that fired on a
    ///     different day is not the same morning, so it waits instead.
    ///   - handoff: Peeked, not taken. Clearing is the caller's job, and only
    ///     when `clearsHandoff` says so.
    ///   - resolvedKeys: Slots already finished today. Without this, someone who
    ///     says "can't today" at 6:35 and reopens the app at 6:50 gets their
    ///     apps locked again.
    ///   - alarmSlotIDs: One-off alarm ids mapped to the slot they stand for.
    ///     A "change next alarm only" alarm carries its own id, but the day it
    ///     settles is recorded under the slot's id.
    static func resolve(
        now: Date,
        isSessionLive: Bool,
        liveSlotID: UUID? = nil,
        liveSessionDay: Date? = nil,
        handoff: AlarmHandoff.Pending?,
        slots: [AlarmSlot],
        windowMinutes: Int,
        resolvedKeys: Set<String>,
        alarmSlotIDs: [UUID: UUID] = [:],
        calendar: Calendar = .current
    ) -> Resolution {
        let handoffSlotID = handoff?.slotID.map { alarmSlotIDs[$0] ?? $0 }

        // A live session wins over everything.
        if isSessionLive {
            guard let handoff else { return .nothing }
            // The same morning again: the AlarmKit intent and observer racing,
            // or a no-slot note. Thrown away now rather than left to start a
            // second session the moment this one ends.
            let isSameDay = liveSessionDay.map {
                calendar.isDate(handoff.firedAt, inSameDayAs: $0)
            } ?? true
            if isSameDay, handoff.slotID == nil || handoffSlotID == liveSlotID {
                return .discardHandoff
            }
            // A different slot waits: it may become actionable once this
            // morning resolves, and `staleAfter` bounds how long it can sit.
            return .nothing
        }

        if let handoff {
            // A slot already settled for the day the note fired never starts
            // again. Keyed by `firedAt`, not `now`, so a note from before
            // midnight is judged against its own day.
            let key = resolvedKey(slotID: handoffSlotID, day: handoff.firedAt, calendar: calendar)
            guard !resolvedKeys.contains(key) else { return .discardHandoff }

            return Resolution(
                decision: Decision(
                    slotID: handoff.slotID,
                    startAt: handoff.firedAt,
                    wantsSnooze: handoff.wantsSnooze,
                    source: .handoff
                ),
                clearsHandoff: true
            )
        }

        guard let today = Weekday(rawValue: calendar.component(.weekday, from: now)) else {
            return .nothing
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
        guard let chosen = open.max(by: { $0.firedAt < $1.firedAt }) else { return .nothing }

        return Resolution(
            decision: Decision(
                slotID: chosen.slot.id,
                startAt: chosen.firedAt,
                wantsSnooze: false,
                source: .clock
            ),
            clearsHandoff: false
        )
    }
}
