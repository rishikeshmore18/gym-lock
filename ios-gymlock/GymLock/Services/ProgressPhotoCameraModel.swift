import AVFoundation
import Observation
import UIKit

/// Drives the camera for a progress photo.
///
/// Deliberately separate from `Day0CameraModel`, which writes its own file into
/// Documents and hands back a `Day0Media`. Progress photos have a single owner
/// — `ProgressPhotoStore` — and letting a second type write image files would
/// mean two definitions of "saved" and two places a half-written photo could
/// come from. This model captures bytes and nothing else.
@Observable
@MainActor
final class ProgressPhotoCameraModel: NSObject {
    enum Availability: Equatable {
        case preparing
        case ready
        case permissionDenied
        case noCameraFound
        case failed(String)
    }

    private(set) var availability: Availability = .preparing
    private(set) var isCapturing = false

    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false
    private var onCaptured: ((Data) -> Void)?
    private var onFailure: ((String) -> Void)?

    // MARK: Lifecycle

    func start(onCaptured: @escaping (Data) -> Void, onFailure: @escaping (String) -> Void) {
        self.onCaptured = onCaptured
        self.onFailure = onFailure
        Task { await prepare() }
    }

    func stop() {
        let session = session
        Task.detached {
            if session.isRunning { session.stopRunning() }
        }
    }

    private func prepare() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                availability = .permissionDenied
                return
            }
        default:
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

    private func configureIfNeeded() -> Bool {
        guard !isConfigured else { return true }

        guard let camera = Self.preferredCamera() else {
            availability = .noCameraFound
            return false
        }

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input)
        else {
            session.commitConfiguration()
            availability = .failed("This device's camera could not be opened.")
            return false
        }

        session.addInput(input)
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        session.commitConfiguration()
        isConfigured = true
        return true
    }

    /// Back camera first: a progress photo is usually taken in a mirror or by
    /// someone else, and the rear lens is the better one. Falls back to
    /// whatever exists, including the simulator's injected external webcam.
    private static func preferredCamera() -> AVCaptureDevice? {
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
        return devices.first { $0.position == .back }
            ?? devices.first { $0.position == .front }
            ?? devices.first
    }

    // MARK: Capture

    func capture() {
        guard availability == .ready, !isCapturing else { return }
        isCapturing = true
        Haptics.medium()
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    fileprivate func finish(with data: Data) {
        isCapturing = false
        onCaptured?(data)
    }

    fileprivate func fail(_ message: String) {
        isCapturing = false
        onFailure?(message)
    }
}

extension ProgressPhotoCameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            Task { @MainActor in fail("That photo didn't save. Try again?") }
            return
        }
        Task { @MainActor in finish(with: data) }
    }
}
