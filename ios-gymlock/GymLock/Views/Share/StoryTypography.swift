import SwiftUI

/// The type roles a frame may use, and nothing else.
///
/// System faces only — SF Pro, SF Rounded, SF Mono, New York — so the export
/// is guaranteed to render on every device and nothing needs licensing. Sizes
/// are authored in canvas points on a 1080-wide canvas and scaled by the
/// layout, then by the element's own scale when the user has resized it.
enum StoryTypography {
    /// Text at 100 %, 80 % and 55 % white — the only three the frames use.
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.80)
    static let tertiary = Color.white.opacity(0.55)

    /// The photo-less canvas, and the gradient it is allowed to have.
    static let cardTop = Color(red: 0.043, green: 0.043, blue: 0.047)
    static let cardBottom = Color(red: 0.078, green: 0.078, blue: 0.086)

    /// Condensed heavy grotesk: athletic and editorial without the
    /// brush-script cliché.
    static func statement(_ layout: StoryLayout, scale: Double) -> Font {
        .system(size: layout.fontSize(StoryLayout.TypeScale.statement, elementScale: scale), weight: .black)
    }

    static func statementTracking(_ layout: StoryLayout, scale: Double) -> CGFloat {
        layout.fontSize(StoryLayout.TypeScale.statement, elementScale: scale) * StoryLayout.TypeScale.statementTracking
    }

    /// Rounded heavy numerals, tabular so 7 and 127 sit identically.
    static func heroNumber(_ layout: StoryLayout, scale: Double, size: CGFloat = StoryLayout.TypeScale.heroNumber) -> Font {
        .system(size: layout.fontSize(size, elementScale: scale), weight: .heavy, design: .rounded)
    }

    static func heroLabel(_ layout: StoryLayout, scale: Double, size: CGFloat = StoryLayout.TypeScale.heroLabel) -> Font {
        .system(size: layout.fontSize(size, elementScale: scale), weight: .black)
    }

    static func eyebrow(_ layout: StoryLayout, scale: Double) -> Font {
        .system(size: layout.fontSize(StoryLayout.TypeScale.eyebrow, elementScale: scale), weight: .semibold)
    }

    static func eyebrowTracking(_ layout: StoryLayout, scale: Double) -> CGFloat {
        layout.fontSize(StoryLayout.TypeScale.eyebrow, elementScale: scale) * StoryLayout.TypeScale.eyebrowTracking
    }

    static func fact(_ layout: StoryLayout, scale: Double) -> Font {
        .system(size: layout.fontSize(StoryLayout.TypeScale.fact, elementScale: scale), weight: .medium)
    }

    static func receiptRow(_ layout: StoryLayout, scale: Double) -> Font {
        .system(size: layout.fontSize(StoryLayout.TypeScale.receiptRow, elementScale: scale), weight: .medium, design: .monospaced)
    }

    static func annotation(_ layout: StoryLayout, scale: Double) -> Font {
        .system(size: layout.fontSize(StoryLayout.TypeScale.annotation, elementScale: scale), weight: .regular, design: .serif)
    }
}

// MARK: - Shared text pieces

/// A statement line: condensed, black, tracked tight, single line that
/// shrinks rather than wraps.
struct StoryStatementText: View {
    let text: Text
    let layout: StoryLayout
    let scale: Double

    var body: some View {
        text
            .font(StoryTypography.statement(layout, scale: scale))
            .fontWidth(.condensed)
            .tracking(StoryTypography.statementTracking(layout, scale: scale))
            .foregroundStyle(StoryTypography.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One or two supporting lines, 80 % white.
struct StoryFactsText: View {
    let lines: [String]
    let layout: StoryLayout
    let scale: Double
    /// Index of a line whose trailing glyph is drawn coral, if any.
    var accentGlyphLine: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: layout.fontSize(10, elementScale: scale)) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                if index == accentGlyphLine, let split = Self.splitTrailingGlyph(line) {
                    (Text(split.body) + Text(split.glyph).foregroundStyle(Theme.accent))
                        .font(StoryTypography.fact(layout, scale: scale))
                        .foregroundStyle(StoryTypography.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text(line)
                        .font(StoryTypography.fact(layout, scale: scale))
                        .foregroundStyle(StoryTypography.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Separates a trailing "✓" so it can be tinted on its own.
    private static func splitTrailingGlyph(_ line: String) -> (body: String, glyph: String)? {
        guard let last = line.last, last == "✓" else { return nil }
        return (String(line.dropLast()), String(last))
    }
}

/// Quiet uppercase label.
struct StoryEyebrowText: View {
    let text: String
    let layout: StoryLayout
    let scale: Double
    var color: Color = StoryTypography.secondary

    var body: some View {
        Text(text.uppercased())
            .font(StoryTypography.eyebrow(layout, scale: scale))
            .tracking(StoryTypography.eyebrowTracking(layout, scale: scale))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)
    }
}
