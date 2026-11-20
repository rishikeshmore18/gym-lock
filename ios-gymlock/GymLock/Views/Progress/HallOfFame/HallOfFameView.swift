import SwiftUI

/// The Hall of Fame: a full-screen film strip of every progress photo, with a
/// scripted entrance and exit, pinch between Photo / Day / Week / Month, and a
/// level capsule. The Progress tab presents it with the system animation off.
struct HallOfFameView: View {
    let store: ProgressPhotoStore
    /// The Progress Photos card in global coordinates: the page zooms back
    /// into it on close.
    var sourceFrame: CGRect = .zero
    /// Called after the close animation ends.
    let onClose: () -> Void
    @AppStorage(HeroCardStyle.storageKey) private var styleRaw = HeroCardStyle.default.rawValue
    /// Hall of Fame only film style; empty follows Home's card style.
    @AppStorage(HallOfFameSettings.styleKey) private var filmStyleRaw = ""
    @AppStorage(HallOfFameSettings.scrollHapticsKey) private var scrollHaptics = true

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
    /// The photo in the middle of the screen, reported by the strip.
    @State private var centerFrameID: String?
    /// Opening: hold on the oldest photo, then glide to the newest.
    @State private var glideTask: Task<Void, Never>?
    @State private var glideScheduled = false
    /// Drag to close: finger travel, film overscroll, and the zoom into the card.
    @State private var dismissDrag: CGSize = .zero
    @State private var pull: CGFloat = 0
    @State private var exitProgress: CGFloat = 0
    @State private var exitFrom: (drag: CGSize, pull: CGFloat)?
    @State private var isFilmTouching = false
    @State private var pastDismissThreshold = false
    @Namespace private var pillSpace

    private let allEvents: ReelEvents = [.reelLanded, .titleComplete, .revolution1, .revolution2, .revolution3, .stripSeated]

    private var style: HeroCardStyle {
        HeroCardStyle(rawValue: filmStyleRaw) ?? HeroCardStyle(rawValue: styleRaw) ?? .default
    }
    private var isDemo: Bool { store.photos.isEmpty }
    private var isLive: Bool { phase == .live }

    // MARK: Body

    var body: some View {
        let frames = realFrames()
        let sections = displaySections(frames, level: level)
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
                .modifier(HallOfFamePageZoom(
                    size: geo.size,
                    drag: exitFrom?.drag ?? dismissDrag,
                    pull: exitFrom?.pull ?? pull,
                    exit: exitProgress,
                    target: sourceFrame,
                    cornerRadius: ProgressCardMetrics.cornerRadius
                ))
                .opacity(configured ? fade : 0)
            }
            .ignoresSafeArea()
        }
        .onAppear { start() }
        .onChange(of: isLive) { _, live in
            if live { scheduleGlide() }
        }
        .onDisappear { glideTask?.cancel() }
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
                introLeader: max(introBox - size.height, 0),
                hapticsEnabled: scrollHaptics && isLive && !isClosing && !isCommitting,
                onCenterFrame: { centerFrameID = $0 },
                onUserInteract: {
                    cancelGlide()
                    isFilmTouching = true
                },
                onPull: { filmPulled($0, size: size) },
                onInteractionEnd: { filmReleased() }
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

            // Drag to close: from the title area, or from the left edge.
            if isLive, !isClosing {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: size.width, height: layout.stripTop)
                    .gesture(dismissGesture(size: size))
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: 22, height: size.height)
                    .gesture(dismissGesture(size: size))
            }

            GlassCircleButton(symbol: "xmark", label: "Close") { close(frames: frames) }
                .frame(width: 44, height: 44)
                .padding(.leading, 14)
                .padding(.top, max(safeTop - 3, 0))
                .opacity(chrome)
                .allowsHitTesting(isLive && !isClosing)

            settingsMenu(sections: sections, frames: frames)
                .frame(width: 44, height: 44)
                .padding(.trailing, 14)
                .padding(.top, max(safeTop - 3, 0))
                .frame(width: size.width, alignment: .trailing)
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

    // MARK: Film

    /// Real photos only. With none, the film is empty dated days, never the
    /// demo artwork: nothing here may imply a photo that was not taken.
    private func realFrames() -> [HallOfFameFrame] {
        guard !store.photos.isEmpty else { return [] }
        return HallOfFameModel.frames(photos: store.photos, installDate: store.installDate)
    }

    /// Shown oldest at the top, newest at the bottom.
    private func displaySections(_ frames: [HallOfFameFrame], level: HallOfFameLevel) -> [HallOfFameSection] {
        HallOfFameModel.sections(frames, level: level, installDate: store.installDate).reversed().map {
            HallOfFameSection(id: $0.id, title: $0.title, countText: $0.countText,
                              frames: $0.frames.reversed(), cells: $0.cells)
        }
    }

    /// The top and bottom of the film as scroll ids (a frame, or a day cell,
    /// which the strip maps to its row in Week and Month).
    private func endIDs(_ sections: [HallOfFameSection], level: HallOfFameLevel) -> (top: String?, bottom: String?) {
        let grid = level == .week || level == .month
        func ids(_ s: HallOfFameSection) -> [String] {
            let cells = s.cells.filter { !$0.isPadding }.map(\.id)
            if grid { return cells }
            return s.frames.isEmpty ? cells : s.frames.map(\.id)
        }
        return (sections.first.flatMap { ids($0).first }, sections.last.flatMap { ids($0).last })
    }

    /// Where the opening glide and "Jump to Latest" land: the newest photo,
    /// or today when there are none.
    private func latestID(_ frames: [HallOfFameFrame], _ sections: [HallOfFameSection]) -> String? {
        frames.first?.id ?? endIDs(sections, level: level).bottom
    }

    private func jump(to id: String?) {
        guard let id, isLive, !isClosing else { return }
        cancelGlide()
        HallOfFameHaptics.levelChanged()
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { scrollPosition = nil }
        Task { @MainActor in
            await Task.yield()
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .timingCurve(0.45, 0, 0.2, 1, duration: 0.9)) {
                scrollPosition = id
            }
        }
    }

    // MARK: Chrome

    /// The slider circle at the top right: jumps, film style, scroll haptics.
    @ViewBuilder
    private func settingsMenu(sections: [HallOfFameSection], frames: [HallOfFameFrame]) -> some View {
        let menu = Menu {
            Section {
                Button {
                    jump(to: latestID(frames, sections))
                } label: {
                    Label("Jump to Latest", systemImage: "arrow.down.to.line")
                }
                Button {
                    jump(to: endIDs(sections, level: level).top)
                } label: {
                    Label("Jump to Where It Started", systemImage: "arrow.up.to.line")
                }
            }
            Section {
                Picker(selection: $filmStyleRaw) {
                    Text("Match Home").tag("")
                    Text("Ridge").tag(HeroCardStyle.ridge.rawValue)
                    Text("Matrix").tag(HeroCardStyle.matrix.rawValue)
                } label: {
                    Label("Film Style", systemImage: "film")
                }
                .pickerStyle(.menu)
                Toggle(isOn: $scrollHaptics) {
                    Label("Scroll Haptics", systemImage: "water.waves")
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .accessibilityLabel("Film options")
        .onChange(of: scrollHaptics) { _, on in
            if on { HallOfFameHaptics.levelChanged() }
        }
        .onChange(of: filmStyleRaw) { _, _ in
            HallOfFameHaptics.levelChanged()
        }

        if #available(iOS 26.0, *) {
            menu
                .menuStyle(.button)
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            menu
                .menuStyle(.button)
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: .circle)
                .overlay { Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1) }
                .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        }
    }

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
        // Open on where it started: the oldest photo, which the glide then
        // leaves for the newest.
        let frames = realFrames()
        let sections = displaySections(frames, level: level)
        if let oldest = frames.last?.id ?? endIDs(sections, level: level).top {
            scrollPosition = oldest
            centerFrameID = oldest
        }
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

    // MARK: Opening glide

    /// Once the strip is live: one second on the oldest photo, then a smooth
    /// glide down to the newest. Any touch, pinch, tap or close cancels it.
    private func scheduleGlide() {
        guard !glideScheduled else { return }
        glideScheduled = true
        let frames = realFrames()
        let sections = displaySections(frames, level: level)
        let opening = frames.last?.id ?? endIDs(sections, level: level).top
        guard let target = latestID(frames, sections), target != opening else { return }
        let distance = max(frames.count, min(sections.count, 14))
        glideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, isLive, !isClosing, !isCommitting else { return }
            if reduceMotion {
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { scrollPosition = target }
            } else {
                // Longer films take a little longer, but never drag.
                let duration = min(0.9 + Double(distance) * 0.06, 2.0)
                withAnimation(.timingCurve(0.45, 0, 0.2, 1, duration: duration)) {
                    scrollPosition = target
                }
            }
            glideTask = nil
        }
    }

    private func cancelGlide() {
        glideTask?.cancel()
        glideTask = nil
    }

    /// Settles the strip exactly on `id` after a level change. Setting the
    /// same id twice is ignored by the scroll view, so it is cleared first;
    /// if the strip already sits there, nothing moves.
    private func reseat(_ id: String?) async {
        guard let id else { return }
        try? await Task.sleep(for: .milliseconds(420))
        guard !isClosing else { return }
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { scrollPosition = nil }
        await Task.yield()
        withAnimation(.snappy(duration: 0.25)) { scrollPosition = id }
    }

    // MARK: Close

    private func close(frames: [HallOfFameFrame]) {
        guard isLive, !isClosing else { return }
        cancelGlide()
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
        // The film collapses back to the newest day, and while it settles the
        // page starts zooming into the card, so the two read as one motion.
        let target = frames.first?.id ?? endIDs(displaySections(frames, level: .day), level: .day).bottom
        let needsScroll = scrollPosition != nil && scrollPosition != target
        let needsLevel = level != .day
        withAnimation(Theme.pageTurn) {
            if needsLevel { level = .day }
            scrollPosition = target
            pinchScale = 1
        }
        let wait: Duration = (needsScroll || needsLevel) ? .milliseconds(300) : .zero
        Task { @MainActor in
            try? await Task.sleep(for: wait)
            zoomOut()
        }
    }

    /// Zooms the page, from wherever the finger left it, into the card.
    private func zoomOut() {
        exitFrom = (dismissDrag, pull)
        withAnimation(.spring(duration: 0.44, bounce: 0)) {
            exitProgress = 1
        } completion: {
            finishClose()
        }
    }

    private func finishClose() {
        guard !didClose else { return }
        didClose = true
        onClose()
    }

    // MARK: Drag to close

    private func dismissGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                guard isLive, !isClosing, !pinchActive else { return }
                if dismissDrag == .zero {
                    cancelGlide()
                    Haptics.prepareSelection()
                }
                let t = value.translation
                // Upwards is resisted: the page only really leaves downwards or right.
                dismissDrag = CGSize(width: t.width, height: t.height > 0 ? t.height : t.height * 0.15)
                updateDismissThreshold(size: size)
            }
            .onEnded { value in
                guard isLive, !isClosing, dismissDrag != .zero else { return }
                let p = HallOfFamePageZoom.progress(drag: dismissDrag, pull: 0, size: size)
                let predicted = value.predictedEndTranslation
                if p > 0.22 || predicted.height > size.height * 0.4 || predicted.width > size.width * 0.55 {
                    closeFromDrag()
                } else {
                    pastDismissThreshold = false
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) { dismissDrag = .zero }
                }
            }
    }

    /// A light tick when the page crosses the point where letting go closes it.
    private func updateDismissThreshold(size: CGSize) {
        let p = HallOfFamePageZoom.progress(drag: dismissDrag, pull: pull, size: size)
        let past = p > 0.22 || pull > 80
        if past != pastDismissThreshold {
            pastDismissThreshold = past
            Haptics.selection()
        }
    }

    /// Pulling the film down past its top shrinks the page like a drag.
    private func filmPulled(_ value: CGFloat, size: CGSize) {
        guard !isClosing else { return }
        guard isLive else { pull = 0; return }
        pull = value
        if isFilmTouching { updateDismissThreshold(size: size) }
    }

    private func filmReleased() {
        isFilmTouching = false
        guard isLive, !isClosing else { return }
        if pull > 80 {
            closeFromDrag()
        } else {
            pastDismissThreshold = false
        }
    }

    private func closeFromDrag() {
        guard isLive, !isClosing else { return }
        cancelGlide()
        isClosing = true
        HallOfFameHaptics.close()
        zoomOut()
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
                    pinchAnchorID = centerFrameID
                    cancelGlide()
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
        commit(l, anchorID: centerFrameID)
    }

    private func commit(_ target: HallOfFameLevel, anchorID: String?) {
        cancelGlide()
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
            // Re-seat once the new layout has settled, then allow detents again.
            await reseat(id)
            try? await Task.sleep(for: .milliseconds(250))
            isCommitting = false
        }
    }

    private func openPhoto(_ frame: HallOfFameFrame) {
        guard isLive, !isClosing, level != .photo else { return }
        cancelGlide()
        isCommitting = true
        pinchAnchor = .center
        centerFrameID = frame.id
        withAnimation(Theme.pageTurn) {
            level = .photo
            pinchScale = 1
            scrollPosition = frame.id
        }
        HallOfFameHaptics.openPhoto()
        Task { @MainActor in
            // The tapped photo, and only it, ends up centred on screen.
            await reseat(frame.id)
            try? await Task.sleep(for: .milliseconds(250))
            isCommitting = false
        }
    }

    private func reachedStart() {
        guard !reachedStartFired, isLive else { return }
        reachedStartFired = true
        HallOfFameHaptics.reachedStart()
    }

    // MARK: Counter

    /// The counter follows the photo mid-screen, so it stays right when the
    /// strip is dragged rather than paged.
    private func counterText(frames: [HallOfFameFrame]) -> String? {
        guard level == .photo, isLive || isClosingPhase, !frames.isEmpty else { return nil }
        let frame = (centerFrameID ?? scrollPosition).flatMap { id in frames.first { $0.id == id } } ?? frames[0]
        return HallOfFameModel.counterText(for: frame, total: frames.count)
    }
}

/// Hall of Fame only preferences, kept apart from Home's card style so a
/// film choice here never changes the Home screen.
enum HallOfFameSettings {
    static let styleKey = "gymlock.hallOfFame.style"
    static let scrollHapticsKey = "gymlock.hallOfFame.scrollHaptics"
}
