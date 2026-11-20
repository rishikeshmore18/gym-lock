//
//  MissionMatrixFigureView.swift
//  GymLock
//
//  A Matrix dot figure on a dot board. Pitch = min(w/cols, h/rows), figure centred. The engine
//  (spring particles, idle loops, pulse) runs inside a TimelineView; a Canvas fills one Path per
//  alpha bucket, so a frame is about a dozen fill calls however many dots there are.
//

import SwiftUI

struct MissionMatrixFigureView: View {
    let figure: MissionFigure
    let mode: MissionDotMode
    let dot: Color
    let board: Color?
    let accent: Color?
    let level: Double
    let pulseToken: Int
    let cols: Int
    let rows: Int
    let onLand: ((MissionFigure) -> Void)?

    @State private var engine = MissionMatrixEngine()
    @State private var idlePaused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(figure: MissionFigure, mode: MissionDotMode = .fill, dot: Color, board: Color?,
         accent: Color? = Theme.accent, level: Double = 1, pulseToken: Int = 0,
         cols: Int = 32, rows: Int = 22, onLand: ((MissionFigure) -> Void)? = nil) {
        self.figure = figure
        self.mode = mode
        self.dot = dot
        self.board = board
        self.accent = accent
        self.level = level
        self.pulseToken = pulseToken
        self.cols = cols
        self.rows = rows
        self.onLand = onLand
    }

    private var isHiddenOrReduceMotionIdle: Bool {
        scenePhase != .active || idlePaused
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            TimelineView(.animation(paused: isHiddenOrReduceMotionIdle)) { timeline in
                let frame = prepareFrame(date: timeline.date, size: size)
                let dotColor = dot
                let accentColor = accent ?? dot
                let boardColor = board
                Canvas { context, _ in
                    MissionMatrixPainter.paint(&context, frame: frame, dot: dotColor,
                                               accent: accentColor, board: boardColor)
                }
                .onChange(of: timeline.date) { _, _ in
                    if reduceMotion && !idlePaused && engine.isSettled { idlePaused = true }
                }
            }
        }
        .onChange(of: figure) { _, newFigure in
            idlePaused = false
            engine.set(figure: newFigure)
        }
        .onChange(of: mode) { _, newMode in
            idlePaused = false
            engine.setMode(newMode)
        }
        .onChange(of: pulseToken) { _, _ in
            idlePaused = false
            engine.pulse()
        }
        .onChange(of: level) { _, newLevel in
            idlePaused = false
            engine.setLevel(Float(newLevel))
        }
        .onChange(of: cols) { _, _ in
            idlePaused = false
            engine.configure(cols: cols, rows: rows)
        }
        .onChange(of: rows) { _, _ in
            idlePaused = false
            engine.configure(cols: cols, rows: rows)
        }
        .onChange(of: reduceMotion) { _, newValue in
            idlePaused = false
            engine.reduceMotion = newValue
        }
    }

    /// Steps the engine to `date` and returns plain drawing data for the Canvas.
    @MainActor
    private func prepareFrame(date: Date, size: CGSize) -> MissionMatrixFrame {
        if !engine.isConfigured {
            engine.reduceMotion = reduceMotion
            engine.setMode(mode)
            engine.setLevel(Float(level), instant: true)
            engine.configure(cols: cols, rows: rows)
            engine.set(figure: figure)
        }
        engine.onLand = onLand
        engine.advance(to: date.timeIntervalSinceReferenceDate)
        let w = Float(max(size.width, 1)), h = Float(max(size.height, 1))
        let pitch = min(w / Float(max(cols, 1)), h / Float(max(rows, 1)))
        let ox = (w - pitch * Float(cols)) / 2
        let oy = (h - pitch * Float(rows)) / 2
        return engine.makeFrame(pitch: pitch, originX: ox, originY: oy)
    }
}

// MARK: - Painter

/// Draws a `MissionMatrixFrame`. Plain value inputs only, so it is safe inside a Canvas renderer.
nonisolated enum MissionMatrixPainter {
    static func paint(_ context: inout GraphicsContext, frame: MissionMatrixFrame,
                      dot: Color, accent: Color, board: Color?) {
        let pitch = CGFloat(frame.pitch)
        let ox = CGFloat(frame.originX), oy = CGFloat(frame.originY)

        // Board: one path per light level (a slow diagonal sweep every 5 s).
        if let board {
            let r = pitch * 0.13
            var levels = [Path](repeating: Path(), count: 4)
            for y in 0..<frame.rows {
                for x in 0..<frame.cols {
                    var l = 0
                    if frame.sweepOn {
                        let dd = abs(Float(x + y) - frame.sweepPos)
                        if dd < 5 { l = Int(((1 - dd / 5) * 3).rounded()) }
                    }
                    let cx = ox + (CGFloat(x) + 0.5) * pitch
                    let cy = oy + (CGFloat(y) + 0.5) * pitch
                    levels[l].addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                }
            }
            for lv in 0..<4 where !levels[lv].isEmpty {
                context.fill(levels[lv], with: .color(board.opacity(0.7 + Double(lv) * 0.1)))
            }
        }

        // Figure: one path per alpha bucket (8 dot, 8 accent, 3 halo layers).
        let records = frame.records
        if records.isEmpty { return }
        var layers = [Path](repeating: Path(), count: MissionMatrixLevels.layerCount)
        var i = 0
        while i + 3 < records.count {
            let cx = CGFloat(records[i]), cy = CGFloat(records[i + 1]), r = CGFloat(records[i + 2])
            let layer = Int(records[i + 3])
            layers[layer].addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            i += 4
        }
        let haloBase = MissionMatrixLevels.haloOffset
        for k in 0..<3 where !layers[haloBase + k].isEmpty {
            let a = Double(MissionMatrixLevels.haloLevels[k] * frame.haloScale)
            context.fill(layers[haloBase + k], with: .color(dot.opacity(a)))
        }
        for b in 0..<8 {
            let a = Double(MissionMatrixLevels.dotLevels[b])
            if !layers[b].isEmpty {
                context.fill(layers[b], with: .color(dot.opacity(a)))
            }
            let ab = b + MissionMatrixLevels.accentOffset
            if !layers[ab].isEmpty {
                context.fill(layers[ab], with: .color(accent.opacity(a)))
            }
        }
    }
}
