import SwiftUI

/// The screen the user meets the instant the alarm is silenced.
///
/// It contains almost nothing on purpose. Someone who has been awake for four
/// seconds cannot read a paragraph, will not appreciate a streak, and does not
/// need a calendar. One time, two lines, and the fewest choices the situation
/// allows — no cards, no stats, no eyebrow labels, no progress pills. Anything
/// added here is something the user has to look past to reach the decision,
/// which is the only thing this screen is for.
///
/// Everything it says comes from `SessionVoice`, so the 6:30 version and the
/// 18:00 version are genuinely different screens rather than the same screen
/// with a misleading greeting. The clearest difference is the snooze: it exists
/// in the morning, once, and never at any other hour.
struct AlarmFiredView: View {
    let session: GymSession
    let onGoing: () -> Void
    let onSnooze: () -> Void
    /// Go Later's running-late choices still on offer (minutes). Empty hides
    /// the button: used already, Wake & Go, or every choice runs into sleep.
    let runningLateOptions: [Int]
    /// Called with the minutes chosen, counted from the tap.
    let onRunningLate: (Int) -> Void
    let onCantToday: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @State private var isChoosingLate = false

    private var voice: SessionVoice { SessionVoice(session: session) }
    private var isSnoozing: Bool { session.state == .snoozed }
    private var isRunningLate: Bool { session.state == .runningLate }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 8)

                clock
                    .opacity(hasAppeared ? 1 : 0)
                    .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.96)

                Spacer(minLength: 20)

                headline
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared || reduceMotion ? 0 : 16)

                Spacer(minLength: 20)

                actions
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared || reduceMotion ? 0 : 14)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.bottom, 14)
        }
        .task {
            // A short beat before anything moves: the alarm has only just
            // stopped, and content arriving on the same frame reads as jarring.
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(Theme.settle) { hasAppeared = true }
        }
        // PLACEHOLDER UI: designed in Step 3
        .confirmationDialog(
            voice.runningLateAction,
            isPresented: $isChoosingLate,
            titleVisibility: .visible
        ) {
            ForEach(runningLateOptions, id: \.self) { minutes in
                Button(Self.lateLabel(minutes)) { onRunningLate(minutes) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(voice.runningLateSupport)
        }
    }

    private static func lateLabel(_ minutes: Int) -> String {
        let target = Date().addingTimeInterval(Double(minutes) * 60)
        return "+\(minutes) · \(target.formatted(date: .omitted, time: .shortened))"
    }

    // MARK: - The clock

    /// The time in a soft coral halo, with the dumbbell above it.
    ///
    /// The halo is drawn rather than illustrated so it inherits the accent and
    /// costs nothing at 6:30 on a cold start. It does not pulse: a breathing
    /// glow on the one screen someone looks at half-asleep is an animation
    /// asking for attention it has already got.
    private var clock: some View {
        ZStack {
            RadialGradient(
                colors: [Theme.accentWash, Theme.accentWash.opacity(0)],
                center: .center,
                startRadius: 10,
                endRadius: 168
            )
            .frame(width: 336, height: 336)
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 60, height: 60)
                    .background(Theme.accent.opacity(0.12), in: .circle)
                    .accessibilityHidden(true)

                Text(session.alarmTime.displayString)
                    .font(.system(size: 66, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                VStack(spacing: 2) {
                    Text(voice.clockCaption)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)

                    Text(session.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
        }
        .frame(height: 336)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.alarmTime.displayString), \(voice.clockCaption)")
    }

    // MARK: - Copy

    /// Two lines, and they change with the hour.
    ///
    /// While the snooze runs, the first line becomes the time it ends. That is
    /// the only number a half-asleep person needs, and stating it removes the
    /// urge to keep checking.
    private var headline: some View {
        VStack(spacing: 6) {
            Text(headlineText)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.ink)

            Text(supportText)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var headlineText: String {
        if isSnoozing { return voice.snoozeHeadline(until: clock(session.snoozeExpiresAt)) }
        if isRunningLate { return voice.runningLateHeadline(until: clock(session.runningLateUntil)) }
        return voice.alarmGreeting
    }

    private var supportText: String {
        if isSnoozing { return voice.snoozeSupport }
        if isRunningLate { return voice.runningLateSupport }
        return voice.alarmSupport
    }

    private func clock(_ date: Date?) -> String {
        date.map { TimeOfDay(from: $0).displayString } ?? ""
    }

    // MARK: - Actions

    /// One coral capsule and, beneath it, plain text.
    ///
    /// The secondaries are text rather than cards so the hierarchy survives
    /// being read at a glance in the dark. They are never hidden: at 6:31 a
    /// user must always be able to see the way out, or they will go looking for
    /// it in Settings instead.
    private var actions: some View {
        VStack(spacing: 4) {
            MorningPrimaryButton(
                title: voice.primaryAction,
                systemImage: voice.primarySymbol,
                trailingImage: "arrow.right"
            ) {
                onGoing()
            }
            .padding(.bottom, 10)

            if voice.allowsSnooze {
                textAction(voice.snoozeAction, action: onSnooze)
            }

            // PLACEHOLDER UI: designed in Step 3
            // Go Later only, once. Gone after it is used; the absence is the
            // only message about it.
            if !runningLateOptions.isEmpty {
                textAction(voice.runningLateAction) { isChoosingLate = true }
            }

            textAction(session.hasSnoozed ? voice.cantTodayAction : voice.changePlanAction, action: onCantToday)
        }
    }

    private func textAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Morning") {
    AlarmFiredView(
        session: GymSession(
            day: Date(),
            slotID: nil,
            alarmTime: TimeOfDay(hour: 6, minute: 30),
            isMorningSession: true,
            getReadyMinutes: 15,
            travelMinutes: 20
        ),
        onGoing: {},
        onSnooze: {},
        runningLateOptions: [],
        onRunningLate: { _ in },
        onCantToday: {}
    )
}

#Preview("Evening") {
    AlarmFiredView(
        session: GymSession(
            day: Date(),
            slotID: nil,
            alarmTime: TimeOfDay(hour: 18, minute: 0),
            isMorningSession: false,
            getReadyMinutes: 15,
            travelMinutes: 20
        ),
        onGoing: {},
        onSnooze: {},
        runningLateOptions: [15, 30, 60],
        onRunningLate: { _ in },
        onCantToday: {}
    )
}
