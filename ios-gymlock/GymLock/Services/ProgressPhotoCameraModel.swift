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

    /// Which lens is live.
    ///
    /// Starts on the front camera because that is how a progress photo is
    /// actually taken — arm out, looking at yourself, checking the framing
    /// before you commit. Opening on the rear lens means every single user
    /// has to find a flip control before they can take the photo they came for.
    private(set) var position: AVCaptureDevice.Position = .front
    /// Whether there is a second lens worth offering.
    ///
    /// Drives whether the flip control is drawn at all: a control that cannot
    /// change anything is worse than no control, and the simulator publishes a
    /// single external webcam with no opposite to switch to.
    private(set) var canFlip = false

    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
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

        // Prefer the intended lens, but never refuse to open a camera just
        // because the preferred one is absent — an iPad with only a rear
        // camera should still be able to take the photo.
        guard let camera = Self.camera(at: position) ?? Self.anyCamera() else {
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
        self.input = input
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        session.commitConfiguration()

        position = camera.position
        isConfigured = true
        canFlip = Self.camera(at: .front) != nil && Self.camera(at: .back) != nil
        applyMirroring()
        return true
    }

    /// Swaps between the front and rear lens on a live session.
    ///
    /// Reconfiguring in place rather than tearing the session down and building
    /// a new one: the preview stays up through the swap, which is what makes it
    /// feel like the system camera instead of a reload. If the new input cannot
    /// be opened the previous one is put back, so a failed flip leaves a
    /// working viewfinder rather than a black screen.
    func flip() {
        guard canFlip, !isCapturing, isConfigured else { return }

        let next: AVCaptureDevice.Position = position == .front ? .back : .front
        guard let device = Self.camera(at: next),
              let replacement = try? AVCaptureDeviceInput(device: device)
        else { return }

        Haptics.tap()
        session.beginConfiguration()

        let previous = input
        if let previous { session.removeInput(previous) }

        guard session.canAddInput(replacement) else {
            if let previous, session.canAddInput(previous) { session.addInput(previous) }
            session.commitConfiguration()
            return
        }

        session.addInput(replacement)
        input = replacement
        session.commitConfiguration()

        position = next
        applyMirroring()
    }

    /// Makes the saved photo match the viewfinder on the front camera.
    ///
    /// The preview layer mirrors the front lens, so an unmirrored capture hands
    /// back a photo that is flipped relative to the one the user just framed
    /// and approved. For a feature whose whole purpose is comparing photographs
    /// of the same body over months, a silent left-right flip between shots is
    /// not a cosmetic detail — it makes the comparison misleading.
    private func applyMirroring() {
        guard let connection = photoOutput.connection(with: .video),
              connection.isVideoMirroringSupported
        else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = position == .front
    }

    private static func camera(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        discovered().first { $0.position == position }
    }

    /// Any usable camera, including the cloud simulator's injected webcam,
    /// which reports an unspecified position.
    private static func anyCamera() -> AVCaptureDevice? {
        discovered().first
    }

    private static func discovered() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInDualWideCamera,
                .builtInTrueDepthCamera,
                .external,
            ],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    // MARK: Capture

    func capture() {
        guard availability == .ready, !isCapturing else { return }
        isCapturing = true
        Haptics.medium()
        // Reasserted here as well as after configuration: adding the output can
        // hand back a fresh connection whose mirroring defaults are its own.
        applyMirroring()
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
