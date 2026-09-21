import SwiftUI

/// Shown when the window has closed without the user reaching the gym.
///
/// Three doors, none of them locked. The tone matters more here than anywhere
/// else in the flow: a person who has just watched their own timer run out does
/// not need to be told they failed, and an app that punishes this moment is an
/// app that gets deleted at 7:20 in the morning.
///
/// "Still going" gives a short grace period, not a fresh timer. Restarting the
/// full window would make the deadline meaningless.
struct PlansChangedView: View {
    let voice: SessionVoice
    let onStillGoing: () -> Void
    let onQuickWorkout: () -> Void
    let onCantToday: () -> Void

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                MorningHeader()

                ScrollView {
                    VStack(spacing: 22) {
                        HaloedGlyph(systemName: "clock.arrow.circlepath", size: 86)
                            .frame(height: 170)

                        VStack(spacing: 8) {
                            Text("plans changed?")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(Theme.ink)

                            Text(voice.plansChangedSupport)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Theme.inkSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(spacing: 12) {
                            MorningPrimaryButton(
                                title: "still going",
                                systemImage: "figure.run",
                                trailingImage: nil
                            ) {
                                onStillGoing()
                            }

                            MorningChoiceRow(
                                title: "quick workout instead",
                                subtitle: "keeps your momentum",
                                systemImage: "house.fill"
                            ) {
                                onQuickWorkout()
                            }

                            MorningChoiceRow(
                                title: "can't today",
                                subtitle: "the next opportunity still counts",
                                systemImage: "calendar"
                            ) {
                                onCantToday()
                            }
                        }

                        Text("choosing \"still going\" gives you \(GymSession.graceMinutes) more minutes — not a new window.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.inkTertiary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Theme.pageMargin)
                    .padding(.top, 6)
                    .padding(.bottom, 26)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}
