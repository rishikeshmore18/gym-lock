import AVFoundation
import Observation
import UIKit

/// Drives the Day 0 capture session.
///
/// Two rules shape this type. First, nothing ever leaves the device: the photo
/// or clip is written straight into the app's own Documents directory and no
/// network code exists anywhere near it. Second, the real capture pipeline runs
/// everywhere — including the simulator, where the host's webcam is published as
/// an *external* camera — so `.external` is part of the discovery session rather
/// than something guarded behind a build flag.
@Observable
@MainActor
final class Day0CameraModel: NSObject {
    /// What the session is currently able to do.
    enum Availability: Equatable {
        case preparing
        case ready
        case permissionDenied
        case noCameraFound
        case failed(String)
    }

    private(set) var availability: Availability = .preparing
    private(set) var isRecording = false
    private(set) var isCapturing = false
    /// Seconds remaining in the video capture, for the countdown ring.
    private(set) var recordingRemaining: Double = 0

    /// Longest Day 0 clip. Short on purpose: this is a marker, not a vlog.
    static let videoDuration: Double = 5

    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var isConfigured = false
    private var countdown: Task<Void, Never>?

    private var onCaptured: ((Day0Media) -> Void)?
    private var onFailure: ((String) -> Void)?

    // MARK: - Lifecycle

    func start(onCaptured: @escaping (Day0Media) -> Void, onFailure: @escaping (String) -> Void) {
        self.onCaptured = onCaptured
        self.onFailure = onFailure

        Task { await prepare() }
    }

    func stop() {
        countdown?.cancel()
        countdown = nil

        let session = session
        Task.detached {
            if session.isRunning { session.stopRunning() }
        }
    }

    private func prepare() async {
        guard await ensureAuthorised() else {
            availability = .permissionDenied
            return
        }

        guard configureIfNeeded() else { return }

        let session = session
        await Task.detached {
            if !session.isRunning { session.startRunning() }
        }.value

        if case .preparing = availability { availability = .ready }
    }

    /// Video capture also needs the microphone, so both are requested up front
    /// rather than interrupting the user mid-recording.
    private func ensureAuthorised() async -> Bool {
        let video = await requestAccess(for: .video)
        _ = await requestAccess(for: .audio)
        return video
    }

    private func requestAccess(for media: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: media)
        default: return false
        }
    }

    // MARK: - Session

    private func configureIfNeeded() -> Bool {
        guard !isConfigured else { return true }

        guard let camera = Self.frontOrAnyCamera() else {
            availability = .noCameraFound
            return false
        }

        session.beginConfiguration()
        session.sessionPreset = .high

        do {
            let videoInput = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(videoInput) else {
                throw CaptureSetupError.cannotAddInput
            }
            session.addInput(videoInput)

            // Audio is optional: a silent Day 0 clip is far better than none.
            if let microphone = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: microphone),
               session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }

            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }

            session.commitConfiguration()
            isConfigured = true
            return true
        } catch {
            session.commitConfiguration()
            availability = .failed("this device's camera could not be opened.")
            return false
        }
    }

    /// Prefers the selfie camera for a progress photo, but accepts whatever the
    /// device actually has — including the simulator's injected webcam, which
    /// arrives as an external device.
    private static func frontOrAnyCamera() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInDualWideCamera,
                .builtInTrueDepthCamera,
                .external,
            ],
            mediaType: .video,
            position: .unspecified
        )

        let devices = discovery.devices
        return devices.first { $0.position == .front }
            ?? devices.first { $0.position == .back }
            ?? devices.first
    }

    // MARK: - Capture

    func capturePhoto() {
        guard availability == .ready, !isCapturing, !isRecording else { return }
        isCapturing = true
        Haptics.medium()

        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func startRecording() {
        guard availability == .ready, !isRecording, !isCapturing else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("day0-\(UUID().uuidString).mov")

        movieOutput.maxRecordedDuration = CMTime(
            seconds: Self.videoDuration,
            preferredTimescale: 600
        )
        movieOutput.startRecording(to: url, recordingDelegate: self)

        isRecording = true
        recordingRemaining = Self.videoDuration
        Haptics.medium()

        countdown = Task { await runCountdown() }
    }

    private func runCountdown() async {
        while !Task.isCancelled, recordingRemaining > 0 {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { return }
            recordingRemaining = max(0, recordingRemaining - 0.1)
        }
    }

    // MARK: - Saving

    fileprivate func finish(with media: Day0Media) {
        isCapturing = false
        isRecording = false
        countdown?.cancel()
        Haptics.commit()
        onCaptured?(media)
    }

    fileprivate func fail(_ message: String) {
        isCapturing = false
        isRecording = false
        countdown?.cancel()
        onFailure?(message)
    }

    fileprivate nonisolated static func documentsURL(named name: String) -> URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(name)
    }
}

private enum CaptureSetupError: Error {
    case cannotAddInput
}

// MARK: - Photo delegate

extension Day0CameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            Task { @MainActor in fail("that photo didn't save. try again?") }
            return
        }

        let name = "day0-\(UUID().uuidString).jpg"
        guard let url = Self.documentsURL(named: name) else {
            Task { @MainActor in fail("couldn't find somewhere to store it.") }
            return
        }

        do {
            try data.write(to: url, options: .atomic)
            let media = Day0Media(kind: .photo, fileName: name, capturedAt: Date())
            Task { @MainActor in finish(with: media) }
        } catch {
            Task { @MainActor in fail("that photo didn't save. try again?") }
        }
    }
}

// MARK: - Movie delegate

extension Day0CameraModel: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        // Hitting `maxRecordedDuration` reports an error even though the file is
        // perfectly good, so the file is trusted over the error.
        let recorded = (try? outputFileURL.checkResourceIsReachable()) ?? false
        guard recorded else {
            Task { @MainActor in fail("that clip didn't record. try again?") }
            return
        }

        let name = "day0-\(UUID().uuidString).mov"
        guard let destination = Self.documentsURL(named: name) else {
            Task { @MainActor in fail("couldn't find somewhere to store it.") }
            return
        }

        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: outputFileURL, to: destination)
            let media = Day0Media(kind: .video, fileName: name, capturedAt: Date())
            Task { @MainActor in finish(with: media) }
        } catch {
            Task { @MainActor in fail("that clip didn't save. try again?") }
        }
    }
}
