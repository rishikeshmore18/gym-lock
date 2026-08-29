import SwiftUI

/// The horizontally endless date strip.
///
/// Rendering is lazy and the underlying window is bounded — see
/// `CalendarWindow`. Scrolling is free: there is no snapping behaviour, so a
/// flick carries natural momentum instead of being yanked to a grid.
struct CalendarStripView: View {
    let window: CalendarWindow
    let index: DayStatusIndex
    let selectedDay: Date
    @Binding var leadingDay: Date?
    let onSelect: (Date) -> Void

    /// Days visible at once. Matches a readable week without crowding the
    /// smallest iPhone.
    private static let visibleDays = 7
    private static let spacing: CGFloat = 4
    private static let margin: CGFloat = 18

    @ScaledMetric(relativeTo: .subheadline) private var markerSize: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var weekdayHeight: CGFloat = 18

    private var cellHeight: CGFloat { markerSize + weekdayHeight + 26 }

    var body: some View {
        GeometryReader { proxy in
            let cellWidth = Self.cellWidth(for: proxy.size.width)

            ScrollView(.horizontal) {
                LazyHStack(spacing: Self.spacing) {
                    ForEach(window.days, id: \.self) { date in
                        let day = index.day(for: date)

                        DayMarkerCell(
                            day: day,
                            isSelected: day.date == selectedDay,
                            markerSize: min(markerSize, cellWidth - 6),
                            height: cellHeight
                        ) {
                            onSelect(day.date)
                        }
                        .frame(width: cellWidth)
                    }
                }
                .scrollTargetLayout()
            }
            // Bound to the leading day rather than a snapping behaviour: it
            // reports where the user is so the window can grow ahead of them,
            // and it survives days being added at either end.
            .scrollPosition(id: $leadingDay, anchor: .leading)
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, Self.margin, for: .scrollContent)
        }
        .frame(height: cellHeight)
    }

    private static func cellWidth(for width: CGFloat) -> CGFloat {
        let available = width - margin * 2 - spacing * CGFloat(visibleDays - 1)
        return max(44, available / CGFloat(visibleDays))
    }

    static var defaultVisibleDays: Int { visibleDays }
}

// MARK: - One day

/// A weekday label above a status marker.
///
/// Selection and status are separate layers on purpose: the raised container
/// says "you are looking at this day", the marker inside says what happened on
/// it. Selecting a day never overwrites its record.
private struct DayMarkerCell: View {
    let day: TrainingDay
    let isSelected: Bool
    let markerSize: CGFloat
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(Self.weekdayFormatter.string(from: day.date))
                    .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                    .foregroundStyle(weekdayColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                marker
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Theme.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(Theme.border, lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var marker: some View {
        ZStack {
            Circle()
                .fill(fill)

            Circle()
                .strokeBorder(strokeColor, style: strokeStyle)

            Text("\(Calendar.current.component(.day, from: day.date))")
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(numberColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(2)
        }
        .frame(width: markerSize, height: markerSize)
    }

    // MARK: Status styling

    /// Filled marks are things that happened. Outlined marks are days with
    /// nothing on the record, which is not the same as a day that went wrong.
    private var fill: Color {
        switch day.status {
        case .verified: Theme.ink
        case .skipped: Theme.accent
        case .attempted: Color(red: 0.870, green: 0.866, blue: 0.855)
        case .neutral, .future: .clear
        }
    }

    private var numberColor: Color {
        switch day.status {
        case .verified, .skipped: .white
        case .attempted: Theme.ink
        case .neutral: day.isToday ? Theme.ink : Theme.inkSecondary
        case .future: Theme.inkTertiary
        }
    }

    private var strokeColor: Color {
        switch day.status {
        case .verified, .skipped, .attempted: .clear
        // Today gets a solid ring so the user can find themselves instantly,
        // even before anything has been recorded.
        case .neutral: day.isToday ? Theme.ink : Theme.border
        case .future: Theme.border.opacity(0.7)
        }
    }

    private var strokeStyle: StrokeStyle {
        if day.status == .neutral, day.isToday {
            return StrokeStyle(lineWidth: 1.5)
        }
        return StrokeStyle(lineWidth: 1.5, dash: [3, 3])
    }

    private var weekdayColor: Color {
        if isSelected { return Theme.ink }
        return day.status == .future ? Theme.inkTertiary : Theme.inkSecondary
    }

    // MARK: Accessibility

    private var accessibilityLabel: String {
        let date = Self.spokenDateFormatter.string(from: day.date)
        return "\(date), \(statusPhrase)"
    }

    private var statusPhrase: String {
        switch day.status {
        case .verified: "verified workout"
        case .skipped: "skipped workout"
        case .attempted: "partial effort"
        case .neutral: day.isPlanned ? "no workout recorded" : "no workout planned"
        case .future: day.isPlanned ? "workout planned" : "no workout planned"
        }
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    private static let spokenDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return formatter
    }()
}
