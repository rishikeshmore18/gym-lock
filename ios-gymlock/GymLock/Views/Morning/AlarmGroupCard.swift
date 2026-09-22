import SwiftUI

/// The grouped card the Alarm screen's controls live in: the repeat card's
/// Liquid Glass surface, radius and padding, holding a stack of rows.
///
/// Content is clipped to the card's shape *before* the glass goes on, for
/// two reasons: a row's pressed wash reaches the card's edges without
/// escaping its corners, and anything inserted or removed with a transition
/// (the snooze wheel, the duration row) grows out of the card rather than
/// drawing over the cards around it mid-animation.
struct AlarmGroupCard<Content: View>: View {
    static var radius: CGFloat { 22 }

    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(.rect(cornerRadius: Self.radius))
        .glassCard(radius: Self.radius)
        .accessibilityElement(children: .contain)
    }
}

/// The hairline between rows in an `AlarmGroupCard`, matching the one under
/// the repeat card's title. `inset` lines it up with row text that sits
/// after a leading checkmark column.
struct AlarmRowDivider: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// A small lowercase heading above a group, after Apple's "Standard".
struct AlarmSectionHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.inkSecondary)
            .padding(.leading, 16)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One tappable row with a trailing value and chevron, after Apple's
/// "Sound   Old Phone ›".
struct AlarmValueRow: View {
    let title: String
    let value: String
    var showsChevron: Bool = true
    var valueIsActive: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 15, weight: valueIsActive ? .semibold : .medium))
                .foregroundStyle(valueIsActive ? Theme.ink : Theme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .frame(minHeight: 50)
        .accessibilityElement(children: .combine)
    }
}
