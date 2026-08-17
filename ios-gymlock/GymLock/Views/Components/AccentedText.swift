import SwiftUI

/// Builds a headline where selected substrings are tinted with the accent
/// colour, keeping one `Text` view so line breaking and Dynamic Type behave
/// exactly as they would for plain text.
struct AccentedText: View {
    let full: String
    let highlighted: [String]
    var size: CGFloat
    var weight: Font.Weight = .bold
    var accent: Color = Theme.accent
    var base: Color = Theme.ink

    var body: some View {
        Text(attributed)
            .font(.system(size: size, weight: weight))
            .lineSpacing(size * 0.14)
    }

    private var attributed: AttributedString {
        var string = AttributedString(full)
        string.foregroundColor = base

        for phrase in highlighted {
            var searchRange = string.startIndex..<string.endIndex
            while let found = string[searchRange].range(of: phrase) {
                string[found].foregroundColor = accent
                guard found.upperBound < string.endIndex else { break }
                searchRange = found.upperBound..<string.endIndex
            }
        }
        return string
    }
}
