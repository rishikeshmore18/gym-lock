import SwiftUI

/// `DAY 30`, with what the days added up to.
///
/// The number is the coral. Facts are the verified visits and, when there is
/// an honest denominator, the percentage of due sessions the user showed up
/// for. The optional inset is the before-picture with a hairline border and a
/// one-word caption — no arrows, no handwriting.
struct JourneyFrame: View {
    let kind: StoryElementKind
    let context: ShareContext
    let layout: StoryLayout
    let scale: Double
    let dayZeroImage: UIImage?

    var body: some View {
        switch kind {
        case .statement:
            statement
        case .facts:
            StoryFactsText(lines: factLines, layout: layout, scale: scale)
        case .inset:
            if context.journey?.dayZeroPhoto != nil {
                inset
            }
        case .mark:
            StoryMarkView(layout: layout, scale: scale)
        }
    }

    private var statement: some View {
        HStack(alignment: .lastTextBaseline, spacing: layout.fontSize(20, elementScale: scale)) {
            Text("DAY")
                .font(StoryTypography.heroLabel(layout, scale: scale, size: StoryLayout.TypeScale.journeyLabel))
                .fontWidth(.condensed)
                .foregroundStyle(StoryTypography.primary)

            Text("\(context.journey?.dayNumber ?? 0)")
                .font(StoryTypography.heroNumber(layout, scale: scale, size: StoryLayout.TypeScale.journeyNumber))
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var factLines: [String] {
        guard let journey = context.journey else { return [] }
        var lines = ["\(journey.verifiedVisits) verified \(journey.verifiedVisits == 1 ? "visit" : "visits")"]
        if let percent = journey.percentText { lines.append(percent) }
        return lines
    }

    /// The before-picture, small and bordered.
    ///
    /// Colour as the size anchor with the image in an overlay: a `.fill`
    /// image would set its own layout width and push the caption about.
    private var inset: some View {
        let width = layout.x(StoryLayout.insetWidthFraction) * CGFloat(scale)
        let height = width / ProgressPhotoMetrics.aspectRatio
        let radius = layout.fontSize(14, elementScale: scale)

        return VStack(alignment: .leading, spacing: layout.fontSize(10, elementScale: scale)) {
            Color(white: 0.16)
                .frame(width: width, height: height)
                .overlay {
                    if let dayZeroImage {
                        Image(uiImage: dayZeroImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(.rect(cornerRadius: radius))
                .overlay {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(Color.white.opacity(0.7), lineWidth: layout.fontSize(2, elementScale: scale))
                }

            Text("Day 0")
                .font(StoryTypography.annotation(layout, scale: scale))
                .italic()
                .foregroundStyle(StoryTypography.secondary)
        }
        .fixedSize()
    }
}
