import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Picks a track and chooses the 28 seconds of it that will wake the user.
///
/// The window is fixed and the track moves under it, the way a story music
/// picker works: the length is dictated by the platform, so the only thing
/// left to choose is where, and that is done by dragging the song itself.
struct SongTrimmerView: View {
    /// How the page arrived, which decides its corner button: a back chevron
    /// when pushed from the Sound page, a close X when presented full screen.
    enum Presentation {
        case pushed
        case cover
    }

    var presentation: Presentation = .cover

    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The local, GymLock-owned copy of the track being trimmed.
    @State private var sourceURL: URL?
    @State private var sourceTitle = ""
    @State private var trackDuration: Double = 0
    @State private var peaks: [Double] = []
    @State private var isLoadingWaveform = false

    /// Where the window starts, in seconds. Moves 1:1 with the finger.
    @State private var start: Double = 0
    /// `start` when the current drag began; nil when no finger is down.
    @State private var dragBase: Double?
    @State private var settleTask: Task<Void, Never>?
    @State private var settleTarget: Double?

    @State private var isImportingFile = false
    @State private var isPickingFromLibrary = false
    @State private var isPreparingSource = false
    @State private var libraryBlocked = false
    @State private var loadTask: Task<Void, Never>?
    @State private var isExporting = false
    @State private var errorMessage: String?

    @State private var preview: AVAudioPlayer?
    @State private var previewLoop: Task<Void, Never>?
    @State private var previewWindowStart: Double?

    private var isPreviewing: Bool { preview != nil }

    private var window: SongTrimWindow {
        SongTrimWindow(duration: trackDuration)
    }

    var body: some View {
        Group {
            switch presentation {
            case .pushed:
                page
                    .toolbar(.hidden, for: .navigationBar)
                    .background {
                        InteractivePopEnabler()
                            .frame(width: 0, height: 0)
                            .accessibilityHidden(true)
                    }
            case .cover:
                // No colour-scheme override here, on purpose. A dark
                // preference set inside a cover leaks back to the presenter:
                // once dismissed, the Alarm pages' glass kept rendering dark
                // and every card went grey until the stack was rebuilt.
                NavigationStack {
                    page.toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .tint(Theme.ink)
        .sheet(isPresented: $isImportingFile) {
            AudioFilePicker { url in
                isImportingFile = false
                handleFileImport(url)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isPickingFromLibrary) {
            MediaPicker { picked in
                handleLibraryPick(picked)
            }
            .ignoresSafeArea()
        }
        .onChange(of: start) { _, newValue in
            // Whatever moved the window, the preview never keeps playing a
            // section that is no longer selected.
            if let previewWindowStart, abs(previewWindowStart - newValue) > 0.0001 {
                stopPreview()
            }
        }
        .onDisappear {
            stopPreview()
            settleTask?.cancel()
            loadTask?.cancel()
        }
    }

    /// The page itself: the app's light canvas and glass, with black as the
    /// only emphasis. Nothing on it is coloured.
    private var page: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                topBar

                ZStack {
                    if sourceURL == nil {
                        sourcePicker
                            .transition(sourceTransition)
                    } else {
                        selector
                            .transition(selectorTransition)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .animation(stepAnimation, value: sourceURL == nil)
        .animation(Theme.stateChange, value: errorMessage)
        .animation(Theme.stateChange, value: isPreparingSource)
        .animation(Theme.stateChange, value: libraryBlocked)
    }

    /// The app canvas with one soft pool of white behind the track, so the
    /// page has depth without a single tinted pixel.
    private var backdrop: some View {
        ZStack {
            Theme.canvas
            RadialGradient(
                colors: [Color.white.opacity(isPreviewing ? 1 : 0.8), Color.white.opacity(0)],
                center: UnitPoint(x: 0.5, y: 0.34),
                startRadius: 0,
                endRadius: 420
            )
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.7), value: isPreviewing)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// The same header as Sound and Haptics, so this reads as the next page
    /// of Alarm rather than a different app, with done on the right once
    /// there is a clip to keep.
    private var topBar: some View {
        ZStack {
            AlarmPageHeader(
                title: "your song",
                symbol: presentation == .pushed ? "chevron.left" : "xmark",
                label: presentation == .pushed ? "Back" : "Close"
            ) {
                stopPreview()
                dismiss()
            }

            HStack {
                Spacer(minLength: 0)
                if sourceURL != nil {
                    doneButton
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 4)
        }
        .frame(height: AlarmPageHeader.band)
    }

    @ViewBuilder
    private var doneButton: some View {
        let isBlocked = isExporting || isLoadingWaveform
        let label = ZStack {
            Text("done")
                .font(.system(size: 16, weight: .bold))
                .opacity(isExporting ? 0 : 1)
            if isExporting {
                ProgressView()
                    .tint(Color.white)
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 6)
        .frame(height: 36)
        .animation(Theme.stateChange, value: isExporting)

        Group {
            if #available(iOS 26.0, *) {
                Button {
                    Task { await save() }
                } label: {
                    label
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(Theme.ink)
            } else {
                Button {
                    Task { await save() }
                } label: {
                    label
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Theme.ink, in: .capsule)
                }
                .buttonStyle(TrimmerPressStyle())
            }
        }
        .disabled(isBlocked)
        .opacity(isLoadingWaveform ? 0.45 : 1)
        .accessibilityLabel(isExporting ? "Saving" : "Use this clip")
    }

    /// Under 300 ms either way. Reduce Motion: a plain crossfade.
    private var stepAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.3, bounce: 0)
    }

    private var sourceTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: 0.97, anchor: .top).combined(with: .opacity)
    }

    private var selectorTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .offset(y: 24).combined(with: .opacity),
                removal: .opacity
            )
    }

    // MARK: - Picking

    private var sourcePicker: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            Image(systemName: "music.note")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 112, height: 112)
                .background(Theme.ink, in: .rect(cornerRadius: 32, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
                .accessibilityHidden(true)

            Text("pick a track")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 28)

            Text("you choose 28 seconds of it. that is the most an alarm can play.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.horizontal, 24)

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                sourceButtons
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    /// Low on the screen, where the thumb already is.
    @ViewBuilder
    private var sourceButtons: some View {
            sourceButton(
                symbol: "music.note.list",
                title: "from my music",
                detail: "purchased or synced songs you own"
            ) {
                Haptics.tap()
                openLibrary()
            }
            .disabled(isPreparingSource)

            if libraryBlocked {
                libraryBlockedRow
                    .transition(.opacity)
            }

            sourceButton(
                symbol: "folder",
                title: "from files",
                detail: "any audio file on this iPhone"
            ) {
                Haptics.tap()
                errorMessage = nil
                isImportingFile = true
            }
            .disabled(isPreparingSource)

            if isPreparingSource {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.ink)
                    Text("opening your track")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .transition(.opacity)
                .accessibilityElement(children: .combine)
            }

            if let errorMessage {
                errorText(errorMessage)
            }
    }

    /// Denied or restricted: say so, offer the way out, never an empty list.
    private var libraryBlockedRow: some View {
        HStack(spacing: 10) {
            Text("music library access is off.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)

            Spacer(minLength: 8)

            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                Text("open settings")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Theme.ink, in: .capsule)
            }
            .buttonStyle(TrimmerPressStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trimmerGlass(in: .rect(cornerRadius: 20, style: .continuous), isInteractive: false)
    }

    /// Errors are said plainly in ink with a mark, not shouted in colour.
    private func errorText(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    private func sourceButton(
        symbol: String,
        title: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.ink, in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(.rect(cornerRadius: 24, style: .continuous))
            .trimmerGlass(in: .rect(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(TrimmerPressStyle())
    }

    // MARK: - Selecting

    /// The track up top as the subject, the controls low where the thumb
    /// is, and the waveform running edge to edge under a fixed black frame.
    private var selector: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            trackHero

            Spacer(minLength: 20)

            transportRow
                .padding(.horizontal, 20)

            waveformStrip
                .padding(.top, 20)

            Text("drag to choose")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
                .padding(.top, 14)

            VStack(spacing: 12) {
                honestNote

                if let errorMessage {
                    errorText(errorMessage)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .padding(.bottom, 12)
    }

    /// The song as the subject of the page: a black tile that pulses with
    /// the preview, its name, and the selected range set large.
    private var trackHero: some View {
        VStack(spacing: 0) {
            Image(systemName: "waveform")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Color.white)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isPreviewing && !reduceMotion)
                .frame(width: 128, height: 128)
                .background(Theme.ink, in: .rect(cornerRadius: 34, style: .continuous))
                .shadow(color: .black.opacity(isPreviewing ? 0.26 : 0.18), radius: isPreviewing ? 30 : 24, y: 12)
                .scaleEffect(isPreviewing && !reduceMotion ? 1.04 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7), value: isPreviewing)
                .accessibilityHidden(true)

            Text(sourceTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 28)
                .padding(.horizontal, 28)

            Text(rangeLabel)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 8)
                .padding(.horizontal, 20)
                .accessibilityLabel(accessibleRange)
        }
    }

    /// Clip length on the left, where the clip sits in the whole song in
    /// the middle, play on the right.
    private var transportRow: some View {
        HStack(spacing: 14) {
            Text("\(Int(window.clipLength.rounded(.down)))")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .overlay { Circle().strokeBorder(Theme.ink, lineWidth: 2) }
                .accessibilityLabel(lengthLabel)

            trackOverview

            Button {
                Haptics.tap()
                togglePreview()
            } label: {
                Image(systemName: isPreviewing ? "pause.fill" : "play.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color.white)
                    .contentTransition(.symbolEffect(.replace))
                    .offset(x: isPreviewing ? 0 : 1.5)
                    .frame(width: 52, height: 52)
                    .background(Theme.ink, in: .circle)
            }
            .buttonStyle(TrimmerPressStyle())
            .disabled(isLoadingWaveform)
            .accessibilityLabel(isPreviewing ? "Stop preview" : "Play selection")
        }
    }

    /// The whole song as a hairline, the selected 28 seconds as a black
    /// segment on it, so a long track never loses its sense of place.
    private var trackOverview: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let total = max(trackDuration, 0.001)
            let span = min(width, max(6, CGFloat(window.clipLength / total) * width))
            let lower = min(width - span, max(0, CGFloat(shownRange.lowerBound / total) * width))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.ink.opacity(0.2))
                    .frame(height: 3)
                Capsule()
                    .fill(Theme.ink)
                    .frame(width: span, height: 3)
                    .offset(x: lower)
            }
            .frame(width: width, height: geometry.size.height, alignment: .leading)
        }
        .frame(height: 44)
        .accessibilityHidden(true)
    }

    /// What the user is actually told, which is exactly what happens.
    ///
    /// AlarmKit rings with the system sound, the stop intent brings the app
    /// forward, and the chosen track starts then. Implying it plays from the
    /// Lock Screen would be a lie the user discovers at 6:30 in the morning.
    @ViewBuilder
    private var honestNote: some View {
        if coordinator.alarmCapability == .systemAlarm {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)

                Text("your selected clip plays with the system alarm.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .trimmerGlass(in: .rect(cornerRadius: 18, style: .continuous), isInteractive: false)
        }
    }

    /// The selection, clamped: rubber banding past the ends never shows a
    /// time the clip cannot have.
    private var shownRange: ClosedRange<Double> {
        window.range(startingAt: start)
    }

    private var rangeLabel: String {
        "\(SongTrimWindow.timeLabel(shownRange.lowerBound)) – \(SongTrimWindow.timeLabel(shownRange.upperBound))"
    }

    private var accessibleRange: String {
        "\(SongTrimWindow.timeLabel(shownRange.lowerBound)) to \(SongTrimWindow.timeLabel(shownRange.upperBound))"
    }

    private var lengthLabel: String {
        let seconds = Int(window.clipLength.rounded(.down))
        return seconds == 1 ? "1 second" : "\(seconds) seconds"
    }

    // MARK: - The waveform

    private static let stripHeight: CGFloat = 96
    private static let barsHeight: CGFloat = 68
    private static let windowRadius: CGFloat = 14

    private var waveformStrip: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let windowWidth = (width * 0.6).rounded()
            let windowMinX = ((width - windowWidth) / 2).rounded()
            let pointsPerSecond = windowWidth / CGFloat(max(window.clipLength, 0.5))
            let originX = windowMinX - CGFloat(start) * pointsPerSecond

            ZStack(alignment: .topLeading) {
                let shape = ScrollingWaveformShape(
                    peaks: peaks,
                    duration: trackDuration,
                    originX: originX,
                    pointsPerSecond: pointsPerSecond
                )

                // Outside the window: quiet grey. Inside: full ink.
                shape
                    .fill(Theme.ink.opacity(0.16))
                    .frame(width: width, height: Self.barsHeight)
                    .offset(y: (Self.stripHeight - Self.barsHeight) / 2)

                shape
                    .fill(Theme.ink)
                    .frame(width: width, height: Self.barsHeight)
                    .mask(alignment: .topLeading) {
                        Rectangle()
                            .frame(width: windowWidth, height: Self.barsHeight)
                            .offset(x: windowMinX)
                    }
                    .offset(y: (Self.stripHeight - Self.barsHeight) / 2)

                if let preview, isPreviewing {
                    PreviewSweep(
                        player: preview,
                        bars: shape,
                        width: width,
                        windowStart: shownRange.lowerBound,
                        windowMinX: windowMinX,
                        windowWidth: windowWidth,
                        pointsPerSecond: pointsPerSecond,
                        stripHeight: Self.stripHeight,
                        barsHeight: Self.barsHeight,
                        cornerRadius: Self.windowRadius
                    )
                    .transition(.opacity)
                }

                // The window: fixed, a bold black frame, never moves.
                RoundedRectangle(cornerRadius: Self.windowRadius, style: .continuous)
                    .strokeBorder(Theme.ink, lineWidth: 3)
                    .frame(width: windowWidth, height: Self.stripHeight)
                    .offset(x: windowMinX)
                    .allowsHitTesting(false)

                if isLoadingWaveform {
                    ProgressView()
                        .tint(Theme.ink)
                        .frame(width: width, height: Self.stripHeight)
                }
            }
            .frame(width: width, height: Self.stripHeight, alignment: .topLeading)
            .clipped()
            .contentShape(.rect)
            .gesture(dragGesture(pointsPerSecond: pointsPerSecond))
            .accessibilityElement()
            .accessibilityLabel("clip start")
            .accessibilityValue(SongTrimWindow.timeLabel(shownRange.lowerBound))
            .accessibilityHint("swipe up or down to move by five seconds")
            .accessibilityAdjustableAction { direction in
                finishSettle()
                stopPreview()
                let delta: Double = direction == .increment ? 5 : -5
                start = window.clamp(start + delta)
                Haptics.selection()
            }
        }
        .frame(height: Self.stripHeight)
    }

    /// The song follows the finger 1:1; the window never moves. A new touch
    /// catches a gliding track exactly where it is.
    private func dragGesture(pointsPerSecond: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragBase == nil {
                    settleTask?.cancel()
                    settleTask = nil
                    settleTarget = nil
                    stopPreview()
                    dragBase = start
                }
                start = window.start(
                    dragBase: dragBase ?? start,
                    translation: value.translation.width,
                    pointsPerSecond: pointsPerSecond
                )
            }
            .onEnded { value in
                let base = dragBase ?? start
                dragBase = nil

                let projected = window.start(
                    dragBase: base,
                    translation: value.predictedEndTranslation.width,
                    pointsPerSecond: pointsPerSecond
                )
                let settle = window.settle(
                    current: start,
                    projected: projected,
                    reduceMotion: reduceMotion
                )

                if settle.animated {
                    glide(to: settle.target)
                } else {
                    start = settle.target
                }
            }
    }

    /// Exponential decay toward the projected resting point. Driven by hand
    /// rather than `withAnimation`, so `start` is always the true position
    /// and the next touch can take over from it mid-flight.
    private func glide(to target: Double) {
        settleTask?.cancel()
        settleTarget = target

        settleTask = Task { @MainActor in
            let timeConstant = 0.14
            var last = ContinuousClock.now

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(8))
                guard !Task.isCancelled else { return }

                let now = ContinuousClock.now
                let elapsed = now - last
                last = now
                let seconds = Double(elapsed.components.seconds)
                    + Double(elapsed.components.attoseconds) / 1e18

                let next = target + (start - target) * exp(-seconds / timeConstant)
                if abs(next - target) < 0.005 {
                    start = target
                    break
                }
                start = next
            }

            settleTarget = nil
            settleTask = nil
        }
    }

    /// Lands any glide immediately, so preview and export use the resting point.
    private func finishSettle() {
        guard let settleTarget else { return }
        settleTask?.cancel()
        settleTask = nil
        start = settleTarget
        self.settleTarget = nil
    }

    // MARK: - Loading

    private func handleFileImport(_ picked: URL?) {
        errorMessage = nil
        guard let source = picked else { return }

        let title = source.deletingPathExtension().lastPathComponent
        isPreparingSource = true

        loadTask?.cancel()
        loadTask = Task {
            do {
                let cached = try await SongTrimService.copyIntoCache(from: source)
                // The picker's own copy sits in our tmp; ours replaces it.
                try? FileManager.default.removeItem(at: source)
                let duration = try await SongTrimService.validatedDuration(
                    of: cached,
                    failure: .unsupportedFormat
                )
                guard !Task.isCancelled else { return }
                isPreparingSource = false
                present(url: cached, title: title, duration: duration)
            } catch {
                guard !Task.isCancelled else { return }
                isPreparingSource = false
                errorMessage = (error as? SongTrimService.TrimError)?.errorDescription
                    ?? SongTrimService.TrimError.fileInaccessible.errorDescription
            }
        }
    }

    /// Checks library access before anything is shown.
    private func openLibrary() {
        errorMessage = nil

        switch MusicLibraryAccess.decision(for: MusicLibraryAccess.currentStatus) {
        case .present:
            libraryBlocked = false
            isPickingFromLibrary = true
        case .blocked:
            libraryBlocked = true
        case .request:
            Task {
                let status = await MusicLibraryAccess.requestAuthorization()
                if MusicLibraryAccess.decision(for: status) == .present {
                    libraryBlocked = false
                    isPickingFromLibrary = true
                } else {
                    libraryBlocked = true
                }
            }
        }
    }

    private func handleLibraryPick(_ picked: MediaPicker.Picked?) {
        isPickingFromLibrary = false
        errorMessage = nil

        guard let picked else { return }

        // No asset URL means DRM: say so now, not after the user has chosen.
        guard let url = MediaPicker.trimmableURL(for: picked) else {
            errorMessage = SongTrimService.TrimError.protectedTrack.errorDescription
            return
        }

        isPreparingSource = true
        loadTask?.cancel()
        loadTask = Task {
            do {
                let duration = try await SongTrimService.validatedDuration(
                    of: url,
                    failure: .protectedTrack
                )
                guard !Task.isCancelled else { return }
                isPreparingSource = false
                present(url: url, title: picked.title, duration: duration)
            } catch {
                guard !Task.isCancelled else { return }
                isPreparingSource = false
                errorMessage = SongTrimService.TrimError.protectedTrack.errorDescription
            }
        }
    }

    /// Moves straight to the selector, then draws the waveform into it.
    private func present(url: URL, title: String, duration: Double) {
        stopPreview()
        settleTask?.cancel()
        settleTask = nil
        settleTarget = nil
        dragBase = nil

        sourceTitle = title.isEmpty ? "your track" : title
        trackDuration = duration
        peaks = []
        isLoadingWaveform = true

        // Reopening a previously trimmed song puts the window back where it
        // was left, rather than snapping to the beginning.
        start = SongTrimWindow(duration: duration).clamp(store.profile.customAlarmTrimStart ?? 0)

        withAnimation(stepAnimation) {
            sourceURL = url
        }

        loadTask = Task {
            do {
                let rendered = try await SongTrimService.waveform(
                    for: url,
                    buckets: SongTrimWindow.waveformBuckets(forDuration: duration)
                )
                guard !Task.isCancelled else { return }
                peaks = rendered
                isLoadingWaveform = false
            } catch {
                guard !Task.isCancelled else { return }
                isLoadingWaveform = false
                returnToSources(with: .unsupportedFormat)
            }
        }
    }

    private func returnToSources(with error: SongTrimService.TrimError) {
        stopPreview()
        withAnimation(stepAnimation) {
            sourceURL = nil
        }
        errorMessage = error.errorDescription
    }

    // MARK: - Preview

    /// Plays exactly the selected window, looping at its end, so what the
    /// user hears is what will ring.
    private func togglePreview() {
        if isPreviewing {
            stopPreview()
            return
        }

        guard let sourceURL else { return }
        finishSettle()

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            let player = try AVAudioPlayer(contentsOf: sourceURL)
            let selected = start
            let currentWindow = window
            player.currentTime = currentWindow.previewStart(for: selected)
            player.prepareToPlay()
            player.play()

            preview = player
            previewWindowStart = selected
            errorMessage = nil

            previewLoop?.cancel()
            previewLoop = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled, let preview, preview === player else { return }

                    if let restart = currentWindow.previewRestart(
                        currentTime: player.currentTime,
                        isPlaying: player.isPlaying,
                        start: selected
                    ) {
                        player.currentTime = restart
                        if !player.isPlaying { player.play() }
                    }
                }
            }
        } catch {
            stopPreview()
            errorMessage = SongTrimService.TrimError.unreadable.errorDescription
        }
    }

    private func stopPreview() {
        previewLoop?.cancel()
        previewLoop = nil
        preview?.stop()
        preview = nil
        previewWindowStart = nil
    }

    // MARK: - Saving

    private func save() async {
        guard let sourceURL, !isExporting else { return }

        finishSettle()
        stopPreview()
        isExporting = true
        errorMessage = nil

        do {
            let clip = try await SongTrimService.export(
                from: sourceURL,
                startSeconds: window.clamp(start),
                title: sourceTitle
            )

            // Remembered so a missing file later falls back to a sound the
            // user actually chose, rather than to a generic default.
            if store.profile.alarmSound != .ownSong {
                store.profile.previousBundledSound = store.profile.alarmSound
            }

            store.profile.customAlarmSoundFile = clip.fileName
            store.profile.customAlarmSoundTitle = clip.title
            store.profile.customAlarmTrimStart = clip.startSeconds
            store.profile.alarmSound = .ownSong

            // The OS is holding the old sound until this runs.
            await coordinator.syncAlarms()

            Haptics.commit()
            isExporting = false
            dismiss()
        } catch {
            errorMessage = (error as? SongTrimService.TrimError)?.errorDescription
                ?? SongTrimService.TrimError.exportFailed.errorDescription
            isExporting = false
        }
    }
}

// MARK: - Preview sweep

/// While the clip plays, the window fills with ink from its left edge to
/// the playhead and the bars it has passed turn white, the way story music
/// pickers show progress, in black and white.
private struct PreviewSweep: View {
    let player: AVAudioPlayer
    let bars: ScrollingWaveformShape
    let width: CGFloat
    let windowStart: Double
    let windowMinX: CGFloat
    let windowWidth: CGFloat
    let pointsPerSecond: CGFloat
    let stripHeight: CGFloat
    let barsHeight: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        TimelineView(.animation) { _ in
            let elapsed = max(0, player.currentTime - windowStart)
            let filled = min(windowWidth, max(0, CGFloat(elapsed) * pointsPerSecond))

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Theme.ink)
                    .frame(width: filled, height: stripHeight)
                    .offset(x: windowMinX)

                bars
                    .fill(Color.white)
                    .frame(width: width, height: barsHeight)
                    .mask(alignment: .topLeading) {
                        Rectangle()
                            .frame(width: filled, height: barsHeight)
                            .offset(x: windowMinX)
                    }
                    .offset(y: (stripHeight - barsHeight) / 2)
            }
            .frame(width: width, height: stripHeight, alignment: .topLeading)
            .mask(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .frame(width: windowWidth, height: stripHeight)
                    .offset(x: windowMinX)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Light glass

/// The Alarm pages' glass on the light canvas: clear glass with a soft lift
/// on iOS 26, white material below, opaque white under Reduce Transparency.
private struct TrimmerGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    var isInteractive = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Theme.surface, in: shape)
                .overlay { shape.strokeBorder(Theme.border, lineWidth: 1) }
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(isInteractive ? .regular.interactive() : .regular, in: shape)
                .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(Color.white.opacity(0.6), in: shape)
                .overlay { shape.strokeBorder(Color.white.opacity(0.8), lineWidth: 1) }
                .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
        }
    }
}

private extension View {
    func trimmerGlass<S: InsettableShape>(in shape: S, isInteractive: Bool = true) -> some View {
        modifier(TrimmerGlass(shape: shape, isInteractive: isInteractive))
    }
}

// MARK: - Press feedback

/// Gives under the finger; a plain fade under Reduce Motion.
private struct TrimmerPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Waveform shape

/// The track's loudness at a fixed time scale, positioned so `originX` is
/// 0:00. Only bars inside the visible rect are added to the path, so a long
/// track costs no more per frame than a short one.
private struct ScrollingWaveformShape: Shape {
    let peaks: [Double]
    let duration: Double
    let originX: CGFloat
    let pointsPerSecond: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !peaks.isEmpty, duration > 0, pointsPerSecond > 0 else { return path }

        let count = peaks.count
        let slot = CGFloat(duration / Double(count)) * pointsPerSecond
        guard slot > 0 else { return path }

        let barWidth = max(1.5, slot * 0.55)
        let centre = rect.midY

        let first = max(0, Int(floor((rect.minX - originX) / slot)) - 1)
        let last = min(count - 1, Int(ceil((rect.maxX - originX) / slot)) + 1)
        guard first <= last else { return path }

        for index in first...last {
            let height = max(3, CGFloat(peaks[index]) * rect.height)
            let x = originX + CGFloat(index) * slot
            path.addRoundedRect(
                in: CGRect(x: x, y: centre - height / 2, width: barWidth, height: height),
                cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
            )
        }

        return path
    }
}
