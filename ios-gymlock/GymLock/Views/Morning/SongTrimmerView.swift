import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Picks a track and chooses the thirty seconds of it that will wake the user.
///
/// The window is a fixed length that slides, rather than two handles: the
/// thirty seconds is dictated by the platform, and a handle that cannot move
/// is worse than no handle at all. So there is exactly one thing to do here,
/// and it is done with one finger.
struct SongTrimmerView: View {
    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The track being trimmed, once one has been chosen.
    @State private var sourceURL: URL?
    @State private var sourceTitle = ""
    @State private var trackDuration: Double = 0
    @State private var peaks: [Double] = []
    @State private var isLoadingWaveform = false

    /// Where the window starts, in seconds.
    @State private var start: Double = 0
    /// Live drag offset in seconds, added to `start` while a finger is down.
    @State private var dragSeconds: Double = 0
    @State private var isDragging = false
    @State private var lastHapticBucket: Int?

    @State private var isImportingFile = false
    @State private var isPickingFromLibrary = false
    @State private var isExporting = false
    @State private var errorMessage: String?

    @State private var preview: AVAudioPlayer?
    @State private var previewLoop: Task<Void, Never>?
    @State private var isPreviewing = false

    /// Where the window sits right now, including the live drag.
    private var effectiveStart: Double {
        clampedStart(start + dragSeconds)
    }

    private var maximumStart: Double {
        max(0, trackDuration - SongTrimService.clipDuration)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                if sourceURL == nil {
                    sourcePicker
                } else {
                    trimmer
                }
            }
            .navigationTitle("your song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("cancel") {
                        stopPreview()
                        dismiss()
                    }
                    .foregroundStyle(Theme.inkSecondary)
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
        .onDisappear { stopPreview() }
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
                detail: "songs you own or downloaded"
            ) {
                Haptics.tap()
                isPickingFromLibrary = true
            }

            sourceButton(
                symbol: "folder",
                title: "from files",
                detail: "any audio file on this iPhone"
            ) {
                Haptics.tap()
                isImportingFile = true
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MorningCardStyle())
    }

    // MARK: - Trimming

    private var trimmer: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sourceTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                Text(windowSummary)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            waveformStrip

            HStack(spacing: 12) {
                Button {
                    togglePreview()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isPreviewing ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(isPreviewing ? "stop" : "hear it")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.surfaceMuted, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button {
                    Task { await save() }
                } label: {
                    Text(isExporting ? "saving" : "use this")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.accent, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isExporting || isLoadingWaveform)
                .opacity(isExporting || isLoadingWaveform ? 0.5 : 1)
            }

            honestNote

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
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

    private var windowSummary: String {
        let from = timeLabel(effectiveStart)
        let to = timeLabel(effectiveStart + SongTrimService.clipDuration)
        return "\(from) to \(to) · \(Int(SongTrimService.clipDuration)) seconds"
    }

    private func timeLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - The waveform

    private var waveformStrip: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = trackDuration > 0
                ? SongTrimService.clipDuration / trackDuration
                : 1
            let windowWidth = max(48, width * min(1, fraction))
            let travel = max(1, width - windowWidth)
            let progress = maximumStart > 0 ? effectiveStart / maximumStart : 0
            let offset = travel * progress

            ZStack(alignment: .leading) {
                WaveformShape(peaks: peaks)
                    .fill(Theme.border)
                    .frame(height: 96)

                WaveformShape(peaks: peaks)
                    .fill(Theme.accent)
                    .frame(width: windowWidth, height: 96)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: windowWidth)
                            .offset(x: offset)
                    }
                    .allowsHitTesting(false)

                // The window itself, which is the only thing that moves.
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.ink, lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.ink.opacity(0.06))
                    )
                    .frame(width: windowWidth, height: 104)
                    .offset(x: offset)
                    .overlay(alignment: .leading) {
                        grip.offset(x: offset + 8)
                    }
                    .overlay(alignment: .leading) {
                        grip.offset(x: offset + windowWidth - 14)
                    }
            }
            .frame(height: 112)
            .contentShape(.rect)
            .gesture(dragGesture(travel: travel))
            .accessibilityElement()
            .accessibilityLabel("clip start")
            .accessibilityValue(timeLabel(effectiveStart))
            .accessibilityAdjustableAction { direction in
                // Five-second steps, so a VoiceOver user can place the window
                // without a drag at all.
                let delta: Double = direction == .increment ? 5 : -5
                start = clampedStart(start + delta)
                Haptics.selection()
            }

            if isLoadingWaveform {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 112)
    }

    private var grip: some View {
        Capsule()
            .fill(Theme.ink)
            .frame(width: 6, height: 34)
    }

    private func dragGesture(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                stopPreview()

                // 1:1 tracking: the window is under the finger at every frame,
                // with no animation between the touch and the position.
                let perPoint = maximumStart / Double(max(travel, 1))
                let proposed = start + Double(value.translation.width) * perPoint

                dragSeconds = rubberBanded(proposed) - start
                tickIfCrossedFiveSeconds()
            }
            .onEnded { value in
                let perPoint = maximumStart / Double(max(travel, 1))

                // Flicks project where the gesture was going rather than
                // stopping dead under the finger.
                let projected = start
                    + Double(value.predictedEndTranslation.width) * perPoint
                let settled = clampedStart(projected)

                isDragging = false
                dragSeconds = 0
                lastHapticBucket = nil

                if reduceMotion {
                    // Same outcome, no travel.
                    withAnimation(.easeInOut(duration: 0.2)) { start = settled }
                } else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                        start = settled
                    }
                }
            }
    }

    private func clampedStart(_ value: Double) -> Double {
        min(max(0, value), maximumStart)
    }

    /// Past either end the window still follows the finger, but reluctantly.
    private func rubberBanded(_ value: Double) -> Double {
        if value < 0 { return value * 0.55 }
        if value > maximumStart { return maximumStart + (value - maximumStart) * 0.55 }
        return value
    }

    /// One tick per five seconds crossed. Per-frame haptics are a rattle.
    private func tickIfCrossedFiveSeconds() {
        let bucket = Int(effectiveStart / 5)
        guard bucket != lastHapticBucket else { return }
        lastHapticBucket = bucket
        Haptics.selection()
    }

    // MARK: - Loading

    private func handleFileImport(_ result: Result<[URL], Error>) {
        errorMessage = nil
        guard case let .success(urls) = result, let source = urls.first else { return }

        let didAccess = source.startAccessingSecurityScopedResource()
        defer { if didAccess { source.stopAccessingSecurityScopedResource() } }

        // Copied into the app's own storage straight away: the picker's URL is
        // security scoped and will not survive a relaunch.
        guard let cached = copyToCache(source) else {
            errorMessage = SongTrimService.TrimError.unreadable.errorDescription
            return
        }

        load(url: cached, title: source.deletingPathExtension().lastPathComponent)
    }

    private func handleLibraryPick(_ picked: MediaPicker.Picked?) {
        isPickingFromLibrary = false
        errorMessage = nil

        guard let picked else { return }

        // DRM-protected Apple Music tracks have no exportable asset at all.
        // Saying so now is the whole point: letting someone trim for thirty
        // seconds and then fail at export would be worse than not offering it.
        guard let url = picked.assetURL else {
            errorMessage = SongTrimService.TrimError.protectedTrack.errorDescription
            return
        }

        load(url: url, title: picked.title)
    }

    private func copyToCache(_ source: URL) -> URL? {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let caches else { return nil }

        let destination = caches.appendingPathComponent(
            "trim-source.\(source.pathExtension.isEmpty ? "m4a" : source.pathExtension)"
        )
        try? FileManager.default.removeItem(at: destination)

        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private func load(url: URL, title: String) {
        sourceURL = url
        sourceTitle = title.isEmpty ? "your track" : title
        isLoadingWaveform = true
        peaks = []

        // Reopening a previously trimmed song puts the window back where it
        // was left, rather than snapping to the beginning.
        start = store.profile.customAlarmTrimStart ?? 0

        Task {
            do {
                let duration = try await SongTrimService.duration(of: url)
                trackDuration = duration
                start = clampedStart(start)

                let rendered = try await SongTrimService.waveform(for: url)
                peaks = rendered
            } catch {
                errorMessage = (error as? SongTrimService.TrimError)?.errorDescription
                    ?? SongTrimService.TrimError.unreadable.errorDescription
            }
            isLoadingWaveform = false
        }
    }

    // MARK: - Preview

    /// Plays exactly the selected window, looping, so what the user hears is
    /// what will ring.
    private func togglePreview() {
        if isPreviewing {
            stopPreview()
            return
        }

        guard let sourceURL else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            let player = try AVAudioPlayer(contentsOf: sourceURL)
            player.currentTime = effectiveStart
            player.prepareToPlay()
            player.play()

            preview = player
            isPreviewing = true

            let windowStart = effectiveStart
            previewLoop = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(SongTrimService.clipDuration))
                    guard !Task.isCancelled, let preview, preview.isPlaying else { return }
                    preview.currentTime = windowStart
                }
            }
        } catch {
            errorMessage = SongTrimService.TrimError.unreadable.errorDescription
        }
    }

    private func stopPreview() {
        previewLoop?.cancel()
        previewLoop = nil
        preview?.stop()
        preview = nil
        isPreviewing = false
    }

    // MARK: - Saving

    private func save() async {
        guard let sourceURL else { return }

        stopPreview()
        isExporting = true
        errorMessage = nil

        do {
            let clip = try await SongTrimService.export(
                from: sourceURL,
                startSeconds: effectiveStart,
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

// MARK: - Waveform shape

/// The track's loudness, mirrored around the centre line.
///
/// A `Shape` rather than a stack of bars: this is drawn twice, over the whole
/// track, and a few hundred views would cost more than the picture is worth.
private struct WaveformShape: Shape {
    let peaks: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !peaks.isEmpty else { return path }

        let barWidth = rect.width / CGFloat(peaks.count)
        let centre = rect.midY

        for (index, peak) in peaks.enumerated() {
            let height = max(2, CGFloat(peak) * rect.height)
            let x = CGFloat(index) * barWidth

            path.addRoundedRect(
                in: CGRect(
                    x: x,
                    y: centre - height / 2,
                    width: max(1, barWidth * 0.6),
                    height: height
                ),
                cornerSize: CGSize(width: 0.5, height: 0.5)
            )
        }

        return path
    }
}
