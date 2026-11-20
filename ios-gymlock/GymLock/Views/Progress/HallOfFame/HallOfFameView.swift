import SwiftUI

/// The Hall of Fame: a full-screen film strip of every progress photo, with a
/// scripted entrance and exit, pinch between Photo / Day / Week / Month, and a
/// level capsule. The Progress tab presents it with the system animation off.
struct HallOfFameView: View {
    let store: ProgressPhotoStore
    /// Called after the close animation ends.
    let onClose: () -> Void
    @AppStorage(HeroCardStyle.storageKey) private var styleRaw = HeroCardStyle.default.rawValue

    private enum Phase: Equatable {
        case intro(start: Date)
        case live
        case closing(start: Date)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    @State private var phase: Phase = .intro(start: .distantFuture)
    @State private var level: HallOfFameLevel = .day
    @State private var pinchScale: CGFloat = 1
    @State private var pinchAnchor: UnitPoint = .center
    @State private var scrollPosition: String?
    @State private var firedEvents: ReelEvents = []

    @State private var configured = false
    @State private var fade: Double = 1
    @State private var pinchActive = false
    @State private var pinchLimitFired = false
    @State private var pinchAnchorID: String?
    @State private var reachedStartFired = false
    @State private var isCommitting = false
    @State private var isClosing = false
    @State private var didClose = false
    @Namespace private var pillSpace

    private let allEvents: ReelEvents = [.reelLanded, .titleComplete, .revolution1, .revolution2, .revolution3, .stripSeated]

    private var style: HeroCardStyle { HeroCardStyle(rawValue: styleRaw) ?? .default }
    private var isDemo: Bool { store.photos.isEmpty }
    private var isLive: Bool { phase == .live }

    // MARK: Body

    var body: some View {
        let frames = HallOfFameModel.frames(photos: store.photos, installDate: store.installDate)
        // Shown oldest at the top, newest at the bottom; the strip opens on the newest.
        let sections = HallOfFameModel.sections(frames, level: level).reversed().map {
            HallOfFameSection(id: $0.id, title: $0.title, countText: $0.countText, frames: $0.frames.reversed())
        }
        let levels = HallOfFameModel.availableLevels(isDemo: isDemo)

        // The outer reader respects the safe area so its insets are the real
        // notch / Dynamic Island / home indicator; the inner one fills the screen
        // (a reader that ignores the safe area reports zero insets).
        GeometryReader { outer in
            let insets = outer.safeAreaInsets
            GeometryReader { geo in
                let layout = makeLayout(size: geo.size, insets: insets)
                ZStack(alignment: .topLeading) {
                    Theme.canvas
                    TimelineView(.animation(paused: isLive)) { ctx in
                        let pose = currentPose(date: ctx.date, layout: layout)
                        screen(pose: pose, layout: layout, size: geo.size, insets: insets,
                               frames: frames, sections: sections, levels: levels)
                            .onChange(of: ctx.date) { _, date in
                                tick(date: date, layout: layout)
                            }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .opacity(configured ? fade : 0)
            }
            .ignoresSafeArea()
        }
        .onAppear { start() }
        .onChange(of: scrollPosition) { _, new in
            if level == .photo, isLive, !isCommitting, !isClosing, new != nil {
                HallOfFameHaptics.pageChanged()
            }
        }
    }

    // MARK: Screen

    @ViewBuilder
    private func screen(pose: ReelPose?, layout: ReelLayout, size: CGSize, insets: EdgeInsets,
                        frames: [HallOfFameFrame], sections: [HallOfFameSection],
                        levels: [HallOfFameLevel]) -> some View {
        let safeTop = insets.top
        let capB = max(insets.bottom, 8) + 8
        let introBox = pose == nil ? size.height : max(size.height, ReelScene.introBoxHeight(layout: layout))
        let chrome = pose?.chromeOpacity ?? 1
        let clip: CGFloat = {
            if let pose, pose.filmClipLength.isFinite { return pose.filmClipLength > 0.5 ? pose.filmClipLength : 0 }
            return .infinity
        }()
        let titleProgress = pose?.titleProgress ?? 1
        let titleGlide = pose?.titleGlide ?? 1
        let titleOpacity: Double = {
            if case .closing(let s) = phase, !reduceMotion {
                return 1 - min(max(Date().timeIntervalSince(s) / 0.3, 0), 1)
            }
            return 1
        }()

        ZStack(alignment: .topLeading) {
            FilmStripView(
                sections: sections,
                level: level,
                style: style,
                stripWidth: layout.stripWidth,
                topInset: layout.stripTop,
                bottomInset: capB + 44 + 24,
                pinchScale: pinchScale,
                pinchAnchor: pinchAnchor,
                scrollPosition: $scrollPosition,
                onTapFrame: { openPhoto($0) },
                onReachStart: { reachedStart() },
                introLeader: max(introBox - size.height, 0)
            )
            // While the film lies on the floor the box is taller than the
            // screen (src HBOX) and only the laid length below the strip top
            // shows (src clip-path inset). Live: plain screen-sized box.
            .frame(width: size.width, height: introBox, alignment: .top)
            .mask(alignment: .top) {
                if pose == nil {
                    Rectangle()
                } else {
                    Rectangle()
                        .frame(width: size.width, height: clip)
                        .padding(.top, layout.stripTop)
                }
            }
            .projectionEffect(pose?.floorTransform ?? ProjectionTransform(CGAffineTransform.identity))
            .allowsHitTesting(isLive && !isClosing)
            .simultaneousGesture(magnify(frames: frames, layout: layout, size: size))

            // Fades in the canvas colour (not glass).
            VStack(spacing: 0) {
                LinearGradient(stops: [.init(color: Theme.canvas, location: 0),
                                       .init(color: Theme.canvas, location: 0.62),
                                       .init(color: Theme.canvas.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: safeTop + 62)
                Spacer(minLength: 0)
                LinearGradient(colors: [Theme.canvas, Theme.canvas.opacity(0)],
                               startPoint: .bottom, endPoint: .top)
                    .opacity(0.7)
                    .frame(height: capB + 74)
            }
            .frame(width: size.width, height: size.height)
            .opacity(chrome)
            .allowsHitTesting(false)

            if let pose, !reduceMotion, pose.reelVisible {
                ReelCanvas(t: pose.t, isClosing: isClosingPhase, style: style, layout: layout)
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
            }

            HallOfFameTitle(progress: titleProgress, glide: titleGlide, style: style,
                            counter: counterText(frames: frames), safeTop: safeTop)
                .frame(width: size.width, height: size.height)
                .opacity(titleOpacity)

            if case .intro = phase {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { skipIntro() }
                    .frame(width: size.width, height: size.height)
            }

            GlassCircleButton(symbol: "xmark", label: "Close") { close(frames: frames) }
                .frame(width: 44, height: 44)
                .padding(.leading, 14)
                .padding(.top, max(safeTop - 3, 0))
                .opacity(chrome)
                .allowsHitTesting(isLive && !isClosing)

            capsule(levels: levels, frames: frames, layout: layout, size: size)
                .frame(width: size.width, height: size.height, alignment: .bottom)
                .padding(.bottom, 0)
                .offset(y: -capB)
                .opacity(chrome)
                .allowsHitTesting(isLive && !isClosing)
        }
        // Top-leading: while the film lies on the floor the stage is taller
        // than the screen, and centring it pushed the reel and title off the top.
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var isClosingPhase: Bool {
        if case .closing = phase { return true }
        return false
    }

    // MARK: Chrome

    private func capsule(levels: [HallOfFameLevel], frames: [HallOfFameFrame],
                         layout: ReelLayout, size: CGSize) -> some View {
        let width = min(316, size.width - 24)
        return HStack(spacing: 0) {
            ForEach(levels) { l in
                Button {
                    step(to: l, frames: frames, size: size, layout: layout)
                } label: {
                    Text(l.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(l == level ? Theme.surface : Theme.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if l == level {
                                Capsule().fill(Theme.ink)
                                    .padding(.vertical, 4)
                                    .matchedGeometryEffect(id: "pill", in: pillSpace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(l == level ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        .frame(width: width, height: 44)
        .glassCapsule()
        .frame(maxWidth: .infinity)
    }

    // MARK: Layout

    private func makeLayout(size: CGSize, insets: EdgeInsets) -> ReelLayout {
        // Same rule as the prototype and ReelScene: min(330, round(W * 0.84)),
        // one point narrower when the side margins would be uneven, so the
        // composited floor layer lands on whole pixels at scroll 0.
        let w = size.width
        var strip = min(330, (w * 0.84).rounded())
        if Int(w - strip) % 2 != 0 { strip -= 1 }
        return ReelLayout(size: size, safeTop: insets.top,
                          stripWidth: strip, stripTop: insets.top + 66)
    }

    // MARK: Clock

    private func currentPose(date: Date, layout: ReelLayout) -> ReelPose? {
        switch phase {
        case .live:
            return nil
        case .intro(let start):
            let t = max(0, date.timeIntervalSince(start))
            if t >= ReelTimeline.total { return nil }
            return ReelScene.pose(at: t, layout: layout)
        case .closing(let start):
            let t = max(0, date.timeIntervalSince(start))
            return ReelScene.closePose(at: min(t, ReelTimeline.closeTotal), layout: layout)
        }
    }

    private func tick(date: Date, layout: ReelLayout) {
        switch phase {
        case .intro(let start):
            let t = max(0, date.timeIntervalSince(start))
            let pose = ReelScene.pose(at: min(t, ReelTimeline.total), layout: layout)
            fire(pose.events)
            if t >= ReelTimeline.total { phase = .live }
        case .closing(let start):
            if date.timeIntervalSince(start) >= ReelTimeline.closeTotal, !didClose {
                didClose = true
                onClose()
            }
        case .live:
            break
        }
    }

    private func fire(_ events: ReelEvents) {
        let new = events.subtracting(firedEvents)
        guard !new.isEmpty else { return }
        if new.contains(.reelLanded) { HallOfFameHaptics.reelLands() }
        if new.contains(.titleComplete) { HallOfFameHaptics.titleComplete() }
        if new.contains(.revolution1) { HallOfFameHaptics.reelRevolution() }
        if new.contains(.revolution2) { HallOfFameHaptics.reelRevolution() }
        if new.contains(.revolution3) { HallOfFameHaptics.reelRevolution() }
        if new.contains(.stripSeated) { HallOfFameHaptics.stripSeated() }
        firedEvents.formUnion(new)
    }

    private func start() {
        HallOfFameHaptics.prepare()
        if reduceMotion {
            phase = .live
            firedEvents = allEvents
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { fade = 0; configured = true }
            withAnimation(.easeOut(duration: 0.2)) { fade = 1 }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                HallOfFameHaptics.stripSeated()
            }
        } else {
            phase = .intro(start: Date())
            configured = true
        }
    }

    private func skipIntro() {
        guard case .intro = phase else { return }
        let seated = firedEvents.contains(.stripSeated)
        firedEvents = allEvents
        phase = .live
        if !seated { HallOfFameHaptics.stripSeated() }
    }

    // MARK: Close

    private func close(frames: [HallOfFameFrame]) {
        guard isLive, !isClosing else { return }
        isClosing = true
        HallOfFameHaptics.close()
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { fade = 0 }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                onClose()
            }
            return
        }
        let needsScroll = scrollPosition != nil && scrollPosition != frames.first?.id
        let needsLevel = level != .day
        withAnimation(Theme.pageTurn) {
            if needsLevel { level = .day }
            scrollPosition = frames.first?.id
            pinchScale = 1
        }
        let wait: Duration = (needsScroll || needsLevel) ? .milliseconds(420) : .milliseconds(0)
        Task { @MainActor in
            try? await Task.sleep(for: wait)
            phase = .closing(start: Date())
        }
    }

    // MARK: Levels

    private func availableCoarser(_ levels: [HallOfFameLevel]) -> HallOfFameLevel? {
        guard let c = level.coarser, levels.contains(c) else { return nil }
        return c
    }

    private func availableFiner(_ levels: [HallOfFameLevel]) -> HallOfFameLevel? {
        guard let f = level.finer, levels.contains(f) else { return nil }
        return f
    }

    /// Rubber band: 1:1 inside 0.7...1.4 (only where a level exists beyond),
    /// heavy resistance outside it.
    private func rubber(_ s: CGFloat, canCoarser: Bool, canFiner: Bool) -> CGFloat {
        if s < 1 {
            if !canCoarser { return 1 - (1 - s) * 0.12 }
            return s < 0.7 ? 0.7 - (0.7 - s) * 0.3 : s
        }
        if !canFiner { return 1 + (s - 1) * 0.12 }
        return s > 1.4 ? 1.4 + (s - 1.4) * 0.3 : s
    }

    private func magnify(frames: [HallOfFameFrame], layout: ReelLayout, size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard isLive, !isClosing else { return }
                let levels = HallOfFameModel.availableLevels(isDemo: isDemo)
                if !pinchActive {
                    pinchActive = true
                    pinchLimitFired = false
                    pinchAnchor = value.startAnchor
                    pinchAnchorID = frameID(atFraction: value.startAnchor.y, frames: frames, layout: layout, size: size)
                }
                let raw = value.magnification
                let s = rubber(raw, canCoarser: availableCoarser(levels) != nil, canFiner: availableFiner(levels) != nil)
                pinchScale = s
                if !pinchLimitFired, abs(s - raw) > 0.0005 {
                    pinchLimitFired = true
                    HallOfFameHaptics.pinchLimit()
                }
            }
            .onEnded { value in
                guard pinchActive else { return }
                pinchActive = false
                let levels = HallOfFameModel.availableLevels(isDemo: isDemo)
                let raw = value.magnification
                let predicted = raw + value.velocity * 0.15
                var target: HallOfFameLevel?
                if let c = availableCoarser(levels), raw < 0.85 || predicted < 0.85 {
                    target = c
                } else if let f = availableFiner(levels), raw > 1.15 || predicted > 1.15 {
                    target = f
                }
                if let target {
                    commit(target, anchorID: pinchAnchorID)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { pinchScale = 1 }
                }
                pinchAnchorID = nil
            }
    }

    private func step(to l: HallOfFameLevel, frames: [HallOfFameFrame], size: CGSize, layout: ReelLayout) {
        guard isLive, !isClosing, l != level, !pinchActive else { return }
        let id = frameID(atFraction: 0.5, frames: frames, layout: layout, size: size)
        commit(l, anchorID: id)
    }

    private func commit(_ target: HallOfFameLevel, anchorID: String?) {
        isCommitting = true
        let id = anchorID ?? scrollPosition
        pinchAnchor = .center
        withAnimation(Theme.pageTurn) {
            level = target
            pinchScale = 1
            scrollPosition = id
        }
        HallOfFameHaptics.levelChanged()
        Task { @MainActor in
            // Re-seat after the new layout exists, then allow page haptics again.
            scrollPosition = id
            try? await Task.sleep(for: .milliseconds(450))
            isCommitting = false
        }
    }

    private func openPhoto(_ frame: HallOfFameFrame) {
        guard isLive, !isClosing, level != .photo else { return }
        isCommitting = true
        pinchAnchor = .center
        withAnimation(Theme.pageTurn) {
            level = .photo
            pinchScale = 1
            scrollPosition = frame.id
        }
        HallOfFameHaptics.openPhoto()
        Task { @MainActor in
            scrollPosition = frame.id
            try? await Task.sleep(for: .milliseconds(450))
            isCommitting = false
        }
    }

    private func reachedStart() {
        guard !reachedStartFired, isLive else { return }
        reachedStartFired = true
        HallOfFameHaptics.reachedStart()
    }

    /// The frame near a vertical fraction of the viewport, estimated from the
    /// frame at the top (`scrollPosition`) and the row height of the level.
    private func frameID(atFraction f: CGFloat, frames: [HallOfFameFrame],
                         layout: ReelLayout, size: CGSize) -> String? {
        guard !frames.isEmpty else { return nil }
        // Display order: oldest at the top.
        let frames = Array(frames.reversed())
        let top = scrollPosition.flatMap { id in frames.firstIndex { $0.id == id } } ?? 0
        let cols = max(level.columns, 1)
        let rowH: CGFloat
        switch level {
        case .photo: rowH = size.height
        default: rowH = max(layout.stripWidth / CGFloat(cols) * 1.25, 1)
        }
        let rows = Int(max(0, f * size.height - layout.stripTop) / rowH)
        let idx = min(max(top + rows * cols + cols / 2, 0), frames.count - 1)
        return frames[idx].id
    }

    // MARK: Counter

    private func counterText(frames: [HallOfFameFrame]) -> String? {
        guard level == .photo, isLive || isClosingPhase, !frames.isEmpty else { return nil }
        let frame = scrollPosition.flatMap { id in frames.first { $0.id == id } } ?? frames[0]
        return HallOfFameModel.counterText(for: frame, total: frames.count)
    }
}
