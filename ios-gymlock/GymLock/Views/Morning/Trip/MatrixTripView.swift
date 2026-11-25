import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - MatrixTripView

/// The Matrix style of the trip screen: a tilted 3D board of dots built from the
/// real map around the route, the countdown under it, and the full-screen
/// verification takeover when the user reaches the gym.
///
/// Port of the approved HTML prototype (`gymlock-trip-matrix.html`). The board is
/// one `Canvas` inside a `TimelineView`; its camera, dot levels and entry are
/// driven by `MatrixTripEngine`, which lives in `@State` so it survives the
/// host re-creating `frame` every second.
struct MatrixTripView: View {
    let model: TripModel
    let frame: TripFrame
    let actions: TripActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engine = MatrixTripEngine()
    @State private var view3D: Bool = true
    @State private var boardFrame: CGRect = .zero
    @State private var boardPulse: Bool = false

    // Entry
    @State private var entryBegan: Bool = false
    @State private var infoIn: Bool = false
    @State private var countInStart: Date?
    @State private var countInDone: Bool = false

    // Arrival takeover
    @State private var takeoverOn: Bool = false
    @State private var grown: Bool = false
    @State private var panelShown: Bool = false
    @State private var arrivalTask: Task<Void, Never>?
    @State private var burst: TripConfetti.Burst?
    @State private var burstCount: Int = 0

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                boardSection
                infoSection
            }
            takeoverLayer
        }
        .overlay {
            TripConfetti(look: .dots, burst: burst)
                .ignoresSafeArea()
        }
        .onAppear(perform: handleAppear)
        .onChange(of: frame.entryStarted) { _, started in
            if started { beginEntry() }
        }
        .onChange(of: frame.phase) { old, new in
            handlePhaseChange(from: old, to: new)
        }
    }

    // MARK: Top bar

    /// The title in the middle and the same glass cross as Ridge in the top
    /// left corner. It ends the trip the way "End" did.
    private var topBar: some View {
        ZStack {
            MorningHeader()
            HStack {
                GlassCircleButton(symbol: "xmark", label: "End", diameter: 44) {
                    actions.end()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 2)
    }

    // MARK: Board

    private var boardSection: some View {
        ZStack(alignment: .topTrailing) {
            boardCanvas
            boardControls
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(minHeight: 180, maxHeight: .infinity)
    }

    private var renderInput: MatrixTripEngine.Input {
        MatrixTripEngine.Input(
            phase: frame.phase,
            entryStarted: frame.entryStarted,
            view3D: view3D,
            reduceMotion: reduceMotion
        )
    }

    private var boardCanvas: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            Canvas { ctx, size in
                engine.render(into: &ctx, size: size, date: context.date, model: model, input: renderInput)
            }
        }
        .background(MatrixTripStyle.board)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .scaleEffect(boardPulse ? 1.008 : 1.0)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { newFrame in
            boardFrame = newFrame
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Map of your route to the gym, drawn in dots")
        .accessibilityAddTraits(.isImage)
    }

    private var boardControls: some View {
        VStack(spacing: 10) {
            GlassCircleButton(
                symbol: view3D ? "map" : "view.3d",
                label: view3D ? "Switch to 2D map" : "Switch to 3D map",
                diameter: 40
            ) {
                view3D.toggle()
            }
            GlassCircleButton(
                symbol: "location.north.line.fill",
                label: "Recenter on you",
                diameter: 40
            ) {
                engine.pingUser()
                view3D = true
            }
        }
        .padding(10)
    }

    // MARK: Info

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            countdown
                .modifier(MatrixTripReveal(isIn: infoIn, index: 0, reduceMotion: reduceMotion))
            detailRow
                .padding(.top, 2)
                .modifier(MatrixTripReveal(isIn: infoIn, index: 1, reduceMotion: reduceMotion))
            MatrixTripMeter(progress: model.progress)
                .frame(height: 14)
                .padding(.top, 10)
                .animation(.easeOut(duration: 0.5), value: model.progress)
                .modifier(MatrixTripReveal(isIn: infoIn, index: 2, reduceMotion: reduceMotion))
            headingBlock
                .padding(.top, 12)
                .modifier(MatrixTripReveal(isIn: infoIn, index: 3, reduceMotion: reduceMotion))
            actionZone
                .padding(.top, 10)
                .modifier(MatrixTripReveal(isIn: infoIn, index: 4, reduceMotion: reduceMotion))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private func countFactor(at date: Date) -> Double {
        if reduceMotion || countInDone { return 1.0 }
        guard let start = countInStart else { return entryBegan ? 1.0 : 0.0 }
        let e = matrixTripClamp(date.timeIntervalSince(start) / 1.0, 0.0, 1.0)
        return 1.0 - pow(1.0 - e, 3.0)
    }

    private var countdown: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: countInDone || reduceMotion)) { context in
            let seconds: Double = frame.remaining * countFactor(at: context.date)
            let text: String = TripFormat.clock(seconds)
            Text(text)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText(countsDown: true))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(countInDone ? Animation.easeInOut(duration: 0.18) : nil, value: text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Get to your gym")
        .accessibilityValue(spokenValue)
    }

    private var spokenValue: String {
        var value = "\(TripFormat.spoken(frame.remaining)) left"
        if let by = frame.gymBy { value += ", \(TripCopy.gymBy(by))" }
        return value
    }

    private var detailRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let by = frame.gymBy {
                Text(TripCopy.gymBy(by))
            }
            Spacer(minLength: 12)
            if let line = frame.distanceLine {
                Text(line)
            }
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(Theme.inkSecondary)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var headingBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(frame.heading)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.17), value: frame.heading)
            Text(frame.support)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.17), value: frame.support)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
    }

    private var actionZone: some View {
        let showButton = frame.phase == .atHome
        let showRow = frame.phase == .onTheWay
        return ZStack {
            TripPrimaryButton(
                title: TripCopy.leftButton,
                systemImage: "figure.walk.departure",
                action: actions.left
            )
            .opacity(showButton ? 1.0 : 0.0)
            .scaleEffect(showButton ? 1.0 : 0.92)
            .allowsHitTesting(showButton)
            .accessibilityHidden(!showButton)
            .animation(.easeOut(duration: 0.14), value: showButton)

            TripStatusRow()
                .opacity(showRow ? 1.0 : 0.0)
                .allowsHitTesting(false)
                .accessibilityHidden(!showRow)
                .animation(.easeOut(duration: 0.35).delay(showRow ? 0.12 : 0.0), value: showRow)
        }
        .frame(height: 56)
    }

    // MARK: Takeover

    @ViewBuilder
    private var takeoverLayer: some View {
        if takeoverOn {
            GeometryReader { proxy in
                takeoverContent(proxy)
            }
            .ignoresSafeArea()
        }
    }

    private func takeoverContent(_ proxy: GeometryProxy) -> some View {
        let size: CGSize = proxy.size
        let origin: CGPoint = proxy.frame(in: .global).origin
        let boardLocal: CGRect = boardFrame.offsetBy(dx: -origin.x, dy: -origin.y)
        let full = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let from: CGRect = (reduceMotion || boardLocal.isEmpty) ? full : boardLocal
        let fades: Bool = reduceMotion || boardLocal.isEmpty
        return ZStack {
            RoundedRectangle(cornerRadius: grown ? 0 : Theme.cardRadius, style: .continuous)
                .fill(MatrixTripStyle.takeover)
                .frame(width: grown ? size.width : from.width, height: grown ? size.height : from.height)
                .position(x: grown ? size.width / 2 : from.midX, y: grown ? size.height / 2 : from.midY)
                .opacity(fades && !grown ? 0.0 : 1.0)

            MatrixTripVerifyPanel(
                frame: frame,
                reduceMotion: reduceMotion,
                onTrouble: actions.trouble,
                onFinale: actions.finaleDone,
                onPuff: { point in
                    fireBurst(at: CGPoint(x: point.x - origin.x, y: point.y - origin.y), count: 60, fromTop: false)
                }
            )
            .opacity(panelShown ? 1.0 : 0.0)
            .offset(y: (panelShown || reduceMotion) ? 0 : 10)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
    }

    private func fireBurst(at point: CGPoint, count: Int, fromTop: Bool) {
        burstCount += 1
        burst = TripConfetti.Burst(id: burstCount, origin: point, count: count, fromTop: fromTop)
    }

    // MARK: Lifecycle

    private func handleAppear() {
        if frame.phase == .verifying || frame.phase == .verified {
            startTakeover(animated: false)
        }
        if frame.entryStarted { beginEntry() }
    }

    /// Plays the entry once: the countdown counts in a beat after the board starts.
    private func beginEntry() {
        guard !entryBegan else { return }
        entryBegan = true
        let instant = reduceMotion || frame.phase == .verifying || frame.phase == .verified
        if instant {
            infoIn = true
            countInDone = true
            return
        }
        countInStart = Date().addingTimeInterval(0.5)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            infoIn = true
            try? await Task.sleep(for: .milliseconds(1_200))
            countInDone = true
        }
    }

    private func handlePhaseChange(from old: TripPhase, to new: TripPhase) {
        if old == .atHome && new != .atHome && !reduceMotion {
            withAnimation(.easeOut(duration: 0.09)) { boardPulse = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(90))
                withAnimation(.easeOut(duration: 0.09)) { boardPulse = false }
            }
        }
        let wasArrival = old == .verifying || old == .verified
        let isArrival = new == .verifying || new == .verified
        if isArrival && !wasArrival {
            startTakeover(animated: true)
        } else if !isArrival && wasArrival {
            endTakeover()
        }
    }

    /// The dark board grows to the whole phone, then the verification panel fades up.
    /// `animated` is false when the app opens already mid-dwell: no confetti, no grow.
    private func startTakeover(animated: Bool) {
        arrivalTask?.cancel()
        takeoverOn = true
        if !animated {
            grown = true
            panelShown = true
            infoIn = true
            countInDone = true
            return
        }
        grown = false
        panelShown = false
        if let userPoint = engine.userScreen, !boardFrame.isEmpty {
            let global = CGPoint(x: boardFrame.minX + userPoint.x, y: boardFrame.minY + userPoint.y)
            fireBurst(at: global, count: 105, fromTop: true)
        } else {
            fireBurst(at: CGPoint(x: boardFrame.midX, y: boardFrame.midY), count: 105, fromTop: true)
        }
        let fades = reduceMotion
        arrivalTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            if fades {
                withAnimation(.easeOut(duration: 0.25)) { grown = true }
            } else {
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1.0, duration: 0.75)) { grown = true }
            }
            try? await Task.sleep(for: .milliseconds(fades ? 250 : 520))
            guard !Task.isCancelled else { return }
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1.0, duration: 0.6)) { panelShown = true }
        }
    }

    private func endTakeover() {
        arrivalTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) {
            panelShown = false
            grown = false
        }
        arrivalTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            takeoverOn = false
        }
    }
}

// MARK: - Style constants and bitmaps

private enum MatrixTripStyle {
    /// Board #1A1A1A and dots #F4F4F2, as in the prototype.
    static let board = Color(red: 0.102, green: 0.102, blue: 0.102)
    static let dot = Color(red: 0.957, green: 0.957, blue: 0.949)
    static let takeover = Color(red: 0.08, green: 0.08, blue: 0.08)

    static let gymRows: [String] = ["##.......##", "##.......##", "###########", "##.......##", "##.......##"]
    static let checkRows: [String] = [
        "..........#", ".........##", "........##.", "#......##..",
        "##....##...", ".##..##....", "..####.....", "...##......"
    ]

    /// 32 pre-multiplied dot colours, one per brightness bucket.
    static let bucketColors: [Color] = (0..<32).map { index in
        dot.opacity(Double(index) / 31.0)
    }

    /// Dumbbell dots, sorted by x then y, rows lowered by 1.5 to sit mid-canvas.
    static let dumbbellPoints: [CGPoint] = sortedPoints(gymRows, yOffset: 1.5)
    /// Check dots, same order, so dot i of the dumbbell flies to dot i of the check.
    static let checkPoints: [CGPoint] = sortedPoints(checkRows, yOffset: 0.0)

    private static func sortedPoints(_ rows: [String], yOffset: Double) -> [CGPoint] {
        var points: [CGPoint] = []
        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, character) in row.enumerated() where character == "#" {
                points.append(CGPoint(x: CGFloat(columnIndex), y: CGFloat(Double(rowIndex) + yOffset)))
            }
        }
        return points.sorted { a, b in
            if a.x != b.x { return a.x < b.x }
            return a.y < b.y
        }
    }
}

private nonisolated func matrixTripClamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
    min(high, max(low, value))
}

private nonisolated func matrixTripWrap(_ angle: Double) -> Double {
    var a = angle
    let twoPi = 2.0 * Double.pi
    while a > Double.pi { a -= twoPi }
    while a < -Double.pi { a += twoPi }
    return a
}

private nonisolated func matrixTripRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
    CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(w), height: CGFloat(h))
}

private nonisolated func matrixTripLevelAlpha(_ level: Double) -> Double {
    let index = matrixTripClamp(((level + 0.5) / 7.0 * 255.0).rounded(), 0.0, 255.0)
    return matrixTripClamp(0.04 + 0.96 * pow(index / 255.0, 1.4), 0.0, 1.0)
}

private nonisolated func matrixTripEaseBack(_ value: Double) -> Double {
    let x = matrixTripClamp(value, 0.0, 1.0)
    return 1.0 + 2.70158 * pow(x - 1.0, 3.0) + 1.70158 * pow(x - 1.0, 2.0)
}

// MARK: - Reveal modifier

private struct MatrixTripReveal: ViewModifier {
    let isIn: Bool
    let index: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let animation: Animation = reduceMotion
            ? Animation.easeOut(duration: 0.3)
            : Animation.timingCurve(0.2, 0.8, 0.2, 1.0, duration: 0.6).delay(0.06 * Double(index))
        content
            .opacity(isIn ? 1.0 : 0.0)
            .offset(y: (isIn || reduceMotion) ? 0 : 8)
            .animation(animation, value: isIn)
    }
}

// MARK: - Trip meter

/// 30 dots filling in ink with trip progress, and a small pixel dumbbell at the end.
/// Animatable so the fill glides between the model's updates.
private struct MatrixTripMeter: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            drawMeter(&ctx, size: size)
        }
        .accessibilityHidden(true)
    }

    private func drawMeter(_ ctx: inout GraphicsContext, size: CGSize) {
        let width = Double(size.width)
        let height = Double(size.height)
        let glyphWidth = 22.0
        let glyphHeight = 10.0
        let count = 30
        let radius = 2.5
        let span = max(1.0, width - glyphWidth - 12.0 - 2.0 * radius)
        let filled = matrixTripClamp(progress, 0.0, 1.0) * Double(count)
        for index in 0..<count {
            let amount = matrixTripClamp(filled - Double(index), 0.0, 1.0)
            let x = radius + span * Double(index) / Double(count - 1)
            let dot = Path(ellipseIn: matrixTripRect(x - radius, height / 2.0 - radius, 2.0 * radius, 2.0 * radius))
            ctx.fill(dot, with: .color(Theme.ink.opacity(0.14 + 0.86 * amount)))
        }
        let glyphColor = Theme.ink.opacity(progress >= 0.999 ? 1.0 : 0.14)
        let gx = width - glyphWidth
        let gy = (height - glyphHeight) / 2.0
        for (rowIndex, row) in MatrixTripStyle.gymRows.enumerated() {
            for (columnIndex, character) in row.enumerated() where character == "#" {
                let cell = matrixTripRect(gx + Double(columnIndex) * 2.0, gy + Double(rowIndex) * 2.0, 2.0, 2.0)
                ctx.fill(Path(cell), with: .color(glyphColor))
            }
        }
    }
}

// MARK: - Verification panel

/// "you're here." with the pixel dumbbell that fills while the dwell runs, then
/// morphs into a check when the arrival is verified.
private struct MatrixTripVerifyPanel: View {
    let frame: TripFrame
    let reduceMotion: Bool
    let onTrouble: () -> Void
    let onFinale: () -> Void
    let onPuff: (CGPoint) -> Void

    @State private var verifiedAt: Date?
    @State private var canvasCenter: CGPoint?
    @State private var finaleSent: Bool = false

    private var isVerified: Bool { frame.phase == .verified }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            column(date: context.date)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: isVerified) {
            await runFinale()
        }
    }

    private func column(date: Date) -> some View {
        VStack(spacing: 0) {
            Text(TripCopy.youreHere)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Canvas { ctx, _ in
                drawDumbbell(&ctx, date: date)
            }
            .frame(width: 264, height: 192)
            .padding(.top, 34)
            .padding(.bottom, 26)
            .onGeometryChange(for: CGPoint.self) { proxy in
                let rect = proxy.frame(in: .global)
                return CGPoint(x: rect.midX, y: rect.midY)
            } action: { center in
                canvasCenter = center
            }
            .accessibilityHidden(true)

            statusRow(date: date)

            Text(isVerified ? TripCopy.unlocked : TripCopy.stayInside)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            Button {
                Haptics.tap()
                onTrouble()
            } label: {
                Text(TripCopy.trouble)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            .opacity(isVerified ? 0.0 : 1.0)
            .allowsHitTesting(!isVerified)
            .accessibilityHidden(isVerified)
        }
        .accessibilityElement(children: .contain)
    }

    private func statusRow(date: Date) -> some View {
        let seconds = frame.verifySecondsLeft(at: date)
        let step = Int(date.timeIntervalSinceReferenceDate * 2.4) % 3
        return HStack(spacing: 14) {
            HStack(spacing: 0) {
                Text(isVerified ? TripCopy.verified : TripCopy.verifying)
                if !isVerified {
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { index in
                            Text(".").opacity((reduceMotion || index <= step) ? 1.0 : 0.0)
                        }
                    }
                    .frame(width: 20, alignment: .leading)
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.85))

            if !isVerified {
                Text(TripFormat.short(seconds))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    /// Runs once when the phase turns verified: the second confetti puff, then
    /// the hand-over to the arrival screen after the check has landed.
    private func runFinale() async {
        guard isVerified else { return }
        if verifiedAt == nil { verifiedAt = Date() }
        try? await Task.sleep(for: .milliseconds(40))
        guard !Task.isCancelled else { return }
        if let center = canvasCenter { onPuff(center) }
        try? await Task.sleep(for: .milliseconds(2_400))
        guard !Task.isCancelled, !finaleSent else { return }
        finaleSent = true
        onFinale()
    }

    private func drawDumbbell(_ ctx: inout GraphicsContext, date: Date) {
        let pitch = 24.0
        let t = date.timeIntervalSinceReferenceDate
        let originX = (264.0 - 10.0 * pitch) / 2.0
        let originY = (192.0 - 7.0 * pitch) / 2.0

        let progress: Double = isVerified ? 1.0 : matrixTripClamp(frame.verifyProgress(date), 0.0, 1.0)
        var elapsed: Double = -1.0
        if isVerified {
            elapsed = date.timeIntervalSince(verifiedAt ?? date)
        }
        let flash: Double = elapsed < 0 ? 0.0 : matrixTripClamp(1.0 - abs(elapsed - 0.12) / 0.25, 0.0, 1.0)
        let morph: Double = elapsed < 0 ? 0.0 : (reduceMotion ? 1.0 : matrixTripClamp((elapsed - 0.25) / 0.55, 0.0, 1.0))
        let eased: Double = morph <= 0 ? 0.0 : 1.0 - pow(1.0 - morph, 3.0)
        let fill = progress * 11.0

        let points = MatrixTripStyle.dumbbellPoints
        let targets = MatrixTripStyle.checkPoints
        for index in 0..<points.count {
            let gx = Double(points[index].x)
            let gy = Double(points[index].y)
            let k = matrixTripClamp(fill - gx, 0.0, 1.0)
            var alpha = 0.14 + 0.86 * k
            if !reduceMotion && k < 1.0 {
                alpha += 0.05 * sin(t * 2.2 + gx * 0.7)
            }
            alpha = max(alpha, flash)
            var px = originX + gx * pitch
            var py = originY + gy * pitch
            var radius = pitch * (0.3 + 0.08 * k)
            if eased > 0 {
                if index < targets.count {
                    let tx = originX + Double(targets[index].x) * pitch
                    let ty = originY + Double(targets[index].y) * pitch
                    px += (tx - px) * eased
                    py += (ty - py) * eased
                    alpha = 1.0
                    radius = pitch * 0.36
                } else {
                    alpha *= (1.0 - eased)
                }
            }
            if alpha <= 0.01 { continue }
            if eased == 0 && k > 0 && k < 1.0 {
                let halo = Path(ellipseIn: matrixTripRect(px - radius * 1.9, py - radius * 1.9, radius * 3.8, radius * 3.8))
                ctx.fill(halo, with: .color(MatrixTripStyle.dot.opacity(0.16 * k)))
            }
            let dot = Path(ellipseIn: matrixTripRect(px - radius, py - radius, radius * 2.0, radius * 2.0))
            ctx.fill(dot, with: .color(MatrixTripStyle.dot.opacity(matrixTripClamp(alpha, 0.0, 1.0))))
        }
    }
}

// MARK: - Street field (Apple Maps snapshot -> dot levels)

/// Turns a muted, flat Apple Maps snapshot into a base brightness per grid cell:
/// roads are the brightest pixels of the light map, so the brightest slice becomes
/// street dots, a sparse sample of the rest becomes block texture, and everything
/// else stays very faint. When the snapshot fails or has no contrast, it returns
/// nil and the board shows a plain faint grid: no street is ever invented.
private enum MatrixStreetField {
    static func load(
        gym: CLLocationCoordinate2D,
        cellXm: [Double],
        cellYm: [Double],
        hash: [Double],
        pitchM: Double,
        cols: Int,
        rows: Int
    ) async -> [Double]? {
        guard cols > 1, rows > 1, !cellXm.isEmpty, cellXm.count == cellYm.count, cellXm.count == hash.count else { return nil }
        let widthM = Double(cols) * pitchM
        let heightM = Double(rows) * pitchM
        let minX = cellXm.min() ?? 0.0
        let maxX = cellXm.max() ?? 0.0
        let minY = cellYm.min() ?? 0.0
        let maxY = cellYm.max() ?? 0.0
        let centre = coordinate(around: gym, xm: (minX + maxX) / 2.0, ym: (minY + maxY) / 2.0)

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: centre, latitudinalMeters: heightM * 1.04, longitudinalMeters: widthM * 1.04)
        let longSide = 900.0
        let aspect = widthM / heightM
        let snapshotWidth = aspect >= 1.0 ? longSide : max(300.0, longSide * aspect)
        let snapshotHeight = aspect >= 1.0 ? max(300.0, longSide / aspect) : longSide
        options.size = CGSize(width: CGFloat(snapshotWidth), height: CGFloat(snapshotHeight))
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)

        let snapshot: MKMapSnapshotter.Snapshot
        do {
            snapshot = try await MKMapSnapshotter(options: options).start()
        } catch {
            return nil
        }
        guard let image = snapshot.image.cgImage else { return nil }
        let imageWidthPoints = Double(snapshot.image.size.width)
        guard imageWidthPoints > 0 else { return nil }
        let pointScale = Double(image.width) / imageWidthPoints

        let origin = snapshot.point(for: gym)
        let east = snapshot.point(for: coordinate(around: gym, xm: 1_000.0, ym: 0.0))
        let north = snapshot.point(for: coordinate(around: gym, xm: 0.0, ym: 1_000.0))
        let originX = Double(origin.x)
        let originY = Double(origin.y)
        let eastX = (Double(east.x) - originX) / 1_000.0
        let eastY = (Double(east.y) - originY) / 1_000.0
        let northX = (Double(north.x) - originX) / 1_000.0
        let northY = (Double(north.y) - originY) / 1_000.0
        let reach = pitchM * 0.3

        return await Task.detached(priority: .utility) { () -> [Double]? in
            MatrixStreetField.levels(
                image: image, pointScale: pointScale,
                originX: originX, originY: originY,
                eastX: eastX, eastY: eastY, northX: northX, northY: northY,
                cellXm: cellXm, cellYm: cellYm, hash: hash, reachM: reach
            )
        }.value
    }

    nonisolated static func coordinate(around c: CLLocationCoordinate2D, xm: Double, ym: Double) -> CLLocationCoordinate2D {
        let metresPerDegree = 111_320.0
        let latitude = c.latitude + ym / metresPerDegree
        let longitude = c.longitude + xm / (metresPerDegree * cos(c.latitude * Double.pi / 180.0))
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Reads the snapshot's pixels into an RGBA buffer, averages five samples per
    /// cell, then ranks the cells by brightness.
    nonisolated static func levels(
        image: CGImage,
        pointScale: Double,
        originX: Double, originY: Double,
        eastX: Double, eastY: Double,
        northX: Double, northY: Double,
        cellXm: [Double], cellYm: [Double], hash: [Double],
        reachM: Double
    ) -> [Double]? {
        let width = image.width
        let height = image.height
        guard width > 8, height > 8 else { return nil }
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let raw = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = raw.assumingMemoryBound(to: UInt8.self)
        let stride = context.bytesPerRow

        func luma(_ xm: Double, _ ym: Double) -> Double? {
            let px = ((originX + eastX * xm + northX * ym) * pointScale).rounded()
            let py = ((originY + eastY * xm + northY * ym) * pointScale).rounded()
            guard px >= 0, py >= 0, px < Double(width), py < Double(height) else { return nil }
            let offset = Int(py) * stride + Int(px) * 4
            let r = Double(pixels[offset])
            let g = Double(pixels[offset + 1])
            let b = Double(pixels[offset + 2])
            return (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
        }

        let offsets: [(Double, Double)] = [(0.0, 0.0), (reachM, 0.0), (-reachM, 0.0), (0.0, reachM), (0.0, -reachM)]
        var values = [Double](repeating: -1.0, count: cellXm.count)
        var valid: [Double] = []
        valid.reserveCapacity(cellXm.count)
        for index in 0..<cellXm.count {
            var total = 0.0
            var samples = 0.0
            for offset in offsets {
                if let value = luma(cellXm[index] + offset.0, cellYm[index] + offset.1) {
                    total += value
                    samples += 1.0
                }
            }
            if samples >= 3.0 {
                let mean = total / samples
                values[index] = mean
                valid.append(mean)
            }
        }
        guard valid.count > 50 else { return nil }
        valid.sort()
        let streetThreshold = valid[Int(Double(valid.count - 1) * 0.82)]
        let majorThreshold = valid[Int(Double(valid.count - 1) * 0.94)]
        let median = valid[valid.count / 2]
        // A flat map (no roads in view) has no contrast: show no streets rather than invent some.
        guard streetThreshold - median >= 0.012 else { return nil }

        var result = [Double](repeating: 0.2, count: cellXm.count)
        for index in 0..<cellXm.count {
            let value = values[index]
            if value < 0 { continue }
            if value >= streetThreshold {
                result[index] = value >= majorThreshold ? 2.6 : 2.0
            } else if value >= median && hash[index] < 0.22 {
                result[index] = 1.1
            }
        }
        return result
    }
}

// MARK: - Engine

/// Everything the board needs between frames: the dot grid, the resampled route,
/// the springs behind every dot's brightness, and the follow camera.
///
/// World units are grid cells (one cell is `pitch` metres), east = +x, north = +y,
/// origin at the gym, exactly like the prototype's cell space, so its constants
/// carry over unchanged.
@MainActor
private final class MatrixTripEngine {
    struct Input {
        var phase: TripPhase
        var entryStarted: Bool
        var view3D: Bool
        var reduceMotion: Bool
    }

    /// Where the user's dot was last drawn, in board coordinates.
    private(set) var userScreen: CGPoint?

    private struct RouteSignature: Equatable {
        var count: Int
        var firstLat: Double
        var firstLon: Double
        var lastLat: Double
        var lastLon: Double
    }

    private struct Extra {
        var x: Double
        var y: Double
        var isCheck: Bool
        var delay: Double
        var cur: Double = -1.5
        var vel: Double = 0.0
    }

    private struct Proj {
        var x: Double
        var y: Double
        var scale: Double
        var depth: Double
    }

    private struct Step {
        var t: Double
        var dt: Double
        var te: Double
        var px: Double
        var py: Double
        var s: Double
        var total: Double
        var left: Bool
        var arrived: Bool
        var rm: Bool
        var entryOn: Bool
        var leftT: Double
        var arrT: Double
        var width: Double
        var height: Double
    }

    // Grid
    private var hasGrid = false
    private var pitch: Double = 22.0
    private var cols = 0
    private var rows = 0
    private var gx0: Double = 0.0
    private var gy0: Double = 0.0
    private var gridVersion = 0
    private var cellX: [Double] = []
    private var cellY: [Double] = []
    private var hash: [Double] = []
    private var dGym: [Double] = []
    private var dStart: [Double] = []
    private var streetBase: [Double] = []
    private var base: [Double] = []
    private var cur: [Double] = []
    private var vel: [Double] = []
    private var onRoute: [Bool] = []
    private var streetTask: Task<Void, Never>?

    // Route
    private var lastSignature: RouteSignature?
    private var routeX: [Double] = []
    private var routeY: [Double] = []
    private var routeS: [Double] = []
    private var routeCur: [Double] = []
    private var routeVel: [Double] = []
    private var routeLength: Double = 1.0
    private var extras: [Extra] = []

    // Time and state
    private var lastTime: Double?
    private var entryStart: Double?
    private var lastTe: Double = 0.0
    private var leftT: Double = -1.0
    private var wasLeft = false
    private var arrT: Double = -1.0
    private var wasArrived = false
    private var seenFirstFrame = false
    private var ping: Double = 0.0

    // Smoothed user and heading
    private var dposX: Double = 0.0
    private var dposY: Double = 0.0
    private var dvelX: Double = 0.0
    private var dvelY: Double = 0.0
    private var hasPos = false
    private var hd: Double = Double.pi / 2.0
    private var hdS: Double = Double.pi / 2.0
    private var headingReady = false

    // Camera: tilt, ln distance, target x, target y, heading, anchor
    private var camV: [Double] = [0.0, 0.0, 0.0, 0.0, Double.pi / 2.0, 0.5]
    private var camW: [Double] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    private let omega: [Double] = [4.2, 4.0, 8.0, 8.0, 3.4, 4.2]
    private var snapCamera = true

    // Per-frame projection constants
    private var ca = 0.0
    private var sa = 1.0
    private var cph = 0.0
    private var sph = 1.0
    private var dd = 0.0
    private var hh = 0.0
    private var cxs = 0.0
    private var cys = 0.0
    private var tx = 0.0
    private var ty = 0.0
    private var fd0 = 0.0
    private var fdk = 1.0
    private var ff = 330.0

    private var buckets: [[Double]] = Array(repeating: [], count: 32)

    private let tilt = 48.0 * Double.pi / 180.0
    private let followDistance = 30.0

    func pingUser() {
        ping = 1.0
    }

    // MARK: Render

    func render(into ctx: inout GraphicsContext, size: CGSize, date: Date, model: TripModel, input: Input) {
        let width = Double(size.width)
        let height = Double(size.height)
        guard width > 10, height > 10 else { return }
        guard ensureWorld(model: model) else { return }

        let now = date.timeIntervalSinceReferenceDate
        var dt = 1.0 / 30.0
        if let previous = lastTime { dt = matrixTripClamp(now - previous, 0.0, 0.05) }
        lastTime = now

        let rm = input.reduceMotion
        let arrived = input.phase == .verifying || input.phase == .verified
        let left = input.phase.hasLeft

        // Entry clock. Opening mid-dwell or with Reduce Motion skips the show.
        if input.entryStarted && entryStart == nil {
            entryStart = (rm || arrived) ? now - 3.0 : now
        }
        var te = 0.0
        if let start = entryStart { te = now - start }
        let entryOn = entryStart != nil
        lastTe = te

        advanceStates(dt: dt, left: left, arrived: arrived)
        ping = max(0.0, ping - dt * 1.5)

        // The user, smoothed so 1 Hz fixes glide.
        let target = userTarget(model: model)
        followUser(targetX: target.x, targetY: target.y, dt: dt, snap: rm)
        let s = alongRoute(x: dposX, y: dposY)
        updateHeading(s: s, model: model, dt: dt)

        // Camera.
        ff = width * 0.95
        let overview = !input.view3D || (!rm && te < 1.15)
        let camTarget = cameraTarget(overview: overview, width: width, height: height, arrived: arrT >= 0)
        stepCamera(target: camTarget, dt: dt, snap: snapCamera || rm)
        snapCamera = false
        setProjection(width: width, height: height, rm: rm)

        let step = Step(
            t: now, dt: dt, te: te, px: dposX, py: dposY, s: s, total: routeLength,
            left: left, arrived: arrived, rm: rm, entryOn: entryOn,
            leftT: leftT, arrT: arrT, width: width, height: height
        )

        for index in 0..<buckets.count { buckets[index].removeAll(keepingCapacity: true) }
        projectCells(step)
        projectRoute(step)
        projectExtras(step)
        projectCone(step)
        let userProj = projectWorld(dposX, dposY, z: 0.3)
        projectGym(step, userProj: userProj)

        if !rm {
            let roll = matrixTripClamp(camW[4] * 0.05, -0.07, 0.07)
            if roll != 0 {
                ctx.translateBy(x: CGFloat(cxs), y: CGFloat(cys))
                ctx.rotate(by: .radians(roll))
                ctx.translateBy(x: CGFloat(-cxs), y: CGFloat(-cys))
            }
        }
        paintBuckets(&ctx)
        paintUser(&ctx, step: step, projection: userProj, hasUser: hasPos)
    }

    // MARK: World building

    /// Builds or refreshes the grid and route from the model. False until a route exists.
    private func ensureWorld(model: TripModel) -> Bool {
        let route = model.route
        guard route.count >= 2 else { return hasGrid && !routeX.isEmpty }
        let signature = RouteSignature(
            count: route.count,
            firstLat: route[0].latitude, firstLon: route[0].longitude,
            lastLat: route[route.count - 1].latitude, lastLon: route[route.count - 1].longitude
        )
        if hasGrid && signature == lastSignature { return true }
        lastSignature = signature

        let gym = model.gym
        // Only the last stretch of the route is drawn. A user who is far from
        // the gym (a different city, say) would otherwise stretch the dot grid
        // over hundreds of kilometres and leave every cell around them empty.
        let metres: [(x: Double, y: Double)] = MatrixTripEngine.clipTail(
            route.map { TripModel.local($0, around: gym) },
            limit: MatrixTripEngine.farLimit
        )
        var minX = 0.0
        var maxX = 0.0
        var minY = 0.0
        var maxY = 0.0
        for point in metres {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        for candidate in [model.origin, model.user] {
            guard let coordinate = candidate else { continue }
            let point = TripModel.local(coordinate, around: gym)
            if hypot(point.x, point.y) > MatrixTripEngine.farLimit { continue }
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        if !hasGrid || !gridCovers(minX: minX, maxX: maxX, minY: minY, maxY: maxY) {
            buildGrid(minX: minX, maxX: maxX, minY: minY, maxY: maxY, gym: gym)
        }
        buildRoute(metres: metres, model: model)
        return true
    }

    /// How far from the gym the dot world reaches, in metres.
    static let farLimit: Double = 6_000.0

    /// The part of a route (gym at the origin, last point at the gym) that lies
    /// within `limit` metres of the gym, starting exactly on that circle.
    nonisolated static func clipTail(_ points: [(x: Double, y: Double)], limit: Double) -> [(x: Double, y: Double)] {
        guard points.count >= 2 else { return points }
        var kept: [(x: Double, y: Double)] = []
        var index = points.count - 1
        while index >= 0 {
            let point = points[index]
            if hypot(point.x, point.y) <= limit {
                kept.append(point)
                index -= 1
                continue
            }
            if let inside = kept.last {
                var lo = 0.0
                var hi = 1.0
                for _ in 0..<24 {
                    let mid = (lo + hi) / 2.0
                    let x = point.x + (inside.x - point.x) * mid
                    let y = point.y + (inside.y - point.y) * mid
                    if hypot(x, y) > limit { lo = mid } else { hi = mid }
                }
                kept.append((x: point.x + (inside.x - point.x) * hi, y: point.y + (inside.y - point.y) * hi))
            }
            break
        }
        kept.reverse()
        return kept.count >= 2 ? kept : points
    }

    private func gridCovers(minX: Double, maxX: Double, minY: Double, maxY: Double) -> Bool {
        let gMinX = gx0 * pitch
        let gMaxX = (gx0 + Double(cols - 1)) * pitch
        let gMinY = gy0 * pitch
        let gMaxY = (gy0 + Double(rows - 1)) * pitch
        return minX >= gMinX + pitch && maxX <= gMaxX - pitch && minY >= gMinY + pitch && maxY <= gMaxY - pitch
    }

    /// About 60 x 100 cells covering the route plus a 25% margin.
    private func buildGrid(minX: Double, maxX: Double, minY: Double, maxY: Double, gym: CLLocationCoordinate2D) {
        let extentX = max(maxX - minX, 200.0)
        let extentY = max(maxY - minY, 200.0)
        let pad = max(0.25 * max(extentX, extentY), 150.0)
        let w = extentX + 2.0 * pad
        let h = extentY + 2.0 * pad
        let newPitch = matrixTripClamp(max(w / 60.0, h / 100.0), 14.0, 90.0)
        pitch = newPitch
        cols = min(Int((w / newPitch).rounded(.up)) + 1, 140)
        rows = min(Int((h / newPitch).rounded(.up)) + 1, 220)
        let centreX = (minX + maxX) / 2.0 / newPitch
        let centreY = (minY + maxY) / 2.0 / newPitch
        // Whole-cell origin so the gym sits exactly on a grid point.
        gx0 = (centreX - Double(cols - 1) / 2.0).rounded()
        gy0 = (centreY - Double(rows - 1) / 2.0).rounded()

        let count = cols * rows
        var xs = [Double](repeating: 0.0, count: count)
        var ys = [Double](repeating: 0.0, count: count)
        var hashes = [Double](repeating: 0.0, count: count)
        var gymDistance = [Double](repeating: 0.0, count: count)
        for j in 0..<rows {
            for i in 0..<cols {
                let index = j * cols + i
                let x = gx0 + Double(i)
                let y = gy0 + Double(j)
                xs[index] = x
                ys[index] = y
                let raw = sin(x * 12.9898 + y * 78.233) * 43758.5453
                hashes[index] = raw - raw.rounded(.down)
                gymDistance[index] = hypot(x, y)
            }
        }
        cellX = xs
        cellY = ys
        hash = hashes
        dGym = gymDistance
        dStart = [Double](repeating: 0.0, count: count)
        streetBase = [Double](repeating: 0.2, count: count)
        base = streetBase
        onRoute = [Bool](repeating: false, count: count)
        let entryDone = lastTe > 1.2
        cur = [Double](repeating: entryDone ? 0.2 : -1.5, count: count)
        vel = [Double](repeating: 0.0, count: count)
        hasGrid = true
        gridVersion += 1
        snapCamera = true
        startStreetLoad(gym: gym)
    }

    private func startStreetLoad(gym: CLLocationCoordinate2D) {
        let version = gridVersion
        let xs = cellX.map { $0 * pitch }
        let ys = cellY.map { $0 * pitch }
        let hashes = hash
        let pitchM = pitch
        let columns = cols
        let rowCount = rows
        streetTask?.cancel()
        streetTask = Task { [weak self] in
            let levels = await MatrixStreetField.load(
                gym: gym, cellXm: xs, cellYm: ys, hash: hashes,
                pitchM: pitchM, cols: columns, rows: rowCount
            )
            guard !Task.isCancelled, let self else { return }
            self.finishStreets(levels, version: version)
        }
    }

    private func finishStreets(_ levels: [Double]?, version: Int) {
        guard version == gridVersion, let levels, levels.count == streetBase.count else { return }
        streetBase = levels
        applyBase()
    }

    private func applyBase() {
        guard base.count == streetBase.count, onRoute.count == base.count else { return }
        for index in 0..<base.count {
            base[index] = onRoute[index] ? min(streetBase[index], 0.3) : streetBase[index]
        }
    }

    /// Resamples the route every half cell, and places the origin ring and check.
    private func buildRoute(metres: [(x: Double, y: Double)], model: TripModel) {
        let inverse = 1.0 / pitch
        let spacing = 0.5
        let points: [(x: Double, y: Double)] = metres.map { (x: $0.x * inverse, y: $0.y * inverse) }
        var xs: [Double] = []
        var ys: [Double] = []
        var ss: [Double] = []
        if let first = points.first {
            xs.append(first.x)
            ys.append(first.y)
            ss.append(0.0)
        }
        var cumulative = 0.0
        var nextSample = spacing
        for segment in 1..<points.count {
            let a = points[segment - 1]
            let b = points[segment]
            let length = hypot(b.x - a.x, b.y - a.y)
            if length < 1e-9 { continue }
            while nextSample <= cumulative + length {
                let t = (nextSample - cumulative) / length
                xs.append(a.x + (b.x - a.x) * t)
                ys.append(a.y + (b.y - a.y) * t)
                ss.append(nextSample)
                nextSample += spacing
            }
            cumulative += length
        }
        if let last = points.last, (ss.last ?? 0.0) < cumulative - 0.05 {
            xs.append(last.x)
            ys.append(last.y)
            ss.append(cumulative)
        }
        routeX = xs
        routeY = ys
        routeS = ss
        routeLength = max(cumulative, 1.0)
        let initial: Double = lastTe > 1.2 ? 3.0 : -1.5
        routeCur = [Double](repeating: initial, count: xs.count)
        routeVel = [Double](repeating: 0.0, count: xs.count)

        // Origin ring and check
        var startX = xs.first ?? 0.0
        var startY = ys.first ?? 0.0
        var newExtras: [Extra] = []
        if let origin = model.origin, hypot(TripModel.local(origin, around: model.gym).x, TripModel.local(origin, around: model.gym).y) <= MatrixTripEngine.farLimit {
            let o = TripModel.local(origin, around: model.gym)
            let ox = o.x * inverse
            let oy = o.y * inverse
            startX = ox
            startY = oy
            let ringCount = 22
            for j in 0..<ringCount {
                let angle = -Double.pi + Double(j) / Double(ringCount) * 2.0 * Double.pi
                let delay = (angle + Double.pi) / (2.0 * Double.pi) * 0.3
                newExtras.append(Extra(x: ox + cos(angle) * 3.3, y: oy + sin(angle) * 3.3, isCheck: false, delay: delay))
            }
            let offsets: [(Double, Double)] = [(-3.0, 1.0), (-2.0, 0.0), (-1.0, -1.0), (0.0, 0.0), (1.0, 1.0), (2.0, 2.0), (3.0, 3.0)]
            for (j, offset) in offsets.enumerated() {
                newExtras.append(Extra(x: ox + offset.0, y: oy + offset.1, isCheck: true, delay: 0.2 + Double(j) * 0.05))
            }
        }
        extras = newExtras

        // Cells: distance from the start (for the entry reveal) and route cells to quieten.
        for index in 0..<cellX.count {
            dStart[index] = hypot(cellX[index] - startX, cellY[index] - startY)
            onRoute[index] = false
        }
        for sample in 0..<xs.count {
            let i = Int((xs[sample] - gx0).rounded())
            let j = Int((ys[sample] - gy0).rounded())
            if i >= 0 && i < cols && j >= 0 && j < rows {
                onRoute[j * cols + i] = true
            }
        }
        applyBase()
    }

    // MARK: State

    private func advanceStates(dt: Double, left: Bool, arrived: Bool) {
        if left {
            if !wasLeft {
                // Opened already on the way: no ring collapse, no pulse.
                leftT = seenFirstFrame ? 0.0 : 99.0
            } else if leftT >= 0 {
                leftT += dt
            }
        } else {
            leftT = -1.0
        }
        wasLeft = left

        if arrived {
            if !wasArrived {
                arrT = 0.0
            } else if arrT >= 0 {
                arrT += dt
            }
        } else {
            arrT = -1.0
        }
        wasArrived = arrived
        seenFirstFrame = true
    }

    private func userTarget(model: TripModel) -> (x: Double, y: Double) {
        if let coordinate = model.snapped ?? model.user {
            let p = TripModel.local(coordinate, around: model.gym)
            // Far away: wait at the start of the drawn stretch.
            if hypot(p.x, p.y) > MatrixTripEngine.farLimit, let x = routeX.first, let y = routeY.first {
                return (x, y)
            }
            return (p.x / pitch, p.y / pitch)
        }
        if let x = routeX.first, let y = routeY.first { return (x, y) }
        return (0.0, 0.0)
    }

    /// Critically damped follow of the latest fix, so the dot glides between GPS updates.
    private func followUser(targetX: Double, targetY: Double, dt: Double, snap: Bool) {
        if !hasPos || snap {
            if !hasPos { hasPos = true }
            dposX = targetX
            dposY = targetY
            dvelX = 0.0
            dvelY = 0.0
            return
        }
        let w = 6.0
        dvelX += (w * w * (targetX - dposX) - 2.0 * w * dvelX) * dt
        dvelY += (w * w * (targetY - dposY) - 2.0 * w * dvelY) * dt
        dposX += dvelX * dt
        dposY += dvelY * dt
    }

    /// Distance along the resampled route, in cells, of the point nearest to (x, y).
    private func alongRoute(x: Double, y: Double) -> Double {
        guard routeX.count >= 2 else { return 0.0 }
        var best = Double.greatestFiniteMagnitude
        var bestS = 0.0
        for i in 0..<(routeX.count - 1) {
            let ax = routeX[i]
            let ay = routeY[i]
            let dx = routeX[i + 1] - ax
            let dy = routeY[i + 1] - ay
            let lengthSquared = dx * dx + dy * dy
            var t = lengthSquared > 0 ? ((x - ax) * dx + (y - ay) * dy) / lengthSquared : 0.0
            t = matrixTripClamp(t, 0.0, 1.0)
            let ex = x - (ax + dx * t)
            let ey = y - (ay + dy * t)
            let d = ex * ex + ey * ey
            if d < best {
                best = d
                bestS = routeS[i] + (routeS[i + 1] - routeS[i]) * t
            }
        }
        return bestS
    }

    private func routePoint(at s: Double) -> (x: Double, y: Double) {
        guard !routeX.isEmpty else { return (0.0, 0.0) }
        let f = max(0.0, s) / 0.5
        let i = min(Int(f), routeX.count - 1)
        let j = min(i + 1, routeX.count - 1)
        let t = matrixTripClamp(f - Double(i), 0.0, 1.0)
        return (routeX[i] + (routeX[j] - routeX[i]) * t, routeY[i] + (routeY[j] - routeY[i]) * t)
    }

    /// Looks 7 cells ahead along the route; falls back to the model's bearing.
    private func updateHeading(s: Double, model: TripModel, dt: Double) {
        let ahead = routePoint(at: min(s + 7.0, routeLength))
        let ddx = ahead.x - dposX
        let ddy = ahead.y - dposY
        if ddx * ddx + ddy * ddy > 0.25 {
            hd = atan2(ddy, ddx)
        } else {
            hd = Double.pi / 2.0 - Double(model.heading) * Double.pi / 180.0
        }
        if !headingReady {
            hdS = hd
            headingReady = true
        }
        hdS += matrixTripWrap(hd - hdS) * min(1.0, dt * 6.0)
    }

    // MARK: Camera

    private func cameraTarget(overview: Bool, width: Double, height: Double, arrived: Bool) -> [Double] {
        if overview {
            let fit = min(width / Double(cols + 4), height / Double(rows + 4))
            let centreX = gx0 + Double(cols - 1) / 2.0
            let centreY = gy0 + Double(rows - 1) / 2.0
            return [0.0, log(ff / max(fit, 0.01)), centreX, centreY, Double.pi / 2.0, 0.5]
        }
        return [tilt, log(followDistance), dposX, dposY, hdS, arrived ? 0.84 : 0.70]
    }

    private func stepCamera(target: [Double], dt: Double, snap: Bool) {
        for i in 0..<6 {
            var d = target[i] - camV[i]
            if i == 4 { d = matrixTripWrap(d) }
            if snap {
                camV[i] += d
                camW[i] = 0.0
                continue
            }
            let w = omega[i]
            camW[i] += (w * w * d - 2.0 * w * camW[i]) * dt
            camV[i] += camW[i] * dt
        }
    }

    private func setProjection(width: Double, height: Double, rm: Bool) {
        let tiltNow = camV[0]
        let distance = exp(camV[1])
        tx = camV[2]
        ty = camV[3]
        let angle = camV[4]
        ca = cos(angle)
        sa = sin(angle)
        cph = sin(tiltNow)
        sph = cos(tiltNow)
        dd = distance * cph
        hh = distance * sph
        let lean = rm ? 0.0 : matrixTripClamp(camW[4] * 14.0, -22.0, 22.0)
        cxs = width / 2.0 + lean
        cys = height * camV[5]
        fd0 = distance * 1.3
        fdk = 1.0 / (distance * 2.5)
    }

    // MARK: Projection

    private func projectCamera(right: Double, forward: Double, z: Double) -> Proj? {
        let dy = forward + dd
        let depth = dy * cph + (hh - z) * sph
        if depth < 3.0 { return nil }
        let scale = ff / depth
        return Proj(x: cxs + right * scale, y: cys - (dy * sph + (z - hh) * cph) * scale, scale: scale, depth: depth)
    }

    private func projectWorld(_ wx: Double, _ wy: Double, z: Double) -> Proj? {
        let rx = wx - tx
        let ry = wy - ty
        return projectCamera(right: rx * sa - ry * ca, forward: rx * ca + ry * sa, z: z)
    }

    private func fadeOf(_ depth: Double) -> Double {
        let u = (depth - fd0) * fdk
        if u <= 0 { return 1.0 }
        if u >= 1 { return 0.0 }
        return 1.0 - u * u * (3.0 - 2.0 * u)
    }

    private func put(_ x: Double, _ y: Double, _ radius: Double, _ alpha: Double) {
        if alpha < 0.03 || radius < 0.3 { return }
        let bucket = min(31, Int((alpha * 31.0).rounded()))
        if bucket < 1 { return }
        buckets[bucket].append(x)
        buckets[bucket].append(y)
        buckets[bucket].append(radius)
    }

    // MARK: Dots

    /// The street grid: every cell springs towards its level, then is projected.
    private func projectCells(_ st: Step) {
        let n = cellX.count
        guard n > 0, base.count == n, cur.count == n else { return }
        let f = min(2.0, st.dt * 60.0)
        let damp = pow(st.rm ? 0.5 : 0.7, f)
        let kk = st.rm ? 0.12 : 0.2
        var revealRadius = -1.0
        if st.entryOn {
            let reach = Double(max(cols, rows))
            revealRadius = st.rm ? 1e9 : (st.te < 0.8 ? st.te / 0.7 * reach : 1e9)
        }
        let wave = st.arrived && !st.rm ? st.arrT * 22.0 : -99.0
        let twinkle = !st.rm && !st.arrived
        let distance = exp(camV[1])
        let width = st.width
        let height = st.height

        for i in 0..<n {
            let x = cellX[i]
            let y = cellY[i]
            var l = base[i]
            if wave > 0 && dGym[i] > 6.0 {
                let diff = abs(dGym[i] - wave)
                if diff < 2.5 {
                    l = max(l, 4.0 * (1.0 - diff / 2.5) * (1.0 - matrixTripClamp(wave / 40.0, 0.0, 1.0)))
                }
            }
            if abs(x - st.px) < 0.9 && abs(y - st.py) < 0.9 { l = min(l, 0.4) }
            if dStart[i] > revealRadius { l = -1.5 }

            vel[i] += (l - cur[i]) * kk * f
            vel[i] *= damp
            cur[i] += vel[i] * f

            let rx = x - tx
            let ry = y - ty
            let dy = rx * ca + ry * sa + dd
            let depth = dy * cph + hh * sph
            if depth < 3.0 { continue }
            let scale = ff / depth
            let sx = cxs + (rx * sa - ry * ca) * scale
            if sx < -16.0 || sx > width + 16.0 { continue }
            let sy = cys - (dy * sph - hh * cph) * scale
            if sy < -16.0 || sy > height + 16.0 { continue }

            var c = cur[i]
            if twinkle && base[i] >= 1.0 { c += 0.35 * sin(st.t * 1.3 + hash[i] * 40.0) }
            var near = 1.0
            if distance < 40.0 && depth < distance * 0.9 {
                near = matrixTripClamp((depth - distance * 0.22) / (distance * 0.5), 0.0, 1.0)
            }
            let alpha = matrixTripLevelAlpha(c) * fadeOf(depth) * near
            put(sx, sy, scale * (0.11 + 0.17 * matrixTripClamp(c, 0.0, 6.0) / 6.0), alpha)
        }
    }

    /// The route dots: bright ahead, dim behind with a glowing tail, a slow scan
    /// towards the gym, and the pulse that runs out of the origin when he leaves.
    private func projectRoute(_ st: Step) {
        let count = routeX.count
        guard count > 0, routeCur.count == count else { return }
        let f = min(2.0, st.dt * 60.0)
        let damp = pow(st.rm ? 0.5 : 0.7, f)
        let kk = st.rm ? 0.12 : 0.2
        let revealStart = st.rm ? 0.1 : 0.3
        let revealSpan = st.rm ? 0.01 : 0.65
        let total = max(st.total, 1.0)
        let scanPosition: Double = st.rm ? -99.0 : st.s + (st.t.truncatingRemainder(dividingBy: 4.0) / 4.0) * (total - st.s + 8.0)
        let pulse: Double = (st.leftT >= 0 && !st.rm) ? st.leftT * 55.0 : -99.0

        for i in 0..<count {
            let k = routeS[i]
            let visible = st.entryOn && st.te > revealStart + k / total * revealSpan
            var l = -1.5
            if visible {
                if st.arrived {
                    l = 3.0
                } else if k < st.s - 0.6 {
                    l = 1.0 + 3.6 * exp((k - st.s) / 2.4)
                } else {
                    l = 6.0
                    let q = (k - scanPosition) / 3.5
                    if q < 3.0 && q > -3.0 { l += 1.1 * exp(-q * q) }
                }
                let q2 = k - pulse
                if q2 < 6.0 && q2 > -6.0 { l += 3.2 * exp(-pow(q2 / 3.2, 2.0)) }
                l = min(l, 6.8)
            }
            routeVel[i] += (l - routeCur[i]) * kk * f
            routeVel[i] *= damp
            routeCur[i] += routeVel[i] * f
            if !visible { continue }

            guard let p = projectWorld(routeX[i], routeY[i], z: 0.0) else { continue }
            if p.x < -16.0 || p.x > st.width + 16.0 || p.y < -16.0 || p.y > st.height + 16.0 { continue }
            let c = routeCur[i]
            let alpha = matrixTripLevelAlpha(c) * fadeOf(p.depth)
            put(p.x, p.y, p.scale * (0.11 + 0.17 * matrixTripClamp(c, 0.0, 6.0) / 6.0) * 0.8, alpha)
        }
    }

    /// The ring at the origin, which collapses into a check when the user leaves.
    private func projectExtras(_ st: Step) {
        guard !extras.isEmpty else { return }
        let f = min(2.0, st.dt * 60.0)
        let damp = pow(st.rm ? 0.5 : 0.7, f)
        let kk = st.rm ? 0.12 : 0.2
        for j in 0..<extras.count {
            var target = -1.5
            if st.entryOn {
                if extras[j].isCheck {
                    target = (st.left && st.leftT > extras[j].delay) ? 5.5 : -1.5
                } else {
                    target = (!st.left || st.leftT < extras[j].delay) ? 5.0 : -1.5
                }
            }
            extras[j].vel += (target - extras[j].cur) * kk * f
            extras[j].vel *= damp
            extras[j].cur += extras[j].vel * f
            if extras[j].cur < -0.8 { continue }
            guard let p = projectWorld(extras[j].x, extras[j].y, z: 0.0) else { continue }
            if p.x < -16.0 || p.x > st.width + 16.0 || p.y < -16.0 || p.y > st.height + 16.0 { continue }
            let c = extras[j].cur
            put(p.x, p.y, p.scale * (0.11 + 0.17 * matrixTripClamp(c, 0.0, 6.0) / 6.0), matrixTripLevelAlpha(c) * fadeOf(p.depth))
        }
    }

    /// Four brighter white dots ahead of the user, pointing the way.
    private func projectCone(_ st: Step) {
        guard st.te > 0.25, hasPos else { return }
        let ch = cos(hdS)
        let sh = sin(hdS)
        let spots: [(Double, Double)] = [(2.3, 0.0), (3.6, -0.85), (3.6, 0.85), (5.0, 0.0)]
        for spot in spots {
            let wx = st.px + ch * spot.0 + sh * spot.1
            let wy = st.py + sh * spot.0 - ch * spot.1
            guard let p = projectWorld(wx, wy, z: 0.15) else { continue }
            let wobble = st.rm ? 0.3 : 0.4 * sin(st.t * 4.0 - spot.0 * 1.3)
            let alpha = matrixTripClamp(0.55 + wobble, 0.2, 1.0) * fadeOf(p.depth)
            put(p.x, p.y, p.scale * 0.17, alpha)
        }
    }

    /// The gym: an upright dumbbell billboard facing the camera, a beam of dots down
    /// to the ground and a ring on the ground, breathing softly.
    private func projectGym(_ st: Step, userProj: Proj?) {
        guard st.te > 1.0 else { return }
        let pop: Double = st.rm ? 1.0 : matrixTripEaseBack((st.te - 1.0) / 0.45)
        let breath: Double = st.rm ? 0.5 : 0.5 + 0.5 * sin(st.t * 1.8)
        let pulse: Double = (st.leftT >= 0 && !st.rm) ? st.leftT * 55.0 : -99.0
        var boost = st.arrived ? 0.25 : 0.0
        if pulse > st.total - 2.0 { boost += 0.3 * exp(-pow((pulse - st.total) / 10.0, 2.0)) }

        let gx = 0.0 - tx
        let gy = 0.0 - ty
        let right = gx * sa - gy * ca
        let forward = gx * ca + gy * sa
        let spacing = 1.15
        let brightness = matrixTripClamp(0.7 + 0.25 * breath + boost, 0.0, 1.0)

        for r in 0..<5 {
            let row = Array(MatrixTripStyle.gymRows[r])
            for c in 0..<11 where row[c] == "#" {
                let offset = Double(c - 5) * spacing * pop
                let z = pop * (2.6 + Double(4 - r) * spacing)
                guard let p = projectCamera(right: right + offset, forward: forward, z: z) else { continue }
                put(p.x, p.y, p.scale * spacing * 0.43 * pop, brightness * max(0.62, fadeOf(p.depth)))
            }
        }
        var z = 0.0
        while z <= 2.2 {
            if let p = projectCamera(right: right, forward: forward, z: z * pop) {
                let level = (0.5 + 0.35 * breath + boost * 0.5) * (0.5 + 0.5 * (z / 2.2))
                put(p.x, p.y, p.scale * 0.2, level * max(0.6, fadeOf(p.depth)) * matrixTripClamp(pop, 0.0, 1.0))
            }
            z += 0.45
        }
        for j in 0..<12 {
            let angle = Double(j) / 12.0 * 2.0 * Double.pi
            if let p = projectWorld(cos(angle) * 1.7, sin(angle) * 1.7, z: 0.0) {
                put(p.x, p.y, p.scale * 0.14, (0.45 + 0.2 * breath) * max(0.6, fadeOf(p.depth)) * matrixTripClamp(pop, 0.0, 1.0))
            }
        }
    }

    // MARK: Paint

    private func paintBuckets(_ ctx: inout GraphicsContext) {
        for bucket in 1..<32 {
            let values = buckets[bucket]
            if values.isEmpty { continue }
            var path = Path()
            var o = 0
            while o + 2 < values.count {
                let r = values[o + 2]
                path.addEllipse(in: matrixTripRect(values[o] - r, values[o + 1] - r, 2.0 * r, 2.0 * r))
                o += 3
            }
            ctx.fill(path, with: .color(MatrixTripStyle.bucketColors[bucket]))
        }
    }

    /// The user: a coral dot, two expanding rings of coral dots, and a soft halo.
    /// The only coral on the screen.
    private func paintUser(_ ctx: inout GraphicsContext, step st: Step, projection: Proj?, hasUser: Bool) {
        guard hasUser, st.te > 0.15, let u = projection else {
            userScreen = nil
            return
        }
        userScreen = CGPoint(x: CGFloat(u.x), y: CGFloat(u.y))
        let fade = matrixTripClamp((st.te - 0.15) / 0.3, 0.0, 1.0)
        let breathe: Double = st.rm ? 0.5 : sin(st.t * 2.2) * 0.5 + 0.5 + ping
        let haloRadius = (1.8 + 0.5 * breathe) * u.scale
        let halo = Path(ellipseIn: matrixTripRect(u.x - haloRadius, u.y - haloRadius * sph, 2.0 * haloRadius, 2.0 * haloRadius * sph))
        ctx.fill(halo, with: .color(Theme.accent.opacity(0.14 * fade)))

        for ring in 0..<2 {
            let phase: Double = st.rm ? 0.35 + Double(ring) * 0.35 : (st.t * 0.5 + Double(ring) * 0.5).truncatingRemainder(dividingBy: 1.0)
            let radius = 0.9 + phase * 6.0
            let alpha = pow(1.0 - phase, 1.3) * 0.75 * fade
            var path = Path()
            for j in 0..<20 {
                let angle = Double(j) / 20.0 * 2.0 * Double.pi + Double(ring) * 0.3
                guard let p = projectWorld(st.px + cos(angle) * radius, st.py + sin(angle) * radius, z: 0.0) else { continue }
                let r = p.scale * 0.13
                path.addEllipse(in: matrixTripRect(p.x - r, p.y - r, 2.0 * r, 2.0 * r))
            }
            ctx.fill(path, with: .color(Theme.accent.opacity(alpha)))
        }

        let dotRadius = max(3.0, u.scale * 0.55)
        let dot = Path(ellipseIn: matrixTripRect(u.x - dotRadius, u.y - u.scale * 0.1 - dotRadius, 2.0 * dotRadius, 2.0 * dotRadius))
        ctx.fill(dot, with: .color(Theme.accent.opacity(fade)))
    }
}
