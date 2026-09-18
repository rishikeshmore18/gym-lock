import SwiftUI

/// The home fallback, said plainly.
///
/// `PLAN CHANGED. / I DIDN'T.` and the minutes. It never says gym and never
/// borrows a verified-visit number — the whole point of the ledger is that a
/// living-room workout is recorded as exactly that.
struct QuickSaveFrame: View {
    let kind: StoryElementKind
    let context: ShareContext
    let layout: StoryLayout
    let scale: Double

    var body: some View {
        switch kind {
        case .statement:
            VStack(alignment: .leading, spacing: layout.fontSize(-18, elementScale: scale)) {
                StoryStatementText(text: Text("PLAN CHANGED."), layout: layout, scale: scale)
                StoryStatementText(
                    text: Text("I DIDN'T") + Text(".").foregroundStyle(Theme.accent),
                    layout: layout,
                    scale: scale
                )
            }
        case .facts:
            StoryFactsText(lines: [fact], layout: layout, scale: scale)
        case .mark:
            StoryMarkView(layout: layout, scale: scale)
        default:
            EmptyView()
        }
    }

    private var fact: String {
        if let minutes = context.outcome?.minutes, minutes > 0 {
            return "\(minutes) min quick save ✓"
        }
        return "quick save ✓"
    }
}
