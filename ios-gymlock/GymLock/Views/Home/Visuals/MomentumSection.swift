import SwiftUI

/// The proof layer under the action cards.
///
/// Home has two jobs and this is the second one. The cards above answer "what do
/// I do now"; this answers "am I actually doing this" — in one glance, without
/// asking the user to log anything and without inventing a single mark.
///
/// The layout is deliberately split: the claim on the left ("4/5 this week"),
/// the evidence for it on the right (the seven days that produced the number).
/// A metric with its own receipt next to it is believed; a metric on its own is
/// just a number the app is asserting.
struct MomentumSection: View {
    let field: MomentumField
    /// Optional destination; without one the card is inert and shows no
    /// affordance.
    var onTap: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasRevealed = false

    /// Caps the day dots on wide screens. Past this they stop reading as marks
    /// and start reading as buttons.
    private static let maxDot: CGFloat = 30

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

    private var week: some View {
        HStack(spacing: 4) {
            ForEach(Array(field.days.enumerated()), id: \.element.id) { index, day in
                VStack(spacing: 7) {
                    Text(day.label)
                        .font(.system(size: 10, weight: day.isToday ? .bold : .medium))
                        .foregroundStyle(day.isToday ? Theme.ink : Theme.inkTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    MomentumDot(mark: day.mark, isToday: day.isToday)
                        .frame(maxWidth: Self.maxDot)
                }
                .frame(maxWidth: .infinity)
                .opacity(hasRevealed ? 1 : 0)
                .scaleEffect(hasRevealed ? 1 : 0.7)
                .animation(revealAnimation(index: index), value: hasRevealed)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// A short left-to-right cascade, the way the week itself runs. Under
    /// Reduce Motion the days are simply there.
    private func revealAnimation(index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return .spring(response: 0.44, dampingFraction: 0.78)
            .delay(Double(index) * 0.035)
    }
}

// MARK: - One day

/// A single day of the week.
///
/// Every state is the same circle at a different weight, so the row reads as one
/// material: solid for a day that counted, an open ring for one that never
/// resolved, a small dot for a day nothing was ever asked of.
private struct MomentumDot: View {
    let mark: MomentumMark
    let isToday: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { shape }
            .overlay {
                if isToday {
                    // Today is circled rather than filled. It has not earned a
                    // fill yet, and pretending otherwise would be the one lie
                    // this whole layer exists to avoid.
                    Circle()
                        .strokeBorder(Theme.ink, lineWidth: 1.5)
                        .padding(-3.5)
                }
            }
            .scaleEffect(isBreathing ? 1.05 : 1)
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: mark)
            .task(id: shouldBreathe) {
                guard shouldBreathe, !reduceMotion else {
                    isBreathing = false
                    return
                }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
    }

    /// Only today, and only while it is still open. A pulse on a finished day
    /// would be decoration; here it is the one thing left to do.
    private var shouldBreathe: Bool { isToday && mark == .planned }

    @ViewBuilder
    private var shape: some View {
        switch mark {
        case .verified:
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.accentWarm, Theme.accent, Theme.accentDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Theme.accent.opacity(0.35), radius: 4, y: 2)

        case .preserved:
            Circle()
                .fill(Theme.accent.opacity(0.16))
                .overlay {
                    Circle().strokeBorder(Theme.accent.opacity(0.75), lineWidth: 2)
                }

        case .missed:
            // Deflated rather than marked wrong. A red cross on a Tuesday is
            // the fastest way to lose someone who already feels behind.
            Circle()
                .fill(Theme.border)
                .scaleEffect(0.58)

        case .excused:
            Circle()
                .fill(Theme.surfaceMuted)
                .scaleEffect(0.82)

        case .unresolved:
            Circle()
                .strokeBorder(Theme.border, lineWidth: 2)

        case .planned:
            Circle()
                .fill(Theme.surfaceMuted)

        case .rest:
            Circle()
                .fill(Theme.border.opacity(0.7))
                .scaleEffect(0.26)
        }
    }
}

// MARK: - Previews

#Preview("Momentum · mid-week") {
    let marks: [MomentumMark] = [.verified, .rest, .verified, .planned, .planned, .rest, .rest]

    return MomentumSection(
        field: MomentumField(
            days: marks.enumerated().map { index, mark in
                MomentumDay(
                    column: index,
                    label: Weekday.allCases[index].shortLabel,
                    mark: mark,
                    isToday: index == 3
                )
            },
            verifiedCount: 2,
            preservedCount: 0,
            targetCount: 4,
            hasSchedule: true
        )
    )
    .padding(18)
    .background(Theme.canvas)
}

#Preview("Momentum · mixed week") {
    let marks: [MomentumMark] = [.verified, .preserved, .verified, .missed, .verified, .rest, .unresolved]

    return MomentumSection(
        field: MomentumField(
            days: marks.enumerated().map { index, mark in
                MomentumDay(
                    column: index,
                    label: Weekday.allCases[index].shortLabel,
                    mark: mark,
                    isToday: index == 6
                )
            },
            verifiedCount: 3,
            preservedCount: 1,
            targetCount: 5,
            hasSchedule: true
        ),
        onTap: {}
    )
    .padding(18)
    .background(Theme.canvas)
}

#Preview("Momentum · week one") {
    MomentumSection(
        field: MomentumField(
            days: (0..<7).map { index in
                MomentumDay(
                    column: index,
                    label: Weekday.allCases[index].shortLabel,
                    mark: index < 4 ? .planned : .rest,
                    isToday: index == 0
                )
            },
            verifiedCount: 0,
            preservedCount: 0,
            targetCount: 4,
            hasSchedule: true
        )
    )
    .padding(18)
    .background(Theme.canvas)
}
