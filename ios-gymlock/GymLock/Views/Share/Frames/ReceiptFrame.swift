import SwiftUI

/// The morning as a ticket.
///
/// Monospaced rows between two straight hairlines — a receipt, not a cartoon
/// of one. Every row is a timestamp from the event log; a morning with a row
/// missing has no receipt at all rather than a dashed placeholder. The check
/// on ARRIVED is the frame's coral.
struct ReceiptFrame: View {
    let kind: StoryElementKind
    let context: ShareContext
    let layout: StoryLayout
    let scale: Double
    let isAnimated: Bool

    @State private var revealed = 0

    /// Settled for export regardless of lifecycle; see `MomentumFrame`.
    private var revealedCount: Int { isAnimated ? revealed : rows.count }

    private struct Row: Identifiable {
        let id: Int
        let time: Date
        let label: String
        let isVerified: Bool
    }

    private var rows: [Row] {
        guard let receipt = context.receipt else { return [] }
        var result = [
            Row(id: 0, time: receipt.alarm, label: "ALARM", isVerified: false),
            Row(id: 1, time: receipt.left, label: "LEFT", isVerified: false),
            Row(id: 2, time: receipt.arrived, label: "ARRIVED", isVerified: true),
        ]
        if let workout = receipt.workout {
            result.append(Row(id: 3, time: workout, label: "WORKOUT", isVerified: false))
        }
        return result
    }

    var body: some View {
        switch kind {
        case .statement:
            ticket
        case .facts:
            if let receipt = context.receipt {
                StoryFactsText(
                    lines: ["\(receipt.alarmToGymMinutes) min alarm → gym"],
                    layout: layout,
                    scale: scale
                )
            }
        case .mark:
            StoryMarkView(layout: layout, scale: scale)
        default:
            EmptyView()
        }
    }

    private var ticket: some View {
        let rows = rows
        let rowSpacing = layout.fontSize(22, elementScale: scale)
        let rule = layout.fontSize(2, elementScale: scale)

        return VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(StoryTypography.secondary)
                .frame(height: rule)

            VStack(alignment: .leading, spacing: rowSpacing) {
                ForEach(rows) { row in
                    HStack(spacing: layout.fontSize(40, elementScale: scale)) {
                        Text(ShareContext.timeText(row.time))
                            .foregroundStyle(StoryTypography.primary)
                            .frame(minWidth: layout.fontSize(230, elementScale: scale), alignment: .leading)

                        Text(row.label)
                            .foregroundStyle(row.isVerified ? StoryTypography.primary : StoryTypography.secondary)

                        if row.isVerified {
                            Text("✓")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .font(StoryTypography.receiptRow(layout, scale: scale))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(row.id < revealedCount ? 1 : 0)
                    .offset(y: row.id < revealedCount ? 0 : layout.fontSize(10, elementScale: scale))
                }
            }
            .padding(.vertical, layout.fontSize(30, elementScale: scale))

            Rectangle()
                .fill(StoryTypography.secondary)
                .frame(height: rule)
        }
        .frame(width: layout.textWidth(elementScale: scale) * 0.78, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            guard isAnimated else { return }
            // Rows print top to bottom, 60 ms apart, the way a receipt comes
            // out of the machine.
            for index in 0..<rows.count {
                try? await Task.sleep(for: .milliseconds(index == 0 ? 120 : 60))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.18)) { revealed = index + 1 }
            }
        }
    }
}
