//
//  MissionDotIcon.swift
//  GymLock
//
//  The small 13x9 Matrix art as a static dot icon. No animation.
//

import SwiftUI

struct MissionDotIcon: View {
    let figure: MissionFigure
    let size: CGFloat
    let color: Color

    init(figure: MissionFigure, size: CGFloat, color: Color) {
        self.figure = figure
        self.size = size
        self.color = color
    }

    var body: some View {
        let cells = MissionMatrixArt.small(figure)
        let iconColor = color
        let side = size
        Canvas { context, _ in
            MissionDotIconPainter.paint(&context, cells: cells, size: side, color: iconColor)
        }
        .frame(width: size, height: size)
    }
}

nonisolated enum MissionDotIconPainter {
    static func paint(_ context: inout GraphicsContext, cells: MissionMatrixCells, size: CGFloat, color: Color) {
        let pitch = size / 13
        let ox = (13 - CGFloat(cells.w)) / 2
        let oy = (9 - CGFloat(cells.h)) / 2
        let by = (size - 9 * pitch) / 2
        let r = pitch * 0.4
        var solid = Path()
        var light = Path()
        for i in 0..<cells.n {
            let cx = (ox + CGFloat(cells.x[i]) + 0.5) * pitch
            let cy = by + (oy + CGFloat(cells.y[i]) + 0.5) * pitch
            let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
            if cells.a[i] >= 1 { solid.addEllipse(in: rect) } else { light.addEllipse(in: rect) }
        }
        if !solid.isEmpty { context.fill(solid, with: .color(color)) }
        if !light.isEmpty { context.fill(light, with: .color(color.opacity(Double(MissionMatrixArt.baseAlpha(58))))) }
    }
}
