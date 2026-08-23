import AVFoundation
import Observation
import UIKit

/// The camera behind the photo missions.
///
/// Distinct from `Day0CameraModel` for one reason that is not cosmetic: a Day 0
/// capture is a keepsake and is written to Documents, while a mission photo is
/// evidence for a check that lasts four seconds. This model therefore **never
/// touches the filesystem**. The JPEG lives in a property, gets handed to the
/// verifier, and is set to nil immediately afterwards. There is no code path
/// here that could put a mission photo into Day 0, progress, or a gallery.
///
/// As elsewhere, `.external` is in the discovery session so the real pipeline
/// runs on the simulator's injected webcam rather than being stubbed out.
@Observable
@MainActor
final class MissionCameraModel: NSObject {
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

    /// Whether photo missions may be offered.
    var canVerify: Bool {
        switch availability {
        case .ready, .preparing: true
        case .permissionDenied, .noCameraFound, .failed: false
        }
    }

    // MARK: - Lifecycle

    /// Checks permission without prompting, so mission selection can filter
    /// without throwing a dialog at someone who has not asked for one.
    func refreshAvailability() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            availability = .permissionDenied
        case .authorized:
            if case .permissionDenied = availability { availability = .preparing }
        default:
            break
        }
    }

    func start(onCaptured: @escaping (Data) -> Void) {
        self.onCaptured = onCaptured
        Task { await prepare() }
    }

    func stop() {
        let session = session
        Task.detached {
            if session.isRunning { session.stopRunning() }
        }
        onCaptured = nil
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

        guard let camera = Self.rearOrAnyCamera() else {
            availability = .noCameraFound
            return false
        }

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input)
        else {
            session.commitConfiguration()
            availability = .failed("this device's camera could not be opened.")
            return false
        }

        session.addInput(input)
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        session.commitConfiguration()

        isConfigured = true
        return true
    }

    /// Prefers the rear camera: every photo mission points at something in the
    /// room, not at the user.
    private static func rearOrAnyCamera() -> AVCaptureDevice? {
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

    // MARK: - Capture

    func capture() {
        guard availability == .ready, !isCapturing else { return }
        isCapturing = true
        Haptics.tap()
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }
}

extension MissionCameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = photo.fileDataRepresentation()

        Task { @MainActor in
            isCapturing = false
            guard error == nil, let data else {
                availability = .failed("that photo didn't capture.")
                return
            }
            // Handed straight to the verifier. No local copy is retained.
            onCaptured?(data)
        }
    }
}
