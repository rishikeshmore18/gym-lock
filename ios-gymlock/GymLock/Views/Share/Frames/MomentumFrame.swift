import SwiftUI

/// The streak, as one large number.
///
/// `6 WEEKS` on one line with `OF MOMENTUM` under it as the eyebrow, and one
/// fact chosen in order of how much it says: the kept week, then the gym
/// visits so far this week, then the date. The number is the frame's coral.
struct MomentumFrame: View {
    let kind: StoryElementKind
    let context: ShareContext
    let layout: StoryLayout
    let scale: Double
    let isAnimated: Bool

    @State private var shown: Double = 0

    /// The export never runs the appearance lifecycle, so the settled value
    /// is decided by `isAnimated`, not by whether the count has run.
    private var displayed: Double { isAnimated ? shown : Double(context.streak.weeks) }

    var body: some View {
        switch kind {
        case .statement:
            statement
        case .facts:
            StoryFactsText(lines: [fact], layout: layout, scale: scale)
        case .mark:
            StoryMarkView(layout: layout, scale: scale)
        default:
            EmptyView()
        }
    }

    private var statement: some View {
        VStack(alignment: .leading, spacing: layout.fontSize(-14, elementScale: scale)) {
            HStack(alignment: .lastTextBaseline, spacing: layout.fontSize(22, elementScale: scale)) {
                StoryCountingText(
                    value: displayed,
                    font: StoryTypography.heroNumber(layout, scale: scale),
                    color: Theme.accent
                )

                Text(context.streak.weeks == 1 ? "WEEK" : "WEEKS")
                    .font(StoryTypography.heroLabel(layout, scale: scale))
                    .fontWidth(.condensed)
                    .foregroundStyle(StoryTypography.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            StoryEyebrowText(text: "OF MOMENTUM", layout: layout, scale: scale)
                .padding(.leading, layout.fontSize(8, elementScale: scale))
        }
        .fixedSize(horizontal: false, vertical: true)
        .task {
            guard isAnimated else { return }
            // Counts in over 420 ms — under the design's 450 ms ceiling.
            withAnimation(.easeOut(duration: 0.42)) { shown = Double(context.streak.weeks) }
        }
    }

    private var fact: String {
        if context.isReferenceWeekKept {
            return "\(context.sessionDaysThisWeek) of \(context.streak.weeklyGoal) this week"
        }
        if context.verifiedVisitsThisWeek >= 1 {
            let count = context.verifiedVisitsThisWeek
            return "\(count) gym \(count == 1 ? "visit" : "visits") this week"
        }
        return context.dateFact
    }
}

/// A number whose digits roll to their value in preview and sit still in
/// export. `Animatable` on the value so `withAnimation` drives every frame.
struct StoryCountingText: View, Animatable {
    var value: Double
    let font: Font
    let color: Color

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))")
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}
