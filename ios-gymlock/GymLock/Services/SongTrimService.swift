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
    static let clipDuration: Double = 28

    /// Stable file names, so a re-trim replaces rather than accumulating.
    static let clipFileName = "gymlock-custom-alarm.m4a"
    static let notificationClipFileName = "gymlock-custom-alarm.caf"

    nonisolated enum TrimError: LocalizedError {
        case protectedTrack
        case unreadable
        case exportFailed
        case noSoundsDirectory

        var errorDescription: String? {
            switch self {
            case .protectedTrack:
                "this track is protected. pick one you own, or a download."
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

    // MARK: - Reading

    /// A track's loudness over time, normalised to 0...1.
    ///
    /// Rendered once on a background task and never recomputed during a drag:
    /// decoding a four-minute song per frame would turn a smooth gesture into
    /// a slideshow.
    nonisolated static func waveform(
        for url: URL,
        buckets: Int = 220
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
            ]
        )
        reader.add(output)

        guard reader.startReading() else { throw TrimError.unreadable }

        var peaks: [Double] = []
        var runningPeak: Int16 = 0
        var samplesInBucket = 0

        // One bucket per pixel column, roughly. Peak rather than average,
        // because a waveform drawn from averages looks like a flat sausage and
        // gives the user nothing to aim at.
        let totalSamples = Int(
            (try? await asset.load(.duration).seconds) ?? 0
        ) * 44_100
        let samplesPerBucket = max(totalSamples / max(buckets, 1), 1)

        while let buffer = output.copyNextSampleBuffer() {
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
        let start = max(0, min(startSeconds, max(0, total - clipDuration)))
        let range = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: min(clipDuration, total), preferredTimescale: 600)
        )

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
