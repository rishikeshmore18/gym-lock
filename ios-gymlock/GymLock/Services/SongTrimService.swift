import AVFoundation
import Foundation

/// Reads a track's shape and cuts the thirty seconds that will wake the user.
///
/// Split out of the view because all three jobs here are slow, failable and
/// entirely untangled from SwiftUI: decoding a waveform, exporting a clip, and
/// producing the second copy of that clip the notification system needs.
enum SongTrimService {
    /// How long the exported clip is.
    ///
    /// Not a preference. Notification sounds are hard-capped at 30 seconds by
    /// the system, and offering a handle that cannot move is worse than
    /// offering none, so the window is fixed and only its position is chosen.
    nonisolated static let clipDuration: Double = 28

    /// Stable file names, so a re-trim replaces rather than accumulating.
    nonisolated static let clipFileName = "gymlock-custom-alarm.m4a"
    nonisolated static let notificationClipFileName = "gymlock-custom-alarm.caf"

    nonisolated enum TrimError: LocalizedError, Equatable {
        case protectedTrack
        case unreadable
        case exportFailed
        case noSoundsDirectory
        /// The file picker handed over a URL that could not be read or copied.
        case fileInaccessible
        /// The copy succeeded but AVFoundation cannot decode it as audio.
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .protectedTrack:
                "this song can't be trimmed. choose a purchased or synced song, or use Files."
            case .fileInaccessible:
                "couldn't open that audio file. try another one?"
            case .unsupportedFormat:
                "that audio format isn't supported. try another file?"
            case .unreadable:
                "couldn't read that track. try another one?"
            case .exportFailed:
                "couldn't save that clip. try again?"
            case .noSoundsDirectory:
                "couldn't save that clip on this iPhone."
            }
        }
    }

    nonisolated struct Clip: Sendable {
        /// File name only, never a path: the container moves between launches.
        var fileName: String
        var title: String
        var startSeconds: Double
    }

    // MARK: - Importing

    /// Where imported Files sources live. One file at a time, replaced on
    /// every import, never the exported alarm clip.
    nonisolated static var importCacheDirectory: URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("SongTrimSource", isDirectory: true)
    }

    /// Copies a Files-picker URL into GymLock's own cache, off the main thread.
    ///
    /// The order is the whole fix: open the security scope, ask
    /// `NSFileCoordinator` for a coordinated read (which makes iCloud Drive and
    /// other providers materialise the file first), copy inside that block,
    /// then close the scope. Everything after this works on the local copy.
    nonisolated static func copyIntoCache(
        from source: URL,
        cacheDirectory: URL? = nil,
        access: @escaping @Sendable (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
        release: @escaping @Sendable (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try copyIntoCacheSynchronously(
                from: source,
                cacheDirectory: cacheDirectory,
                access: access,
                release: release
            )
        }.value
    }

    nonisolated private static func copyIntoCacheSynchronously(
        from source: URL,
        cacheDirectory: URL?,
        access: (URL) -> Bool,
        release: (URL) -> Void
    ) throws -> URL {
        let usesDefaultDirectory = cacheDirectory == nil
        guard let directory = cacheDirectory ?? importCacheDirectory else {
            throw TrimError.fileInaccessible
        }

        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw TrimError.fileInaccessible
        }

        let destination = directory.appendingPathComponent(
            "trim-source-\(UUID().uuidString).\(cachedExtension(for: source))"
        )

        let didAccess = access(source)
        defer { if didAccess { release(source) } }

        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: source,
            options: [],
            error: &coordinationError
        ) { readableURL in
            do {
                try manager.copyItem(at: readableURL, to: destination)
            } catch {
                copyError = error
            }
        }

        let size = (try? manager.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?
            .intValue ?? 0
        guard coordinationError == nil, copyError == nil, size > 0 else {
            try? manager.removeItem(at: destination)
            throw TrimError.fileInaccessible
        }

        // Only once the new copy exists: the previous source goes, so the
        // cache never holds more than one song.
        if let existing = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) {
            for file in existing where file.lastPathComponent != destination.lastPathComponent {
                try? manager.removeItem(at: file)
            }
        }

        // The old importer wrote `trim-source.<ext>` straight into Caches.
        if usesDefaultDirectory,
           let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let legacy = try? manager.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil) {
            for file in legacy where file.lastPathComponent.hasPrefix("trim-source.") {
                try? manager.removeItem(at: file)
            }
        }

        return destination
    }

    /// The original extension, lowercased, so AVFoundation can still sniff
    /// the container. Anything odd falls back to m4a.
    nonisolated static func cachedExtension(for source: URL) -> String {
        let ext = source.pathExtension.lowercased()
        let isSafe = !ext.isEmpty
            && ext.count <= 5
            && ext.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return isSafe ? ext : "m4a"
    }

    /// Proves a local file is decodable audio before the selector appears.
    /// Returns its duration.
    nonisolated static func validatedDuration(
        of url: URL,
        failure: TrimError = .unsupportedFormat
    ) async throws -> Double {
        do {
            let asset = AVURLAsset(url: url)
            guard try await asset.load(.isReadable) else { throw failure }
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard !tracks.isEmpty else { throw failure }
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0 else { throw failure }
            return duration
        } catch {
            throw failure
        }
    }

    // MARK: - Reading

    /// The rate the waveform is decoded at. Fixed and mono, so every bucket
    /// covers the same slice of time whatever the source's own format is.
    nonisolated static let waveformSampleRate: Double = 22_050

    /// A track's loudness over time, normalised to 0...1.
    ///
    /// Decoded once on a background task and never recomputed during a drag.
    /// Bucket `i` covers `i * duration / count` onwards.
    nonisolated static func waveform(
        for url: URL,
        buckets: Int = 220
    ) async throws -> [Double] {
        try await Task.detached(priority: .userInitiated) {
            try await decodeWaveform(for: url, buckets: buckets)
        }.value
    }

    nonisolated private static func decodeWaveform(
        for url: URL,
        buckets: Int
    ) async throws -> [Double] {
        let asset = AVURLAsset(url: url)

        guard try await asset.load(.isReadable) else { throw TrimError.unreadable }
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw TrimError.unreadable
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVSampleRateKey: waveformSampleRate,
                AVNumberOfChannelsKey: 1,
            ]
        )
        reader.add(output)

        guard reader.startReading() else { throw TrimError.unreadable }

        var peaks: [Double] = []
        peaks.reserveCapacity(max(buckets, 1) + 1)
        var runningPeak: Int16 = 0
        var samplesInBucket = 0

        // Peak rather than average, because a waveform drawn from averages
        // looks like a flat sausage and gives the user nothing to aim at.
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        let totalSamples = Int((seconds.isFinite ? seconds : 0) * waveformSampleRate)
        let samplesPerBucket = max(totalSamples / max(buckets, 1), 1)

        while let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                throw CancellationError()
            }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }

            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)
            data.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress else { return }
                CMBlockBufferCopyDataBytes(
                    blockBuffer,
                    atOffset: 0,
                    dataLength: length,
                    destination: base
                )
            }

            data.withUnsafeBytes { raw in
                let samples = raw.bindMemory(to: Int16.self)
                for sample in samples {
                    let magnitude = Int16(clamping: abs(Int(sample)))
                    if magnitude > runningPeak { runningPeak = magnitude }
                    samplesInBucket += 1

                    if samplesInBucket >= samplesPerBucket {
                        peaks.append(Double(runningPeak) / Double(Int16.max))
                        runningPeak = 0
                        samplesInBucket = 0
                    }
                }
            }

            CMSampleBufferInvalidate(buffer)
        }

        if samplesInBucket > 0 {
            peaks.append(Double(runningPeak) / Double(Int16.max))
        }

        guard !peaks.isEmpty else { throw TrimError.unreadable }

        // Normalised against the track's own peak, so a quietly mastered song
        // still draws as a waveform rather than a flat line.
        let ceiling = peaks.max() ?? 1
        guard ceiling > 0 else { return peaks }
        return peaks.map { min(1, $0 / ceiling) }
    }

    nonisolated static func duration(of url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw TrimError.unreadable }
        return duration
    }

    // MARK: - Exporting

    /// Cuts the chosen window and writes both copies the app needs.
    ///
    /// Two files, one clip: `AVAudioPlayer` plays the m4a, and the notification
    /// system gets an IMA4 caf because it cannot decode anything else. Writing
    /// them together is what stops the two paths drifting apart.
    nonisolated static func export(
        from url: URL,
        startSeconds: Double,
        title: String
    ) async throws -> Clip {
        let asset = AVURLAsset(url: url)

        guard try await asset.load(.isExportable) else { throw TrimError.protectedTrack }

        guard let directory = await AlarmTrackResolver.ensureSoundsDirectory() else {
            throw TrimError.noSoundsDirectory
        }

        let destination = directory.appendingPathComponent(clipFileName)
        let notificationDestination = directory.appendingPathComponent(notificationClipFileName)

        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.removeItem(at: notificationDestination)

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw TrimError.exportFailed
        }

        let total = try await asset.load(.duration).seconds
        let range = exportTimeRange(startSeconds: startSeconds, duration: total)
        let start = range.start.seconds

        // `timeRange` is a property, not a parameter: the async `export(to:as:)`
        // takes only the destination, so the trim has to be configured first.
        session.timeRange = range

        if #available(iOS 18.0, *) {
            try await session.export(to: destination, as: .m4a)
        } else {
            session.outputURL = destination
            session.outputFileType = .m4a
            await session.export()
            guard session.status == .completed else { throw TrimError.exportFailed }
        }

        // Best effort: if the caf cannot be written the alarm still rings, the
        // notification just falls back to a bundled tone rather than silence.
        try? await writeNotificationCopy(from: destination, to: notificationDestination)

        return Clip(fileName: clipFileName, title: title, startSeconds: start)
    }

    /// The exact slice `export` cuts: the selector's window, clamped.
    nonisolated static func exportTimeRange(startSeconds: Double, duration: Double) -> CMTimeRange {
        let window = SongTrimWindow(duration: duration)
        let start = window.clamp(startSeconds)
        return CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: window.clipLength, preferredTimescale: 600)
        )
    }

    /// The notification system's copy: IMA4 in a caf, because Linear PCM, IMA4,
    /// µLaw and aLaw are the only formats it will play.
    nonisolated private static func writeNotificationCopy(
        from source: URL,
        to destination: URL
    ) async throws {
        // `AVAssetExportSession` has no preset that writes into a caf, so the
        // rewrap goes through a reader/writer pair instead.
        try await encodeCAF(from: AVURLAsset(url: source), to: destination)
    }

    /// Decodes to 16-bit PCM and rewraps as a caf.
    ///
    /// Linear PCM rather than IMA4: it is on the system's accepted list, and
    /// `AVAssetWriter` will produce it without a codec dance. Twenty-eight
    /// seconds of mono at 22.05 kHz is about 1.2 MB, which is acceptable for
    /// a file written once.
    nonisolated private static func encodeCAF(from asset: AVAsset, to destination: URL) async throws {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return }

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVSampleRateKey: 22_050,
                AVNumberOfChannelsKey: 1,
            ]
        )
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: destination, fileType: .caf)
        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVSampleRateKey: 22_050,
                AVNumberOfChannelsKey: 1,
            ]
        )
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        guard reader.startReading(), writer.startWriting() else { return }
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "gymlock.caf.export")

        await withCheckedContinuation { continuation in
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    guard let buffer = readerOutput.copyNextSampleBuffer() else {
                        writerInput.markAsFinished()
                        writer.finishWriting { continuation.resume() }
                        return
                    }
                    writerInput.append(buffer)
                    CMSampleBufferInvalidate(buffer)
                }
            }
        }
    }

    /// Removes both copies, for the debug step that proves the fallback rings.
    @discardableResult
    nonisolated static func deleteExportedClip() async -> Bool {
        guard let directory = await AlarmTrackResolver.soundsDirectory else { return false }
        let clip = directory.appendingPathComponent(clipFileName)
        let notification = directory.appendingPathComponent(notificationClipFileName)

        let existed = FileManager.default.fileExists(atPath: clip.path)
        try? FileManager.default.removeItem(at: clip)
        try? FileManager.default.removeItem(at: notification)
        return existed
    }
}

// MARK: - The selection window

/// The maths behind the fixed 28-second window: the window stays put and the
/// track moves under it, so every rule here is about where the track's time
/// sits relative to that window.
///
/// Pure and value-typed so the selector, the preview and the export all agree
/// on one answer, and so the tests can prove it.
nonisolated struct SongTrimWindow: Sendable, Equatable {
    var duration: Double

    init(duration: Double) {
        self.duration = duration.isFinite ? max(0, duration) : 0
    }

    /// 28 seconds, or the whole track when it is shorter. Never padded.
    var clipLength: Double {
        min(SongTrimService.clipDuration, duration)
    }

    var maximumStart: Double {
        max(0, duration - SongTrimService.clipDuration)
    }

    func clamp(_ start: Double) -> Double {
        guard start.isFinite else { return 0 }
        return min(max(0, start), maximumStart)
    }

    func range(startingAt start: Double) -> ClosedRange<Double> {
        let from = clamp(start)
        return from...(from + clipLength)
    }

    /// Where the window starts while a finger is down. Dragging right pulls
    /// earlier audio under the window, exactly like a scrolled timeline.
    func start(dragBase: Double, translation: CGFloat, pointsPerSecond: CGFloat) -> Double {
        guard pointsPerSecond > 0 else { return clamp(dragBase) }
        return rubberBanded(dragBase - Double(translation / pointsPerSecond))
    }

    /// Past either end the track still follows the finger, but reluctantly.
    func rubberBanded(_ value: Double) -> Double {
        let limit = 4.0
        if value < 0 {
            let over = -value
            return -limit * (1 - 1 / (over * 0.35 / limit + 1))
        }
        if value > maximumStart {
            let over = value - maximumStart
            return maximumStart + limit * (1 - 1 / (over * 0.35 / limit + 1))
        }
        return value
    }

    struct Settle: Equatable {
        var target: Double
        var animated: Bool
    }

    /// Where a released drag comes to rest. The target is the same with or
    /// without Reduce Motion; only whether it glides there changes.
    func settle(current: Double, projected: Double, reduceMotion: Bool) -> Settle {
        let target = projected.isFinite ? clamp(projected) : clamp(current)
        return Settle(target: target, animated: !reduceMotion && abs(target - current) > 0.001)
    }

    /// Where preview playback begins for a selection.
    func previewStart(for start: Double) -> Double {
        clamp(start)
    }

    /// When the preview should jump back to the window start: at the end of
    /// the window, when the player ran off the end of a short track, or if it
    /// somehow sits outside the window. `nil` means keep playing.
    func previewRestart(currentTime: Double, isPlaying: Bool, start: Double) -> Double? {
        let window = range(startingAt: start)
        if !isPlaying { return window.lowerBound }
        if currentTime >= window.upperBound - 0.02 { return window.lowerBound }
        if currentTime < window.lowerBound - 0.25 { return window.lowerBound }
        return nil
    }

    /// Bars to decode for a track: about two per second, bounded so a short
    /// clip still has shape and a long mix never balloons.
    static func waveformBuckets(forDuration duration: Double) -> Int {
        guard duration.isFinite, duration > 0 else { return 60 }
        return min(max(Int(duration * 2.2), 60), 2_400)
    }

    static func timeLabel(_ seconds: Double) -> String {
        let total = Int((seconds.isFinite ? max(0, seconds) : 0).rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
