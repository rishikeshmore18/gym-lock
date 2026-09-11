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
    let onCaptured: (Data) -> Void
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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch phase {
            case .capturing:
                capturing
            case let .reviewing(data, image):
                review(data: data, image: image)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.22), value: phase)
        .onAppear(perform: startCamera)
        .onDisappear { camera.stop() }
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

            VStack {
                Text("progress photo")
                    .font(.system(size: 13, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: .capsule)
                    .padding(.top, 12)

                Spacer()

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: .capsule)
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
                .background(.ultraThinMaterial, in: .circle)
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

    // MARK: Review

    /// The captured frame, shown whole rather than cropped.
    ///
    /// `.fit`, not `.fill`: the user is about to decide whether this photograph
    /// is the one, and a preview that quietly crops their head off would make
    /// that decision on false information.
    private func review(data: Data, image: UIImage) -> some View {
        VStack(spacing: 0) {
            Text("use this photo?")
                .font(.system(size: 13, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.8)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: .capsule)
                .padding(.top, 14)

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 16)
                .transition(.opacity)

            HStack {
                Button {
                    Haptics.tap()
                    // Straight back to the live feed. The session was never
                    // stopped, so this is instant rather than a second launch.
                    phase = .capturing
                } label: {
                    Text("Retake")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 96, minHeight: 44, alignment: .leading)
                }

                Spacer()

                Button {
                    Haptics.tap()
                    onCaptured(data)
                } label: {
                    Text("Use Photo")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 22)
                        .frame(height: 48)
                        .background(.white, in: .capsule)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .overlay(alignment: .topTrailing) {
            closeControl.padding(.horizontal, 18).padding(.top, 10)
        }
    }

    // MARK: Chrome

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                closeControl
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private var closeControl: some View {
        Button {
            Haptics.tap()
            onCancel()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: .circle)
        }
        .accessibilityLabel("Close")
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
