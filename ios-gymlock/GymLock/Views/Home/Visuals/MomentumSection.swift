import SwiftUI

/// The proof layer under the action cards.
///
/// Home has two jobs and this is the second one. The cards above answer "what do
/// I do now"; this answers "am I actually doing this" — in one glance, without
/// asking the user to log anything and without inventing a single mark.
///
/// The layout is deliberately split: the claim on the left ("4/5 this week"),
/// the evidence for it on the right (one flame per planned gym session).
/// A metric with its own receipt next to it is believed; a metric on its own is
/// just a number the app is asserting.
struct MomentumSection: View {
    let field: MomentumField
    /// Optional destination; without one the card is inert and shows no
    /// affordance.
    var onTap: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasRevealed = false

    var body: some View {
        card
            .contentShape(.rect(cornerRadius: 22))
            .onTapGesture {
                guard let onTap else { return }
                Haptics.selection()
                onTap()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(field.accessibilityText)
            .accessibilityAddTraits(onTap == nil ? [] : .isButton)
            .task {
                guard !hasRevealed else { return }
                // A beat after the cards above have settled, so the two layers
                // of home arrive in order rather than all at once.
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 220))
                hasRevealed = true
            }
    }

    // MARK: Card

    private var card: some View {
        HStack(alignment: .center, spacing: 14) {
            claim
            divider
            week
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(Theme.surface, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.045), radius: 10, y: 4)
    }

    // MARK: Left — the claim

    private var claim: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                GymLockStatusIcon(systemName: "chart.bar.fill", circleSize: 26)

                Text("MOMENTUM")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.inkTertiary)
                }
            }

            Text(field.summaryValue)
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.42, dampingFraction: 0.75), value: field.verifiedCount)
                .padding(.top, 6)

            HStack(spacing: 5) {
                Text(field.caption)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // Home sessions are reported next to the metric, never inside
                // it: they keep momentum, but they are not a trip to the gym.
                if let note = field.homeNote {
                    Text(note)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.top, 2)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    // MARK: Right — the evidence

    /// One flame per planned gym session, lit by verified workouts only. With
    /// no training days there is no honest commitment to draw, so nothing is
    /// drawn; the left side already says "NO DAYS SET".
    @ViewBuilder
    private var week: some View {
        if field.hasSchedule, field.targetCount > 0 {
            MomentumFlameProgress(
                verifiedCount: field.verifiedCount,
                targetCount: field.targetCount,
                isRevealed: hasRevealed
            )
        } else {
            Color.clear.frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Previews

private func previewField(verified: Int, target: Int, home: Int = 0) -> MomentumField {
    MomentumField(
        days: [],
        verifiedCount: verified,
        preservedCount: home,
        targetCount: target,
        hasSchedule: target > 0
    )
}

private func previewCard(_ field: MomentumField) -> some View {
    MomentumSection(field: field)
        .padding(18)
        .background(Theme.canvas)
}

#Preview("0 / 3") { previewCard(previewField(verified: 0, target: 3)) }
#Preview("1 / 3") { previewCard(previewField(verified: 1, target: 3)) }
#Preview("2 / 3") { previewCard(previewField(verified: 2, target: 3)) }
#Preview("3 / 3") { previewCard(previewField(verified: 3, target: 3)) }
#Preview("1 / 4") { previewCard(previewField(verified: 1, target: 4)) }
#Preview("3 / 4") { previewCard(previewField(verified: 3, target: 4)) }
#Preview("4 / 4") { previewCard(previewField(verified: 4, target: 4)) }
#Preview("4 / 5") { previewCard(previewField(verified: 4, target: 5)) }
#Preview("3 / 7") { previewCard(previewField(verified: 3, target: 7)) }
#Preview("No schedule") { previewCard(.empty) }
#Preview("1 / 3 · +1 at home") { previewCard(previewField(verified: 1, target: 3, home: 1)) }

#Preview("Live · new workout, then week complete") {
    @Previewable @State var verified = 1
    VStack(spacing: 20) {
        MomentumSection(field: previewField(verified: verified, target: 3), onTap: {})
        Button("Verify a workout") { verified = verified >= 3 ? 0 : verified + 1 }
    }
    .padding(18)
    .background(Theme.canvas)
}

#Preview("Narrow · 7 days · large text") {
    previewCard(previewField(verified: 5, target: 7, home: 2))
        .frame(width: 375)
        .dynamicTypeSize(.accessibility2)
}
