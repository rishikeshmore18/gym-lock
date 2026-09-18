import AVFoundation
import SwiftUI

/// Full-screen viewfinder for a progress photo, with the system camera's own
/// two-step rhythm: shoot, then look at what you got and decide.
///
/// The review step is not a nicety. A progress photo is taken at arm's length,
/// in a mirror, often with a timer — the odds of the first frame being the one
/// the user wants are poor. Apple's Camera app answers this with Retake and Use
/// Photo, and this screen keeps those exact words and positions, because the
/// muscle memory is already there.
///
/// Retake returns to the live viewfinder rather than dismissing: the user is
/// still taking a photo, and being thrown back to the Progress tab to start
/// again would punish them for looking.
struct ProgressPhotoCaptureSheet: View {
    /// Whether the store is mid-write, so the review can hold its buttons.
    let isSaving: Bool
    /// Called once the user has reviewed the frame and chosen what to do with
    /// it. Nothing is written before this.
    let onApproved: (Data, ProgressPhotoIntent) -> Void
    let onCancel: () -> Void

    /// Shoot or review. Modelled as one value with the image attached, so there
    /// is no way to be reviewing without something to review.
    private enum Phase: Equatable {
        case capturing
        case reviewing(data: Data, image: UIImage)
    }

    @State private var camera = ProgressPhotoCameraModel()
    @State private var phase: Phase = .capturing
    @State private var errorMessage: String?
    /// Whether the zoom readout is showing. Shown while pinching and for a
    /// moment after, then gone, as the Camera app does it.
    @State private var isShowingZoomReadout = false
    @State private var readoutFade: Task<Void, Never>?
    /// True from the first pinch change to its end. Separate from the readout
    /// flag: a second pinch that starts while the readout is still fading has
    /// to re-anchor its start factor, or it jumps.
    @State private var isPinching = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch phase {
            case .capturing:
                capturing
            case let .reviewing(_, image):
                ProgressPhotoReviewView(
                    image: image,
                    retakeTitle: "Retake",
                    isBusy: isSaving,
                    onRetake: {
                        // Straight back to the live feed. The session was
                        // never stopped, so this is instant rather than a
                        // second launch.
                        phase = .capturing
                    },
                    onChoose: { intent in
                        guard case let .reviewing(data, _) = phase else { return }
                        onApproved(data, intent)
                    },
                    onCancel: onCancel
                )
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.22), value: phase)
        .onAppear(perform: startCamera)
        .onDisappear {
            readoutFade?.cancel()
            camera.stop()
        }
    }

    // MARK: Capture

    @ViewBuilder
    private var capturing: some View {
        switch camera.availability {
        case .preparing:
            ProgressView().tint(.white)
        case .ready:
            viewfinder
        case .permissionDenied:
            message(
                icon: "lock.fill",
                title: "Camera access is off",
                body: "GymLock needs the camera to take a progress photo. Nothing leaves this iPhone.",
                actionTitle: "Open Settings",
                action: openSettings
            )
        case .noCameraFound:
            message(
                icon: "camera.fill",
                title: "No camera available",
                body: "This device doesn't have a camera GymLock can use. You can add a photo from Photos or Files instead.",
                actionTitle: nil,
                action: nil
            )
        case let .failed(reason):
            message(
                icon: "exclamationmark.triangle.fill",
                title: "Camera unavailable",
                body: reason,
                actionTitle: nil,
                action: nil
            )
        }

        closeButton
    }

    private var viewfinder: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
                // Two fingers zoom the lens, exactly as in Camera. The pinch
                // is read from where it started rather than accumulated, so
                // lifting and re-pinching does not compound.
                .gesture(pinch)

            VStack {
                Text("progress photo")
                    .font(.system(size: 13, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .viewfinderGlass(in: .capsule)
                    .padding(.top, 12)

                Spacer()

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .viewfinderGlass(in: .capsule)
                        .padding(.bottom, 14)
                }

                zoomReadout
                    .padding(.bottom, 10)

                if !camera.lensOptions.isEmpty {
                    lensChips
                        .padding(.bottom, 14)
                }

                Text("stored only on this iPhone. never uploaded.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom, 18)

                controls
                    .padding(.bottom, 30)
            }
        }
    }

    // MARK: Zoom

    private var pinch: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .onChanged { value in
                if !isPinching {
                    isPinching = true
                    camera.beginPinch()
                    readoutFade?.cancel()
                    withAnimation(.easeOut(duration: 0.12)) { isShowingZoomReadout = true }
                }
                camera.pinch(magnification: value.magnification)
            }
            .onEnded { _ in
                isPinching = false
                scheduleReadoutFade()
            }
    }

    /// The "1.7×" capsule the Camera app shows mid-pinch.
    ///
    /// Held in the layout at zero opacity rather than inserted and removed, so
    /// the chips below never shift when it appears.
    private var zoomReadout: some View {
        Text("\(LensOption.format(camera.displayZoom))×")
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .viewfinderGlass(in: .capsule)
            .opacity(isShowingZoomReadout ? 1 : 0)
            .accessibilityHidden(!isShowingZoomReadout)
    }

    /// Lens chips, derived from the device (see `ProgressPhotoCameraModel`).
    ///
    /// The "×" appears on the selected chip only, as in Camera; the others
    /// read as plain factors so the row stays quiet.
    private var lensChips: some View {
        HStack(spacing: 6) {
            ForEach(camera.lensOptions) { lens in
                let isSelected = camera.selectedLens == lens
                Button {
                    camera.select(lens)
                } label: {
                    Text(isSelected ? "\(lens.label)×" : lens.label)
                        .font(.system(size: isSelected ? 13 : 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Color(red: 1, green: 0.8, blue: 0.2) : .white)
                        .frame(minWidth: isSelected ? 36 : 30, minHeight: isSelected ? 36 : 30)
                        .background(Color.black.opacity(isSelected ? 0.55 : 0.35), in: .circle)
                        // The whole chip clears 44 pt for the thumb even
                        // though the drawn circle is smaller.
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .animation(Theme.stateChange, value: isSelected)
                .accessibilityLabel("\(lens.label)× lens")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .viewfinderGlass(in: .capsule)
        .disabled(camera.isCapturing)
    }

    private func scheduleReadoutFade() {
        readoutFade?.cancel()
        readoutFade = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { isShowingZoomReadout = false }
        }
    }

    /// The shutter, with the lens switch beside it.
    ///
    /// The shutter stays centred on the screen rather than centred in the row,
    /// because it is the control the thumb aims for without looking. The flip
    /// sits in the right-hand margin, where the system camera puts it.
    private var controls: some View {
        ZStack {
            shutter

            if camera.canFlip {
                HStack {
                    Spacer()
                    flipButton
                }
                .padding(.horizontal, 34)
            }
        }
    }

    private var flipButton: some View {
        Button {
            camera.flip()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .viewfinderGlass(in: .circle)
        }
        .disabled(camera.isCapturing)
        .accessibilityLabel(
            camera.position == .front ? "Switch to rear camera" : "Switch to front camera"
        )
    }

    private var shutter: some View {
        Button {
            camera.capture()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(.white)
                    .frame(width: 62, height: 62)
            }
        }
        .disabled(camera.isCapturing)
        .accessibilityLabel("Take progress photo")
    }

    // MARK: Chrome

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                ViewfinderCloseButton(action: onCancel)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private func message(
        icon: String,
        title: String,
        body: String,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.accent)

            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            Text(body)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: Wiring

    private func startCamera() {
        camera.start { data in
            // The photo is held here, not handed to the store. Nothing is
            // written until the user has seen it and said yes.
            guard let image = UIImage(data: data) else {
                errorMessage = "That photo didn't save. Try again?"
                return
            }
            errorMessage = nil
            phase = .reviewing(data: data, image: image)
        } onFailure: { message in
            errorMessage = message
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
