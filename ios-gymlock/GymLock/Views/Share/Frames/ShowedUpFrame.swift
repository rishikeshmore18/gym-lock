import SwiftUI

/// `SHOWED UP.` — the coral full stop is the frame's one accent.
///
/// Facts: gym verified, plus the arrival time when the event log has one, or
/// the date when it does not. A second, smaller line names the streak once
/// there is one worth naming.
struct ShowedUpFrame: View {
    let kind: StoryElementKind
    let context: ShareContext
    let layout: StoryLayout
    let scale: Double
    let isAnimated: Bool

    @State private var hasAppeared = false

    /// The export never runs the appearance lifecycle, so the settled state
    /// is decided by `isAnimated`, not by whether `task` has fired.
    private var isChecked: Bool { isAnimated ? hasAppeared : true }

    var body: some View {
        switch kind {
        case .statement:
            StoryStatementText(
                text: Text("SHOWED UP") + Text(".").foregroundStyle(Theme.accent),
                layout: layout,
                scale: scale
            )
        case .facts:
            facts
        case .mark:
            StoryMarkView(layout: layout, scale: scale)
        default:
            EmptyView()
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: layout.fontSize(10, elementScale: scale)) {
            HStack(alignment: .firstTextBaseline, spacing: layout.fontSize(14, elementScale: scale)) {
                // The check draws in once in preview; the export is settled.
                Image(systemName: "checkmark")
                    .font(.system(size: layout.fontSize(38, elementScale: scale), weight: .bold))
                    .foregroundStyle(StoryTypography.secondary)
                    .scaleEffect(isChecked ? 1 : 0.6)
                    .opacity(isChecked ? 1 : 0)

                Text(verifiedLine)
                    .font(StoryTypography.fact(layout, scale: scale))
                    .foregroundStyle(StoryTypography.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if context.streak.weeks >= 2 {
                Text("\(context.streak.weeks)-week streak")
                    .font(StoryTypography.fact(layout, scale: scale))
                    .foregroundStyle(StoryTypography.tertiary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .task {
            guard isAnimated else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.7).delay(0.18)) {
                hasAppeared = true
            }
        }
    }

    private var verifiedLine: String {
        if let arrival = context.arrivalTime {
            return "Gym verified · \(ShareContext.timeText(arrival))"
        }
        return "Gym verified · \(context.dateFact)"
    }
}
