import SwiftUI

/// The proof layer under the action cards.
///
/// Home has two jobs and this is the second one. The cards above answer "what do
/// I do now"; this answers "is this actually working for me" — without asking the
/// user to log anything, and without inventing a single mark. It is deliberately
/// not a calendar: the columns carry weekdays so a pattern is visible, but the
/// field reads as accumulated texture rather than a grid of dates.
struct MomentumSection: View {
    let field: MomentumField
    /// Optional destination; without one the section is inert and shows no
    /// affordance.
    var onTap: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            card
        }
        .task {
            guard !hasRevealed else { return }
            // A beat after the cards have settled, so the two layers arrive in
            // order rather than together.
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 180))
            hasRevealed = true
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("MOMENTUM")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Theme.inkSecondary)

            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.inkTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
        .contentShape(.rect)
        .onTapGesture {
            guard let onTap else { return }
            Haptics.selection()
            onTap()
        }
    }

    // MARK: Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            marks
            labels
            Divider().overlay(Theme.border)
            summary
        }
        .padding(16)
        .background(Theme.surface, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Four rows of seven. Each mark sizes itself from the column width, so the
    /// field fills whatever it is given without a single fixed dimension.
    private var marks: some View {
        VStack(spacing: 7) {
            ForEach(field.weeks.indices, id: \.self) { row in
                HStack(spacing: 7) {
                    ForEach(field.weeks[row].indices, id: \.self) { column in
                        MomentumMarkView(
                            mark: field.weeks[row][column],
                            isToday: row == field.todayRow && column == field.todayColumn
                        )
                        .opacity(hasRevealed ? 1 : 0)
                        .scaleEffect(hasRevealed ? 1 : 0.55, anchor: .bottom)
                        .animation(
                            revealAnimation(index: row * 7 + column),
                            value: hasRevealed
                        )
                    }
                }
            }
        }
    }

    private var labels: some View {
        HStack(spacing: 7) {
            ForEach(field.weekdayLabels.indices, id: \.self) { column in
                let isToday = column == field.todayColumn

                Text(field.weekdayLabels[column])
                    .font(.system(size: 10, weight: isToday ? .bold : .medium))
                    .foregroundStyle(isToday ? Theme.ink : Theme.inkTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        if let value = field.summaryValue {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())

                Text(field.summaryLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)

                Spacer(minLength: 0)

                if let note = field.preservedNote {
                    Text(note)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        } else {
            Text(field.emptyMessage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Motion

    /// A short stagger across the field, row-major. Under Reduce Motion the
    /// marks are simply there.
    private func revealAnimation(index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return .spring(response: 0.42, dampingFraction: 0.8)
            .delay(Double(index) * 0.008)
    }

    private var accessibilityText: String {
        guard let value = field.summaryValue else { return field.emptyMessage }
        var text = "Last four weeks: \(value) sessions showed up at the gym."
        if let note = field.preservedNote {
            text += " \(note)."
        }
        return text
    }
}

// MARK: - One mark

/// A single day.
///
/// Every state is the same silhouette at a different weight, so the field reads
/// as one material: a full capsule for a day that counted, a stub for a day that
/// broke, a whisper for a day that was never a session.
private struct MomentumMarkView: View {
    let mark: MomentumMark
    let isToday: Bool

    /// Taller than wide, like the bars this borrows its language from.
    private static let aspect: CGFloat = 0.78

    var body: some View {
        Color.clear
            .aspectRatio(Self.aspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { shape }
            .overlay {
                if isToday {
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.ink, lineWidth: 1.6)
                }
            }
    }

    @ViewBuilder
    private var shape: some View {
        switch mark {
        case .verified:
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.accentDeep, Theme.accent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

        case .preserved:
            Capsule(style: .continuous)
                .fill(Theme.accent.opacity(0.18))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1.3)
                }

        case .excused:
            Capsule(style: .continuous)
                .fill(Theme.surfaceMuted)

        case .missed:
            Capsule(style: .continuous)
                .fill(Theme.border)
                .scaleEffect(x: 1, y: 0.36)

        case .planned:
            Capsule(style: .continuous)
                .fill(Theme.surface)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1.3)
                }

        case .blank:
            Capsule(style: .continuous)
                .fill(Theme.border.opacity(0.55))
                .scaleEffect(x: 1, y: 0.16)
        }
    }
}

// MARK: - Previews

#Preview("Momentum · with a record") {
    let weeks: [[MomentumMark]] = [
        [.verified, .blank, .verified, .blank, .verified, .blank, .blank],
        [.verified, .blank, .missed, .blank, .verified, .preserved, .blank],
        [.verified, .blank, .verified, .blank, .verified, .blank, .blank],
        [.verified, .blank, .planned, .blank, .planned, .blank, .blank],
    ]

    return MomentumSection(
        field: MomentumField(
            weeks: weeks,
            weekdayLabels: ["M", "T", "W", "T", "F", "S", "S"],
            todayRow: 3,
            todayColumn: 1,
            verifiedCount: 9,
            preservedCount: 1,
            dueCount: 11,
            hasHistory: true,
            emptyMessage: ""
        )
    )
    .padding(18)
    .background(Theme.canvas)
}

#Preview("Momentum · day one") {
    MomentumSection(
        field: MomentumField(
            weeks: Array(
                repeating: [.blank, .blank, .blank, .blank, .blank, .blank, .blank],
                count: 4
            ),
            weekdayLabels: ["M", "T", "W", "T", "F", "S", "S"],
            todayRow: 3,
            todayColumn: 2,
            verifiedCount: 0,
            preservedCount: 0,
            dueCount: 0,
            hasHistory: false,
            emptyMessage: "Your record starts tomorrow."
        )
    )
    .padding(18)
    .background(Theme.canvas)
}
