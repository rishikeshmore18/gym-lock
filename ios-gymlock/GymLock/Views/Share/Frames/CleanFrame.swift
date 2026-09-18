import SwiftUI

/// The photo and the mark. Nothing else.
///
/// Exists for people who do not want numbers on their photograph, and it is
/// offered first for exactly that reason.
struct CleanFrame: View {
    let kind: StoryElementKind
    let layout: StoryLayout
    let scale: Double

    var body: some View {
        switch kind {
        case .mark:
            StoryMarkView(layout: layout, scale: scale)
        default:
            EmptyView()
        }
    }
}
