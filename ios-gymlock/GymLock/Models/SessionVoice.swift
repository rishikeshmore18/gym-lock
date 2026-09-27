import Foundation

/// Every line the session flow says, chosen by when the user actually trains.
///
/// Until now the flow was written for one person: someone whose alarm goes off
/// in the dark. That copy is wrong for most of the people using it. "you planned
/// this last night" is a lie to a user training at 18:00, "still getting ready?"
/// is nonsense to someone who has been dressed since 07:00, and a snooze button
/// at 17:25 is a procrastination button at exactly the moment the product exists
/// to remove procrastination.
///
/// So the voice is derived, once, from the session's daypart and read by every
/// screen. Putting it here rather than in the views means the three variants can
/// be compared side by side and tested without a simulator, and it makes the
/// rule impossible to forget: a screen asks the voice, it never writes a line.
///
/// `nonisolated` because it is pure text derivation with no UI state, so it can
/// be built from any context, including a notification handler on a background
/// thread.
nonisolated struct SessionVoice: Hashable {
    let daypart: SessionDaypart
    /// True once this session's single snooze has been spent. The copy after a
    /// snooze is shorter and more direct, and the snooze itself is gone.
    let hasSnoozed: Bool
    /// False when the user switched the snooze off on the Alarm screen.
    let snoozeEnabled: Bool
    /// The snooze length the user chose, 1 to 15.
    let snoozeMinutes: Int
    /// Which flow the alarm ran in (Step 0). Decides whether a snooze exists;
    /// the wording still follows the clock.
    let flowMode: GymFlowMode

    /// `flowMode` left out falls back to what the clock used to decide, so a
    /// voice built from a time alone reads as it always did.
    init(
        daypart: SessionDaypart,
        hasSnoozed: Bool = false,
        snoozeEnabled: Bool = true,
        snoozeMinutes: Int = 5,
        flowMode: GymFlowMode? = nil
    ) {
        self.daypart = daypart
        self.hasSnoozed = hasSnoozed
        self.snoozeEnabled = snoozeEnabled
        self.snoozeMinutes = snoozeMinutes
        self.flowMode = flowMode ?? (daypart == .morning ? .wakeAndGo : .goLater)
    }

    init(session: GymSession) {
        self.init(
            daypart: SessionDaypart(session.alarmTime),
            hasSnoozed: session.hasSnoozed,
            snoozeEnabled: session.offersSnooze,
            snoozeMinutes: session.snoozeDurationMinutes,
            flowMode: session.resolvedFlowMode
        )
    }

    // MARK: - Vocabulary

    /// What to call this block of time. Used wherever a sentence needs a noun
    /// for "the thing that is happening today".
    var sessionNoun: String {
        switch daypart {
        case .morning: "morning"
        case .midday: "session"
        case .evening: "session"
        }
    }

    /// The caption under the clock on the alarm screen, e.g. "gym morning".
    var clockCaption: String {
        switch daypart {
        case .morning: "gym morning"
        case .midday: "gym session"
        case .evening: "gym evening"
        }
    }

    // MARK: - The alarm screen

    /// Whether a snooze may be offered at all.
    ///
    /// Wake & Go only, and only once (FLOW, Flow 1). A Go Later alarm finds
    /// the user already awake, so it offers running late instead (Flow 2).
    ///
    /// And only if the user has not switched it off.
    var allowsSnooze: Bool { snoozeEnabled && flowMode == .wakeAndGo && !hasSnoozed }

    /// The Go Later option on the decision screen (FLOW, Flow 2).
    var runningLateAction: String { "running late" }

    /// Shown while running late waits for its alarm.
    func runningLateHeadline(until time: String) -> String {
        "rings again at \(time)."
    }

    var runningLateSupport: String { "your apps stay locked." }

    /// The action the user is being asked to take.
    var primaryAction: String {
        daypart == .morning ? "I'm up" : "I'm going"
    }

    var primarySymbol: String {
        daypart == .morning ? "sun.horizon.fill" : "figure.walk"
    }

    /// First line under the clock: the reason this alarm exists.
    var alarmGreeting: String {
        if hasSnoozed { return "time to move." }
        switch daypart {
        case .morning: return "you planned this last night."
        case .midday, .evening: return "you planned this."
        }
    }

    /// Second line: what to do about it.
    var alarmSupport: String {
        if hasSnoozed { return "no more decisions. just go." }
        switch daypart {
        case .morning: return "just start moving."
        case .midday: return "go before the afternoon fills up."
        case .evening: return "last thing today. then it's done."
        }
    }

    /// Shown while the snooze is running down.
    func snoozeHeadline(until time: String) -> String {
        "back at \(time)."
    }

    var snoozeSupport: String {
        "your apps stay locked. rest, don't restart."
    }

    var snoozeAction: String { "\(snoozeMinutes) more min" }

    /// The escape hatch on the alarm screen. It is never hidden.
    var changePlanAction: String { "plans changed" }

    var cantTodayAction: String { "can't today" }

    // MARK: - The preparation window

    func windowHeading(hasLeft: Bool) -> String {
        if hasLeft { return "on your way" }
        switch daypart {
        case .morning: return "your morning is running"
        case .midday, .evening: return "your window is open"
        }
    }

    func windowSupport(hasLeft: Bool) -> String {
        if hasLeft { return "finish the trip." }
        switch daypart {
        case .morning: return "distractions are locked. the day gets easier from here."
        case .midday: return "distractions are locked. the rest of the day will keep."
        case .evening: return "distractions are locked. this is the last ask today."
        }
    }

    /// The small encouragement card at the foot of the window screen.
    func windowFooterTitle(hasLeft: Bool) -> String {
        hasLeft ? "you're moving" : "stay with it"
    }

    func windowFooterDetail(hasLeft: Bool) -> String {
        if hasLeft { return "the hard part is behind you." }
        switch daypart {
        case .morning: return "the first hour decides the rest."
        case .midday: return "the day does not get quieter later."
        case .evening: return "tired is not the same as done."
        }
    }

    // MARK: - The single nudge

    var nudgeHeading: String {
        switch daypart {
        case .morning: "still getting ready?"
        case .midday, .evening: "still heading out?"
        }
    }

    var nudgeSupport: String {
        switch daypart {
        case .morning: "no rush. the window is still open."
        case .midday: "no rush. the window is still open."
        case .evening: "no rush. the window is still open."
        }
    }

    // MARK: - Departure

    var departureSupport: String {
        switch daypart {
        case .morning: "you beat the hardest part of the day."
        case .midday: "you beat the part of the day that usually eats this."
        case .evening: "you beat the couch."
        }
    }

    // MARK: - The window closing

    var plansChangedSupport: String {
        switch daypart {
        case .morning: "the morning ran out. that's information, not a verdict."
        case .midday: "the window closed. that's information, not a verdict."
        case .evening: "the evening ran out. that's information, not a verdict."
        }
    }

    // MARK: - Resolving the day

    /// Subtitle on the "skip" row.
    var dayOffDetail: String { "no penalty, no catch-up" }

    // MARK: - Sharing

    /// VoiceOver label for the share link on the two success screens.
    var shareAccessibilityLabel: String {
        daypart == .morning ? "Share this morning" : "Share this session"
    }
}
