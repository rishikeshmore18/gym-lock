import AVFoundation
import Foundation
import MediaPlayer
import Testing
@testable import GymLock

/// The "your song" flow: importing a file reliably, the fixed 28-second
/// window, and the library rules that keep protected tracks out.
@Suite("Song trim flow")
@MainActor
struct SongTrimFlowTests {
    // MARK: - Fixtures

    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SongTrimFlowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Two seconds of a real AAC sine wave in an m4a container.
    private func makeM4A(in directory: URL, seconds: Double = 2) throws -> URL {
        let url = directory.appendingPathComponent("Morning Song.m4a")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try #require(buffer.floatChannelData?[0])
        for index in 0..<Int(frames) {
            samples[index] = Float(sin(Double(index) * 2 * .pi * 440 / 44_100) * 0.5)
        }

        do {
            let file = try AVAudioFile(
                forWriting: url,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                ]
            )
            try file.write(from: buffer)
        }
        return url
    }

    private func makeBytesFile(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data((0..<4_096).map { UInt8($0 % 251) }).write(to: url)
        return url
    }

    /// Thread-safe call counter for the injected security-scope closures.
    private final class ScopeLog: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [String] = []

        func record(_ event: String) {
            lock.lock(); events.append(event); lock.unlock()
        }

        var all: [String] {
            lock.lock(); defer { lock.unlock() }
            return events
        }
    }

    // MARK: - 1, 2. Copying

    @Test func copiesAnMP3KeepingItsExtension() async throws {
        let scratch = try scratchDirectory()
        let cache = scratch.appendingPathComponent("cache", isDirectory: true)
        let source = try makeBytesFile(named: "Wake Up.mp3", in: scratch)

        let copy = try await SongTrimService.copyIntoCache(
            from: source,
            cacheDirectory: cache,
            access: { _ in false },
            release: { _ in }
        )

        #expect(copy.pathExtension == "mp3")
        #expect(copy.deletingLastPathComponent().standardizedFileURL == cache.standardizedFileURL)
        #expect(copy.lastPathComponent.hasPrefix("trim-source-"))
        #expect(try Data(contentsOf: copy) == Data(contentsOf: source))
    }

    @Test func copiesAnM4AAndItDecodes() async throws {
        let scratch = try scratchDirectory()
        let cache = scratch.appendingPathComponent("cache", isDirectory: true)
        let source = try makeM4A(in: scratch)

        let copy = try await SongTrimService.copyIntoCache(
            from: source,
            cacheDirectory: cache,
            access: { _ in false },
            release: { _ in }
        )

        #expect(copy.pathExtension == "m4a")
        #expect(try Data(contentsOf: copy) == Data(contentsOf: source))
        let duration = try await SongTrimService.validatedDuration(of: copy)
        #expect(abs(duration - 2) < 0.2)
    }

    @Test func undecodableCopyIsReportedAsUnsupported() async throws {
        let scratch = try scratchDirectory()
        let garbage = try makeBytesFile(named: "noise.mp3", in: scratch)

        await #expect(throws: SongTrimService.TrimError.unsupportedFormat) {
            _ = try await SongTrimService.validatedDuration(of: garbage)
        }
    }

    @Test func missingSourceIsReportedAsInaccessible() async throws {
        let scratch = try scratchDirectory()
        let missing = scratch.appendingPathComponent("gone.m4a")

        await #expect(throws: SongTrimService.TrimError.fileInaccessible) {
            _ = try await SongTrimService.copyIntoCache(
                from: missing,
                cacheDirectory: scratch.appendingPathComponent("cache"),
                access: { _ in true },
                release: { _ in }
            )
        }
    }

    @Test func aNewImportReplacesThePreviousSource() async throws {
        let scratch = try scratchDirectory()
        let cache = scratch.appendingPathComponent("cache", isDirectory: true)
        let first = try makeBytesFile(named: "a.mp3", in: scratch)
        let second = try makeBytesFile(named: "b.wav", in: scratch)

        let firstCopy = try await SongTrimService.copyIntoCache(
            from: first, cacheDirectory: cache, access: { _ in false }, release: { _ in }
        )
        let secondCopy = try await SongTrimService.copyIntoCache(
            from: second, cacheDirectory: cache, access: { _ in false }, release: { _ in }
        )

        let remaining = try FileManager.default.contentsOfDirectory(atPath: cache.path)
        #expect(remaining == [secondCopy.lastPathComponent])
        #expect(!FileManager.default.fileExists(atPath: firstCopy.path))
    }

    // MARK: - 3. Security scope

    @Test func securityScopeIsHeldOnlyForTheImport() async throws {
        let scratch = try scratchDirectory()
        let source = try makeBytesFile(named: "song.mp3", in: scratch)
        let log = ScopeLog()

        _ = try await SongTrimService.copyIntoCache(
            from: source,
            cacheDirectory: scratch.appendingPathComponent("cache"),
            access: { _ in log.record("start"); return true },
            release: { _ in log.record("stop") }
        )

        #expect(log.all == ["start", "stop"])
    }

    @Test func scopeIsReleasedEvenWhenTheCopyFails() async throws {
        let scratch = try scratchDirectory()
        let log = ScopeLog()

        _ = try? await SongTrimService.copyIntoCache(
            from: scratch.appendingPathComponent("missing.mp3"),
            cacheDirectory: scratch.appendingPathComponent("cache"),
            access: { _ in log.record("start"); return true },
            release: { _ in log.record("stop") }
        )

        #expect(log.all == ["start", "stop"])
    }

    @Test func scopeNotGrantedIsNeverReleased() async throws {
        let scratch = try scratchDirectory()
        let source = try makeBytesFile(named: "song.mp3", in: scratch)
        let log = ScopeLog()

        _ = try await SongTrimService.copyIntoCache(
            from: source,
            cacheDirectory: scratch.appendingPathComponent("cache"),
            access: { _ in log.record("start"); return false },
            release: { _ in log.record("stop") }
        )

        #expect(log.all == ["start"])
    }

    // MARK: - 4. The copy outlives the source

    @Test func cachedCopySurvivesTheSourceGoingAway() async throws {
        let scratch = try scratchDirectory()
        let source = try makeM4A(in: scratch)
        let copy = try await SongTrimService.copyIntoCache(
            from: source,
            cacheDirectory: scratch.appendingPathComponent("cache"),
            access: { _ in true },
            release: { _ in }
        )

        try FileManager.default.removeItem(at: source)

        #expect(FileManager.default.fileExists(atPath: copy.path))
        let duration = try await SongTrimService.validatedDuration(of: copy)
        #expect(duration > 1)
    }

    // MARK: - 5, 6, 7. The window

    @Test func startClampsToZero() {
        let window = SongTrimWindow(duration: 210)
        #expect(window.clamp(-12) == 0)
        #expect(window.clamp(.nan) == 0)
    }

    @Test func startClampsToDurationMinus28() {
        let window = SongTrimWindow(duration: 210)
        #expect(window.maximumStart == 182)
        #expect(window.clamp(500) == 182)
        #expect(window.range(startingAt: 500) == 182...210)
    }

    @Test func threeThirtyAtOneFourteenSelectsOneFourteenToOneFortyTwo() {
        let window = SongTrimWindow(duration: 210)
        let range = window.range(startingAt: 74)
        #expect(SongTrimWindow.timeLabel(range.lowerBound) == "1:14")
        #expect(SongTrimWindow.timeLabel(range.upperBound) == "1:42")
        #expect(SongTrimWindow.timeLabel(window.maximumStart) == "3:02")
    }

    @Test func shortTrackSelectsItsWholeLength() {
        let window = SongTrimWindow(duration: 19)
        #expect(window.clipLength == 19)
        #expect(window.maximumStart == 0)
        #expect(window.range(startingAt: 5) == 0...19)
    }

    @Test func draggingRightMovesEarlierOneToOne() {
        let window = SongTrimWindow(duration: 210)
        // 10 points per second: 50 points right is five seconds earlier.
        #expect(window.start(dragBase: 74, translation: 50, pointsPerSecond: 10) == 69)
        #expect(window.start(dragBase: 74, translation: -50, pointsPerSecond: 10) == 79)
    }

    @Test func pastTheEndsTheDragResistsAndSettlesInside() {
        let window = SongTrimWindow(duration: 210)
        let overshoot = window.start(dragBase: 2, translation: 400, pointsPerSecond: 10)
        #expect(overshoot < 0)
        #expect(overshoot > -38)
        #expect(window.settle(current: overshoot, projected: overshoot, reduceMotion: false).target == 0)
    }

    @Test func waveformBucketsAreBounded() {
        #expect(SongTrimWindow.waveformBuckets(forDuration: 10) == 60)
        #expect((461...462).contains(SongTrimWindow.waveformBuckets(forDuration: 210)))
        #expect(SongTrimWindow.waveformBuckets(forDuration: 3 * 3_600) == 2_400)
    }

    // MARK: - 8. Preview

    @Test func previewStartsAtTheSelectedStart() {
        let window = SongTrimWindow(duration: 210)
        #expect(window.previewStart(for: 74) == 74)
        #expect(window.previewStart(for: 400) == 182)
    }

    @Test func previewLoopsAtTheEndOfTheWindow() {
        let window = SongTrimWindow(duration: 210)
        #expect(window.previewRestart(currentTime: 90, isPlaying: true, start: 74) == nil)
        #expect(window.previewRestart(currentTime: 102, isPlaying: true, start: 74) == 74)
        #expect(window.previewRestart(currentTime: 10, isPlaying: true, start: 74) == 74)
        // A short track runs off its own end and the player stops.
        let short = SongTrimWindow(duration: 19)
        #expect(short.previewRestart(currentTime: 19, isPlaying: false, start: 0) == 0)
    }

    // MARK: - 9. Export

    @Test func exportCutsTheSelectedWindow() {
        let range = SongTrimService.exportTimeRange(startSeconds: 74, duration: 210)
        #expect(abs(range.start.seconds - 74) < 0.01)
        #expect(abs(range.duration.seconds - 28) < 0.01)

        let clamped = SongTrimService.exportTimeRange(startSeconds: 300, duration: 210)
        #expect(abs(clamped.start.seconds - 182) < 0.01)

        let short = SongTrimService.exportTimeRange(startSeconds: 4, duration: 19)
        #expect(short.start.seconds == 0)
        #expect(abs(short.duration.seconds - 19) < 0.01)
    }

    // MARK: - 10, 11. My Music

    @Test func libraryItemWithoutAnAssetIsRejected() {
        #expect(MediaPicker.trimmableURL(assetURL: nil, hasProtectedAsset: false) == nil)
        let url = URL(string: "ipod-library://item/item.m4a?id=1")!
        #expect(MediaPicker.trimmableURL(assetURL: url, hasProtectedAsset: true) == nil)
        #expect(MediaPicker.trimmableURL(assetURL: url, hasProtectedAsset: false) == url)
    }

    @Test func deniedLibraryNeverPresentsThePicker() {
        #expect(MusicLibraryAccess.decision(for: .denied) == .blocked)
        #expect(MusicLibraryAccess.decision(for: .restricted) == .blocked)
        #expect(MusicLibraryAccess.decision(for: .notDetermined) == .request)
        #expect(MusicLibraryAccess.decision(for: .authorized) == .present)
    }

    @Test func protectedCopyMatchesTheBrief() {
        #expect(
            SongTrimService.TrimError.protectedTrack.errorDescription
                == "this song can't be trimmed. choose a purchased or synced song, or use Files."
        )
        #expect(
            SongTrimService.TrimError.fileInaccessible.errorDescription
                == "couldn't open that audio file. try another one?"
        )
        #expect(
            SongTrimService.TrimError.unsupportedFormat.errorDescription
                == "that audio format isn't supported. try another file?"
        )
    }

    // MARK: - 12. Reduce Motion

    @Test func reduceMotionLandsInTheSamePlace() {
        let window = SongTrimWindow(duration: 210)
        let cases: [(current: Double, projected: Double)] = [
            (74, 90), (5, -40), (180, 260), (100, 100),
        ]
        for item in cases {
            let full = window.settle(current: item.current, projected: item.projected, reduceMotion: false)
            let reduced = window.settle(current: item.current, projected: item.projected, reduceMotion: true)
            #expect(full.target == reduced.target)
            #expect(!reduced.animated)
            #expect(window.range(startingAt: full.target) == window.range(startingAt: reduced.target))
        }
    }
}
