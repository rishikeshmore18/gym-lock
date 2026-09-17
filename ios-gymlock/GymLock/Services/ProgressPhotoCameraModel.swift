import AVFoundation
import Observation
import UIKit

/// One lens the user can jump to, as the Camera app's chips offer them.
///
/// `videoZoomFactor` is what the device is actually set to; `displayFactor`
/// is what the chip says. They differ on any phone with an ultra-wide, where
/// the device's 1.0 is the ultra-wide and the label the user knows as "1×" is
/// a factor of 2 underneath. Derived from the hardware, never typed in.
struct LensOption: Identifiable, Hashable {
    let videoZoomFactor: CGFloat
    let displayFactor: CGFloat

    var id: CGFloat { videoZoomFactor }

    /// "0.5", "1", "2", "3", "5" — the Camera app's formatting, with the "×"
    /// left to the chip so it can appear on the selected one only.
    var label: String { LensOption.format(displayFactor) }

    static func format(_ factor: CGFloat) -> String {
        let rounded = (factor * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}

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

    // MARK: Zoom

    /// The device's own zoom factor, not the displayed one.
    private(set) var zoomFactor: CGFloat = 1
    /// The chips above the shutter. Empty on the front camera and on a
    /// single-lens device, where there is nothing to jump between.
    private(set) var lensOptions: [LensOption] = []
    /// Lowest and highest factor a pinch may reach on the live device.
    private(set) var zoomRange: ClosedRange<CGFloat> = 1...1
    /// Converts a device factor into the number the user recognises.
    private var displayMultiplier: CGFloat = 1
    private var pinchStartFactor: CGFloat = 1

    /// The factor as the Camera app would print it, for the readout.
    var displayZoom: CGFloat { zoomFactor * displayMultiplier }

    /// Whether the viewfinder can zoom at all. A fixed webcam cannot.
    var canZoom: Bool { zoomRange.upperBound > zoomRange.lowerBound }

    /// The chip whose factor the live zoom currently matches, if any.
    var selectedLens: LensOption? {
        lensOptions.min { abs($0.videoZoomFactor - zoomFactor) < abs($1.videoZoomFactor - zoomFactor) }
            .flatMap { abs($0.videoZoomFactor - zoomFactor) < 0.05 ? $0 : nil }
    }

    /// Digital zoom allowed on the front camera, in displayed terms. There is
    /// no second lens to hand off to, so anything past this is just blur.
    private static let frontMaximumZoom: CGFloat = 2
    /// Ceiling on the rear camera, in device terms. Matches the point past
    /// which the Camera app stops offering more.
    private static let rearMaximumZoom: CGFloat = 15

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
        adoptZoom(of: camera)
        useFullResolution(of: camera)
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
        adoptZoom(of: device)
        useFullResolution(of: device)
        applyMirroring()
    }

    // MARK: Zoom

    /// Reads the lens layout off the device the session is now using.
    ///
    /// Everything here comes from AVFoundation: which factors switch lenses,
    /// which factor is the sensor's own 2× crop, and what multiplier turns a
    /// device factor into the label people know. Hard-coding "0.5 / 1 / 2 / 3"
    /// would be wrong on half the phones this runs on, and silently wrong —
    /// a chip that says 3× while the device sits at a different lens.
    private func adoptZoom(of device: AVCaptureDevice) {
        displayMultiplier = device.displayVideoZoomFactorMultiplier

        let floor = device.minAvailableVideoZoomFactor
        let ceiling: CGFloat
        if device.position == .front {
            ceiling = min(device.maxAvailableVideoZoomFactor, Self.frontMaximumZoom / displayMultiplier)
            lensOptions = []
        } else {
            ceiling = min(device.maxAvailableVideoZoomFactor, Self.rearMaximumZoom)

            // The wide lens the user thinks of as 1× is the device factor that
            // displays as 1 — on a phone with an ultra-wide that is 2.0, not
            // 1.0, which is exactly why this is derived rather than assumed.
            let one = 1 / displayMultiplier
            var factors: Set<CGFloat> = [one]
            for number in device.virtualDeviceSwitchOverVideoZoomFactors {
                factors.insert(CGFloat(number.doubleValue))
            }
            for number in device.activeFormat.secondaryNativeResolutionZoomFactors {
                factors.insert(CGFloat(number.doubleValue))
            }
            // The ultra-wide constituent, when there is one, sits at the
            // device's floor and is only worth a chip if it is a real lens
            // below 1×.
            if device.isVirtualDevice, device.constituentDevices.contains(where: { $0.deviceType == .builtInUltraWideCamera }) {
                factors.insert(floor)
            }

            let usable = factors.filter { $0 >= floor && $0 <= ceiling }.sorted()
            lensOptions = usable.count > 1
                ? usable.map { LensOption(videoZoomFactor: $0, displayFactor: $0 * displayMultiplier) }
                : []
        }

        zoomRange = floor...max(floor, ceiling)

        // Open on the wide lens, as the Camera app does, not on the
        // ultra-wide the device happens to call 1.0.
        let opening = lensOptions.first { abs($0.displayFactor - 1) < 0.05 }?.videoZoomFactor ?? floor
        set(zoom: opening, ramped: false)
    }

    /// The user's fingers have just touched down: remember where the zoom was
    /// so the pinch scales from there rather than from wherever it drifted to.
    func beginPinch() {
        pinchStartFactor = zoomFactor
    }

    /// Follows a pinch 1:1, clamped to what the lens can do.
    func pinch(magnification: CGFloat) {
        guard canZoom else { return }
        set(zoom: pinchStartFactor * magnification, ramped: false)
    }

    /// Jumps to a chip's lens the way the Camera app does — a short ramp, so
    /// the hand-off between physical lenses reads as one continuous zoom.
    func select(_ lens: LensOption) {
        guard lens != selectedLens else { return }
        Haptics.selection()
        set(zoom: lens.videoZoomFactor, ramped: true)
    }

    private func set(zoom factor: CGFloat, ramped: Bool) {
        guard let device = input?.device else { return }
        let clamped = min(max(factor, zoomRange.lowerBound), zoomRange.upperBound)

        do {
            try device.lockForConfiguration()
            if ramped {
                device.ramp(toVideoZoomFactor: clamped, withRate: 4)
            } else {
                if device.isRampingVideoZoom { device.cancelVideoZoomRamp() }
                device.videoZoomFactor = clamped
            }
            device.unlockForConfiguration()
            zoomFactor = clamped
        } catch {
            // A device that will not lock keeps its current zoom; the readout
            // stays honest by not moving either.
        }
    }

    /// Asks for the sensor's full output rather than the output's default.
    ///
    /// Without this a 48-megapixel sensor hands back 12-megapixel frames — the
    /// store downsamples to 2400 px anyway, but it should be downsampling the
    /// best frame the camera can produce, not a frame the camera already
    /// halved.
    private func useFullResolution(of device: AVCaptureDevice) {
        guard let largest = device.activeFormat.supportedMaxPhotoDimensions.last else { return }
        photoOutput.maxPhotoDimensions = largest
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

    /// The best device at a position.
    ///
    /// The rear list is ordered virtual-first on purpose: a triple or dual
    /// camera switches lenses itself as the zoom crosses each threshold, which
    /// is what makes pinching feel like the Camera app rather than a crop.
    private static func camera(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = switch position {
        case .back:
            [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        case .front:
            [.builtInTrueDepthCamera, .builtInWideAngleCamera]
        default:
            [.external]
        }
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: position
        ).devices.first
    }

    /// Any usable camera, including the cloud simulator's injected webcam,
    /// which reports an unspecified position.
    private static func anyCamera() -> AVCaptureDevice? {
        discovered().first
    }

    private static func discovered() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera,
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

        let settings = AVCapturePhotoSettings()
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        photoOutput.capturePhoto(with: settings, delegate: self)
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
