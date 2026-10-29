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
                NavigationStack {
                    page.toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .tint(Theme.accent)
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
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

    /// The page itself, under the same glass header as the Alarm screen.
    private var page: some View {
        ZStack(alignment: .top) {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                Color.clear.frame(height: AlarmPageHeader.band)

                ZStack(alignment: .top) {
                    if sourceURL == nil {
                        sourcePicker
                            .transition(sourceTransition)
                    } else {
                        selector
                            .transition(selectorTransition)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }

            AlarmPageHeader(
                title: "your song",
                symbol: presentation == .pushed ? "chevron.left" : "xmark",
                label: presentation == .pushed ? "Back" : "Close"
            ) {
                stopPreview()
                dismiss()
            }
        }
        .animation(Theme.stateChange, value: errorMessage)
        .animation(Theme.stateChange, value: isPreparingSource)
        .animation(Theme.stateChange, value: libraryBlocked)
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
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("pick a track")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)

                Text("you choose 28 seconds of it. that is the most an alarm can play.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
                    Text("opening your track")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
                .accessibilityElement(children: .combine)
            }

            if let errorMessage {
                errorText(errorMessage)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    /// Denied or restricted: say so, offer the way out, never an empty list.
    private var libraryBlockedRow: some View {
        HStack(spacing: 10) {
            Text("music library access is off.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)

            Spacer(minLength: 8)

            Button("open settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceMuted, in: .rect(cornerRadius: 14))
    }

    private func errorText(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .fixedSize(horizontal: false, vertical: true)
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 40, height: 40)
                    .background(Theme.surfaceMuted, in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .buttonStyle(AlarmGlassCardButtonStyle(verticalPadding: 13))
    }

    // MARK: - Selecting

    private var selector: some View {
        VStack(spacing: 0) {
            Text(sourceTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Text(rangeLabel)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .padding(.top, 10)
                .accessibilityLabel(accessibleRange)

            Text(lengthLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
                .padding(.top, 2)

            waveformStrip
                .padding(.top, 26)

            Text("drag to choose")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
                .padding(.top, 12)

            HStack(spacing: 12) {
                Button {
                    togglePreview()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isPreviewing ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .contentTransition(.symbolEffect(.replace))
                        Text(isPreviewing ? "stop" : "hear it")
                            .font(.system(size: 15, weight: .semibold))
                            .contentTransition(.opacity)
                    }
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .animation(Theme.stateChange, value: isPreviewing)
                }
                .buttonStyle(AlarmGlassCapsuleButtonStyle())
                .disabled(isLoadingWaveform)

                Button {
                    Task { await save() }
                } label: {
                    Text(isExporting ? "saving" : "use this")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .animation(Theme.stateChange, value: isExporting)
                }
                .buttonStyle(AlarmGlassCapsuleButtonStyle(role: .prominent))
                .disabled(isExporting || isLoadingWaveform)
                .opacity(isExporting || isLoadingWaveform ? 0.5 : 1)
            }
            .padding(.top, 26)

            honestNote
                .padding(.top, 18)

            if let errorMessage {
                errorText(errorMessage)
                    .padding(.top, 12)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
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

                Text("your song plays when you open the app. the system alarm rings first.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceMuted, in: .rect(cornerRadius: 14))
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

    private static let stripHeight: CGFloat = 112
    private static let barsHeight: CGFloat = 92

    private var waveformStrip: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let windowWidth = (width * 0.6).rounded()
            let windowMinX = ((width - windowWidth) / 2).rounded()
            let pointsPerSecond = windowWidth / CGFloat(max(window.clipLength, 0.5))
            let originX = windowMinX - CGFloat(start) * pointsPerSecond

            ZStack(alignment: .topLeading) {
                // The window: fixed, restrained, never moves.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.ink.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.ink.opacity(0.16), lineWidth: 1.5)
                    }
                    .frame(width: windowWidth, height: Self.stripHeight)
                    .offset(x: windowMinX)

                let shape = ScrollingWaveformShape(
                    peaks: peaks,
                    duration: trackDuration,
                    originX: originX,
                    pointsPerSecond: pointsPerSecond
                )

                shape
                    .fill(Theme.inkTertiary.opacity(0.45))
                    .frame(width: width, height: Self.barsHeight)
                    .offset(y: (Self.stripHeight - Self.barsHeight) / 2)

                shape
                    .fill(Theme.accent)
                    .frame(width: width, height: Self.barsHeight)
                    .mask(alignment: .topLeading) {
                        Rectangle()
                            .frame(width: windowWidth, height: Self.barsHeight)
                            .offset(x: windowMinX)
                    }
                    .offset(y: (Self.stripHeight - Self.barsHeight) / 2)

                if let preview, isPreviewing {
                    PreviewPlayhead(
                        player: preview,
                        windowStart: shownRange.lowerBound,
                        windowMinX: windowMinX,
                        pointsPerSecond: pointsPerSecond,
                        height: Self.stripHeight
                    )
                }

                if isLoadingWaveform {
                    ProgressView()
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

    private func handleFileImport(_ result: Result<[URL], Error>) {
        errorMessage = nil

        let source: URL
        switch result {
        case let .success(urls):
            guard let first = urls.first else { return }
            source = first
        case let .failure(error):
            if (error as? CocoaError)?.code == .userCancelled { return }
            errorMessage = SongTrimService.TrimError.fileInaccessible.errorDescription
            return
        }

        let title = source.deletingPathExtension().lastPathComponent
        isPreparingSource = true

        loadTask?.cancel()
        loadTask = Task {
            do {
                let cached = try await SongTrimService.copyIntoCache(from: source)
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

// MARK: - Preview playhead

/// A thin line inside the window showing where the preview is.
private struct PreviewPlayhead: View {
    let player: AVAudioPlayer
    let windowStart: Double
    let windowMinX: CGFloat
    let pointsPerSecond: CGFloat
    let height: CGFloat

    var body: some View {
        TimelineView(.animation) { _ in
            let elapsed = max(0, player.currentTime - windowStart)
            Capsule()
                .fill(Theme.ink)
                .frame(width: 2, height: height - 16)
                .offset(x: windowMinX + CGFloat(elapsed) * pointsPerSecond - 1, y: 8)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
