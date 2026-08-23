import SwiftUI

/// The screen the user meets the instant the alarm is silenced.
///
/// It contains almost nothing on purpose. Someone who has been awake for four
/// seconds cannot read a paragraph, will not appreciate a streak, and does not
/// need a calendar. They need one sentence that removes the excuse and three
/// buttons in descending order of how much the app would like them pressed.
///
/// Anything added here is something the user has to look past to reach the
/// decision, which is the only thing this screen is for.
struct AlarmFiredView: View {
    let alarmTime: TimeOfDay
    let onGoing: () -> Void
    /// Called with how many minutes to push today's session by.
    let onMoveTime: (Int) -> Void
    let onCantToday: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @State private var isMovingTime = false

    /// Offered pushes. Bounded on purpose — an open-ended "later" is how a
    /// morning quietly disappears.
    private static let moveOptions = [30, 60, 120]

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 12)

                hero
                    .opacity(hasAppeared ? 1 : 0)
                    .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.96)

                Spacer(minLength: 18)

                headline
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared || reduceMotion ? 0 : 18)

                Spacer(minLength: 14)

                SparkMark()
                    .opacity(hasAppeared ? 1 : 0)

                Spacer(minLength: 14)

                actions
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared || reduceMotion ? 0 : 16)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.bottom, 12)
        }
        .task {
            // A short beat before anything moves: the alarm has only just
            // stopped, and content arriving on the same frame reads as jarring.
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(Theme.settle) { hasAppeared = true }
        }
        .confirmationDialog(
            "Move today to when?",
            isPresented: $isMovingTime,
            titleVisibility: .visible
        ) {
            ForEach(Self.moveOptions, id: \.self) { minutes in
                Button(Self.moveLabel(minutes)) { onMoveTime(minutes) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Today only. Your other mornings stay exactly as they are.")
        }
    }

    private static func moveLabel(_ minutes: Int) -> String {
        let target = Date().addingTimeInterval(Double(minutes) * 60)
        let clock = target.formatted(date: .omitted, time: .shortened)
        return minutes < 60
            ? "in \(minutes) min · \(clock)"
            : "in \(minutes / 60) hr · \(clock)"
    }

    // MARK: - Pieces

    private var hero: some View {
        VStack(spacing: 18) {
            HStack(spacing: 7) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 15, weight: .bold))
                Text("GymLock")
                    .font(.system(size: 19, weight: .bold))
            }
            .foregroundStyle(Theme.accent)

            HaloedGlyph(systemName: "alarm.fill", size: 96, isPulsing: true)
                .frame(height: 190)

            StatusPill(label: "alarm fired", value: alarmTime.displayString)
        }
    }

    private var headline: some View {
        VStack(spacing: 2) {
            Text("you don't need to feel ready.")
            Text("just start moving.")
        }
        .font(.system(size: 30, weight: .bold))
        .foregroundStyle(Theme.ink)
        .multilineTextAlignment(.center)
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            MorningPrimaryButton(
                title: "I'm going",
                systemImage: "dumbbell.fill",
                trailingImage: nil
            ) {
                onGoing()
            }

            MorningChoiceRow(
                title: "move today's time",
                systemImage: "clock.fill"
            ) {
                isMovingTime = true
            }

            MorningChoiceRow(
                title: "can't today",
                systemImage: "calendar"
            ) {
                onCantToday()
            }
        }
    }
}

#Preview {
    AlarmFiredView(
        alarmTime: TimeOfDay(hour: 6, minute: 30),
        onGoing: {},
        onMoveTime: { _ in },
        onCantToday: {}
    )
}
