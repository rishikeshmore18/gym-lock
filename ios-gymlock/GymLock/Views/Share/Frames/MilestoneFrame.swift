import SwiftUI

/// A threshold, on the day it was crossed.
///
/// A large number and its label, or the label alone, with a single coral
/// hairline underneath. No badge is drawn because no badge system exists yet,
/// and inventing artwork for one would be a promise the Progress tab does not
/// keep.
struct MilestoneFrame: View {
    let kind: StoryElementKind
    let context: ShareContext
    let layout: StoryLayout
    let scale: Double
    let isAnimated: Bool

    @State private var hasSettled = false

    /// Settled for export regardless of lifecycle; see `MomentumFrame`.
    private var isSettled: Bool { isAnimated ? hasSettled : true }

    var body: some View {
        switch kind {
        case .statement:
            statement
        case .facts:
            StoryFactsText(lines: [context.dateFact], layout: layout, scale: scale)
        case .mark:
            StoryMarkView(layout: layout, scale: scale)
        default:
            EmptyView()
        }
    }

    private var statement: some View {
        VStack(alignment: .leading, spacing: layout.fontSize(18, elementScale: scale)) {
            if let number = context.milestone?.heroNumber {
                Text("\(number)")
                    .font(StoryTypography.heroNumber(layout, scale: scale, size: StoryLayout.TypeScale.milestoneNumber))
                    .monospacedDigit()
                    .foregroundStyle(StoryTypography.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                StoryEyebrowText(
                    text: context.milestone?.label ?? "",
                    layout: layout,
                    scale: scale,
                    color: StoryTypography.primary
                )
            } else {
                StoryStatementText(
                    text: Text(context.milestone?.title ?? ""),
                    layout: layout,
                    scale: scale
                )
            }

            Rectangle()
                .fill(Theme.accent)
                .frame(width: layout.fontSize(140, elementScale: scale), height: layout.fontSize(6, elementScale: scale))
        }
        .fixedSize(horizontal: false, vertical: true)
        .scaleEffect(isSettled ? 1 : 0.94, anchor: .bottomLeading)
        .opacity(isSettled ? 1 : 0)
        .task {
            guard isAnimated else { return }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) { hasSettled = true }
        }
    }
}
