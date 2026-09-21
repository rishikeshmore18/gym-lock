import SwiftUI

/// The moment the user actually leaves.
///
/// This is the only celebratory screen before the gym, and it is deliberately
/// short-lived: one line of praise, one confirmation of what happens next, and a
/// way back to the countdown. The person reading it is walking, often outdoors,
/// probably holding a bag — so nothing here needs to be read carefully.
///
/// It is also the point where GymLock stops pushing. No alarm plays again for
/// this session, and exactly one notification has been sent.
struct DepartedView: View {
    let session: GymSession
    let onContinue: () -> Void

    private var voice: SessionVoice { SessionVoice(session: session) }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            // A warm wash rather than the flat canvas: this is the one screen
            // in the flow that is allowed to feel like a reward.
            LinearGradient(
                colors: [Theme.accentWash, Theme.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                MorningHeader()

                Spacer(minLength: 10)

                VStack(spacing: 20) {
                    Text("let's go!!")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.94)
                        .opacity(hasAppeared ? 1 : 0)

                    VStack(spacing: 2) {
                        Text(voice.departureSupport)
                        Text("just get there.")
                    }
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(hasAppeared ? 1 : 0)

                    runner
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared || reduceMotion ? 0 : 14)

                    progressStrip
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared || reduceMotion ? 0 : 14)
                }
                .padding(.horizontal, Theme.pageMargin)

                Spacer(minLength: 10)

                MorningPrimaryButton(
                    title: "back to my window",
                    systemImage: "timer",
                    trailingImage: nil
                ) {
                    onContinue()
                }
                .padding(.horizontal, Theme.pageMargin)
                .padding(.bottom, 14)
                .opacity(hasAppeared ? 1 : 0)
            }
        }
        .task {
            withAnimation(Theme.settle) { hasAppeared = true }
        }
    }

    /// A simple figure heading toward a building, drawn rather than bundled so
    /// it inherits the accent and needs no asset.
    private var runner: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [Theme.accentWash, Theme.accentWash.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            HStack(spacing: 26) {
                Image(systemName: "figure.run")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(Theme.accent)

                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.accent.opacity(0.5))

                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.accent.opacity(0.75))
            }
        }
        .frame(height: 150)
        .accessibilityHidden(true)
    }

    /// Two beats: home left, gym next.
    private var progressStrip: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Theme.accent, in: .circle)

                Text("home left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)

            HStack(spacing: 10) {
                Text("2")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 32, height: 32)
                    .background(Theme.surfaceMuted, in: .circle)
                    .overlay { Circle().strokeBorder(Theme.border, lineWidth: 1) }

                Text("gym next")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .warmCard(radius: 18)
    }
}
