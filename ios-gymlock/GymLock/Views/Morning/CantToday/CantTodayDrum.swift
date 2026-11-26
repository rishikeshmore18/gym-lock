//
//  CantTodayDrum.swift
//  GymLock · the "can't today" screen (three looks)
//
//  The slot-machine drum every look shares. It owns the physics and the gesture, the look owns
//  the styling (through `content`):
//
//    - drag follows the finger 1:1 (the grab offset is kept, nothing jumps on touch-down)
//    - release hands the finger's velocity to a short friction glide, then a spring snap
//      (response 0.34, damping 0.85) to the nearest row
//    - at the ends of a non-wrapping drum it rubber bands (UI-RULES 6.5, constant 0.55)
//    - tap a row to go to it
//    - a light detent callback each time a row crosses the centre
//    - a blocked row can be scrolled over, but the drum settles on the nearest allowed row
//      (the previous selection if there is none) and calls `onBlocked` once
//    - touching during the glide or the snap grabs the drum from its live position
//
//  The motion is a small hand-written simulation stepped from a TimelineView, so the live
//  position is always known (true interruptibility). The timeline only runs while the drum moves.
//

import SwiftUI

/// UI-RULES 6.5. Local copy so this file stands alone.
private func drumRubber(_ overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
    (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
}

// MARK: - Engine

/// Plain reference type, not observed. The view reads it every frame and is told to redraw
/// either by the TimelineView (while moving) or by a tick (while dragging).
fileprivate final class CantTodayDrumEngine {
    enum Phase { case idle, drag, glide, spring }
    enum Event { case detent, blocked(Int), commit(Int), settled }

    // Configuration, refreshed by the view on every body pass.
    var count = 1
    var rowHeight: CGFloat = 40
    var visibleRows = 3
    var wraps = false
    var isBlocked: (Int) -> Bool = { _ in false }
    var sink: ([Event]) -> Void = { _ in }

    // State.
    var phase: Phase = .idle
    var p: Double = 0                 // the row at the centre, fractional, virtual (unbounded when wrapping)
    var committedJ: Int = 0           // virtual row of the current selection
    var initialized = false

    private var v: Double = 0         // rows per second
    private var target: Double = 0
    private var friction: Double = 4
    private var lastT: Double?
    private var lastRow = 0
    private var dragRaw0: Double = 0
    private(set) var moved: CGFloat = 0
    private(set) var touchTime = Date()
    private(set) var grabbedMoving = false
    private var events: [Event] = []
    private var flushScheduled = false

    // Spring: response 0.34 s, damping ratio 0.85.
    private let omega = 2 * Double.pi / 0.34
    private var stiffness: Double { omega * omega }
    private var damping: Double { 2 * 0.85 * omega }

    private let glideStart: Double = 4        // rows/s below which there is no glide
    private let maxSpeed: Double = 60

    var committedIndex: Int { mod(committedJ) }

    func mod(_ j: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((j % count) + count) % count
    }

    private var highest: Double { Double(max(count - 1, 0)) }
    private var dimension: CGFloat { rowHeight * CGFloat(visibleRows) }

    // MARK: Events

    func drain() -> [Event] {
        let e = events
        events.removeAll(keepingCapacity: true)
        return e
    }

    var hasEvents: Bool { !events.isEmpty }

    /// From inside a body pass: never touch bindings there, hand the events over next turn.
    private func scheduleFlush() {
        guard !flushScheduled, !events.isEmpty else { return }
        flushScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            let e = self.drain()
            if !e.isEmpty { self.sink(e) }
        }
    }

    private func detentCheck() {
        let r = Int(p.rounded())
        if r != lastRow {
            lastRow = r
            events.append(.detent)
        }
    }

    // MARK: Bounds

    private func applyBounds(_ raw: Double) -> Double {
        guard !wraps else { return raw }
        if raw < 0 {
            let y = drumRubber(CGFloat(-raw) * rowHeight, dimension: dimension)
            return -Double(y / rowHeight)
        }
        if raw > highest {
            let y = drumRubber(CGFloat(raw - highest) * rowHeight, dimension: dimension)
            return highest + Double(y / rowHeight)
        }
        return raw
    }

    /// Inverse of the rubber band, so a grab made while the drum is stretched does not jump.
    private func inverseBounds(_ pos: Double) -> Double {
        guard !wraps else { return pos }
        let c: CGFloat = 0.55
        let d = dimension
        if pos < 0 {
            let y = min(CGFloat(-pos) * rowHeight, d * 0.99)
            let o = y * d / (c * (d - y))
            return -Double(o / rowHeight)
        }
        if pos > highest {
            let y = min(CGFloat(pos - highest) * rowHeight, d * 0.99)
            let o = y * d / (c * (d - y))
            return highest + Double(o / rowHeight)
        }
        return pos
    }

    // MARK: Touch

    func touchDown() {
        grabbedMoving = (phase == .glide || phase == .spring)
        phase = .drag
        v = 0
        lastT = nil
        dragRaw0 = inverseBounds(p)
        moved = 0
        touchTime = Date()
        lastRow = Int(p.rounded())
    }

    func drag(translationY: CGFloat) {
        guard phase == .drag, rowHeight > 0 else { return }
        moved = max(moved, abs(translationY))
        let raw = dragRaw0 - Double(translationY / rowHeight)
        p = applyBounds(raw)
        detentCheck()
    }

    /// `vRows` and `projRows` are in rows (positive = towards higher rows). `tapRow` is the offset
    /// from the centre of a tapped row.
    func release(vRows: Double, projRows: Double, tapRow: Int?) {
        guard phase == .drag else { return }
        lastT = nil
        let speed = max(-maxSpeed, min(maxSpeed, vRows))
        if let tapRow {
            v = 0
            resolveAndSpring(Int(p.rounded()) + tapRow)
            return
        }
        if !wraps && (p < 0 || p > highest) {
            v = speed * 0.35
            resolveAndSpring(Int(p.rounded()))
            return
        }
        if abs(speed) > glideStart {
            v = speed
            // Total glide distance is v / friction; aim for about half the system's projection.
            let wanted = max(abs(projRows) * 0.5, 0.5)
            friction = max(2.5, min(8, abs(speed) / wanted))
            phase = .glide
            return
        }
        v = speed
        resolveAndSpring(Int((p + v * 0.08).rounded()))
    }

    /// Roll to a row from outside (a changed binding, VoiceOver). Shortest way when wrapping.
    func goTo(index: Int) {
        guard count > 0 else { return }
        let idx = max(0, min(count - 1, index))
        let base = Int(p.rounded())
        var j = idx
        if wraps {
            var d = (idx - mod(base)) % count
            if d > count / 2 { d -= count }
            if d < -count / 2 { d += count }
            j = base + d
        }
        goToVirtual(j)
    }

    func goToVirtual(_ j: Int) {
        guard count > 0 else { return }
        let jj = wraps ? j : max(0, min(count - 1, j))
        committedJ = jj
        target = Double(jj)
        phase = .spring
        lastT = nil
        events.append(.commit(mod(jj)))
    }

    // MARK: Resolve

    /// Decide where the drum settles (a blocked row is swapped for the nearest allowed one) and start the spring.
    private func resolveAndSpring(_ j0: Int) {
        guard count > 0 else { phase = .idle; return }
        var j = wraps ? j0 : max(0, min(count - 1, j0))
        let idx = mod(j)
        if isBlocked(idx) {
            events.append(.blocked(idx))
            j = replacement(for: j)
        }
        committedJ = j
        target = Double(j)
        phase = .spring
        lastT = nil
        events.append(.commit(mod(j)))
    }

    private func replacement(for j: Int) -> Int {
        func ok(_ c: Int) -> Bool {
            if !wraps && (c < 0 || c >= count) { return false }
            return !isBlocked(mod(c))
        }
        for d in 1...max(count, 1) {
            let up = j + d
            let down = j - d
            let okUp = ok(up)
            let okDown = ok(down)
            if okUp && okDown {
                return abs(up - committedJ) <= abs(down - committedJ) ? up : down
            }
            if okUp { return up }
            if okDown { return down }
        }
        // Nothing is allowed: back to the previous selection, by the shortest way when wrapping.
        if wraps {
            var delta = mod(committedJ) - mod(j)
            if delta > count / 2 { delta -= count }
            if delta < -count / 2 { delta += count }
            return j + delta
        }
        return committedJ
    }

    // MARK: Simulation

    /// Called from the TimelineView every frame while moving. `now` = timeline seconds.
    func step(to now: Double) {
        guard phase == .glide || phase == .spring else {
            lastT = nil
            return
        }
        guard let last = lastT else {
            lastT = now
            return
        }
        var dt = now - last
        lastT = now
        guard dt > 0 else { return }
        dt = min(dt, 1.0 / 20.0)
        let n = max(1, Int((dt / 0.004).rounded(.up)))
        let h = dt / Double(n)

        for _ in 0..<n {
            if phase == .glide {
                v *= exp(-friction * h)
                p += v * h
                detentCheck()
                if !wraps && (p < 0 || p > highest) {
                    v *= 0.4
                    resolveAndSpring(Int(max(0, min(highest, p)).rounded()))
                } else if abs(v) < glideStart {
                    resolveAndSpring(Int((p + v * 0.08).rounded()))
                }
            } else if phase == .spring {
                let a = -stiffness * (p - target) - damping * v
                v += a * h
                p += v * h
                detentCheck()
                if abs(p - target) < 0.003 && abs(v) < 0.03 {
                    p = target
                    v = 0
                    finish()
                    break
                }
            } else {
                break
            }
        }
        scheduleFlush()
    }

    private func finish() {
        phase = .idle
        lastT = nil
        if wraps && count > 0 {
            // Keep the numbers small: shift by whole turns while nothing is moving.
            let turns = Int((target / Double(count)).rounded(.down))
            if turns != 0 {
                let shift = turns * count
                p -= Double(shift)
                target -= Double(shift)
                committedJ -= shift
                lastRow -= shift
            }
        }
        events.append(.settled)
    }
}

// MARK: - View

struct CantTodayDrum<Content: View>: View {
    private let count: Int
    private let selection: Binding<Int>
    private let rowHeight: CGFloat
    private let visibleRows: Int
    private let wraps: Bool
    private let isBlocked: (Int) -> Bool
    private let onBlocked: (Int) -> Void
    private let onDetent: () -> Void
    private let isInteracting: Binding<Bool>
    private let content: (Int, CGFloat) -> Content

    @State private var engine = CantTodayDrumEngine()
    @State private var moving = false
    @State private var renderTick = 0
    @GestureState private var touching = false

    init(count: Int,
         selection: Binding<Int>,
         rowHeight: CGFloat,
         visibleRows: Int,
         wraps: Bool,
         isBlocked: @escaping (Int) -> Bool,
         onBlocked: @escaping (Int) -> Void,
         onDetent: @escaping () -> Void,
         isInteracting: Binding<Bool>,
         @ViewBuilder content: @escaping (_ index: Int, _ distance: CGFloat) -> Content) {
        self.count = count
        self.selection = selection
        self.rowHeight = rowHeight
        self.visibleRows = visibleRows
        self.wraps = wraps
        self.isBlocked = isBlocked
        self.onBlocked = onBlocked
        self.onDetent = onDetent
        self.isInteracting = isInteracting
        self.content = content
    }

    var body: some View {
        let _ = configure()
        TimelineView(.animation(paused: !moving)) { context in
            let _ = renderTick
            let _ = engine.step(to: context.date.timeIntervalSinceReferenceDate)
            drumBody
        }
        .frame(minWidth: 44)
        .frame(height: rowHeight * CGFloat(visibleRows))
        .clipped()
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onChange(of: touching) { _, isDown in
            if !isDown && engine.phase == .drag {
                // The system took the touch away (no `onEnded`): let go gently.
                engine.release(vRows: 0, projRows: 0, tapRow: nil)
                moving = true
                renderTick &+= 1
                handle(engine.drain())
            }
        }
        .onChange(of: selection.wrappedValue) { _, newValue in
            guard engine.phase != .drag, count > 0 else { return }
            let clamped = max(0, min(count - 1, newValue))
            if clamped != engine.committedIndex {
                engine.goTo(index: clamped)
                moving = true
                renderTick &+= 1
                handle(engine.drain())
            }
        }
        .onDisappear { engine.sink = { _ in } }   // breaks the engine <-> view reference loop
        .accessibilityElement(children: .combine)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: accessibilityStep(1)
            case .decrement: accessibilityStep(-1)
            @unknown default: break
            }
        }
    }

    // MARK: Drawing

    private var drumBody: some View {
        let c = Int(engine.p.rounded())
        let half = visibleRows / 2
        var rows: [Int] = []
        if count > 0 {
            for j in (c - half - 1)...(c + half + 1) where wraps || (j >= 0 && j < count) {
                rows.append(j)
            }
        }
        let centre = engine.p
        return ZStack {
            ForEach(rows, id: \.self) { j in
                let dist = Double(j) - centre
                content(engine.mod(j), CGFloat(dist))
                    .frame(height: rowHeight)
                    .offset(y: CGFloat(dist) * rowHeight)
                    .accessibilityHidden(abs(dist) > 0.5)
            }
        }
    }

    // MARK: State plumbing

    /// Refreshes the engine's view of the world. Runs inside `body`, so it only writes to the (unobserved) engine.
    private func configure() {
        engine.count = count
        engine.rowHeight = rowHeight
        engine.visibleRows = visibleRows
        engine.wraps = wraps
        engine.isBlocked = isBlocked
        engine.sink = { events in handle(events) }
        if !engine.initialized {
            engine.initialized = true
            let start = count > 0 ? max(0, min(count - 1, selection.wrappedValue)) : 0
            engine.p = Double(start)
            engine.committedJ = start
        }
    }

    /// Runs the callbacks and the binding writes. Only ever called outside a body pass.
    private func handle(_ events: [CantTodayDrumEngine.Event]) {
        for event in events {
            switch event {
            case .detent:
                onDetent()
            case .blocked(let row):
                onBlocked(row)
            case .commit(let index):
                if selection.wrappedValue != index { selection.wrappedValue = index }
            case .settled:
                if engine.phase != .drag { isInteracting.wrappedValue = false }
                if engine.phase == .idle {
                    moving = false
                    renderTick &+= 1
                }
            }
        }
    }

    // MARK: Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($touching) { _, state, _ in state = true }
            .onChanged { value in
                if engine.phase != .drag {
                    engine.touchDown()
                    if !isInteracting.wrappedValue { isInteracting.wrappedValue = true }
                }
                engine.drag(translationY: value.translation.height)
                renderTick &+= 1
                handle(engine.drain())
            }
            .onEnded { value in
                guard engine.phase == .drag else { return }
                let pitch = Double(max(rowHeight, 1))
                let duration = Date().timeIntervalSince(engine.touchTime)
                if !engine.grabbedMoving && engine.moved < 6 && duration < 0.35 {
                    let fromCentre = value.startLocation.y - rowHeight * CGFloat(visibleRows) / 2
                    let k = Int((fromCentre / rowHeight).rounded())
                    engine.release(vRows: 0, projRows: 0, tapRow: k)
                } else {
                    let v = -Double(value.velocity.height) / pitch
                    let proj = -Double(value.predictedEndTranslation.height - value.translation.height) / pitch
                    engine.release(vRows: v, projRows: proj, tapRow: nil)
                }
                moving = true
                renderTick &+= 1
                handle(engine.drain())
            }
    }

    // MARK: Accessibility

    private func accessibilityStep(_ direction: Int) {
        guard count > 0 else { return }
        var j = engine.committedJ
        for _ in 0..<count {
            j += direction
            if !wraps && (j < 0 || j >= count) { return }
            if !isBlocked(engine.mod(j)) {
                engine.goToVirtual(j)
                moving = true
                renderTick &+= 1
                handle(engine.drain())
                return
            }
        }
    }
}
