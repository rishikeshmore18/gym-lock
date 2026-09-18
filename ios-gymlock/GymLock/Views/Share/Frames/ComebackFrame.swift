import SwiftUI

/// `CAME BACK.` — matter-of-fact, no pep talk.
///
/// Facts name the two days. When they would share a weekday name (a week or
/// more apart) the return is given as a count of days instead, so "Missed
/// Monday. / Back Monday." never appears.
struct ComebackFrame: View {
    let kind: StoryElementKind
    let context: ShareContext
    let layout: StoryLayout
    let scale: Double

    var body: some View {
        switch kind {
        case .statement:
            StoryStatementText(
                text: Text("CAME BACK") + Text(".").foregroundStyle(Theme.accent),
                layout: layout,
                scale: scale
            )
        case .facts:
            StoryFactsText(lines: factLines, layout: layout, scale: scale)
        case .mark:
            StoryMarkView(layout: layout, scale: scale)
        default:
            EmptyView()
        }
    }

    private var factLines: [String] {
        guard let comeback = context.comeback else { return [] }
        let missed = ShareContext.weekdayText(comeback.missedDay)
        let returned = ShareContext.weekdayText(comeback.returnDay)

        if missed == returned {
            let days = Calendar.current.dateComponents([.day], from: comeback.missedDay, to: comeback.returnDay).day ?? 0
            return ["Missed \(missed).", "Back \(days) days later."]
        }
        return ["Missed \(missed).", "Back \(returned)."]
    }
}
