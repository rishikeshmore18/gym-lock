import AVFoundation
import SwiftUI

/// Live camera preview for the Day 0 capture.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }

    /// A UIView whose backing layer *is* the preview layer, so the preview
    /// resizes with the view instead of needing manual frame bookkeeping.
    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            guard let layer = layer as? AVCaptureVideoPreviewLayer else {
                return AVCaptureVideoPreviewLayer()
            }
            return layer
        }
    }
}

/// The full-screen Day 0 capture.
///
/// This is the only part of onboarding that leaves GymLock's warm canvas behind,
/// and deliberately so: a viewfinder should look like a viewfinder. The privacy
/// promise is repeated here, at the moment it actually matters, rather than only
/// on the screen that led here.
struct Day0CaptureSheet: View {
    let kind: Day0Media.Kind
    let onCaptured: (Day0Media) -> Void
    let onCancel: () -> Void

    @State private var camera = Day0CameraModel()
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.availability {
            case .preparing:
                ProgressView()
                    .tint(.white)
            case .ready:
                viewfinder
            case .permissionDenied:
                message(
                    icon: "lock.fill",
                    title: "camera access is off",
                    body: "GymLock needs the camera to take your Day 0. nothing leaves this iPhone.",
                    actionTitle: "open settings",
                    action: openSettings
                )
            case .noCameraFound:
                message(
                    icon: "camera.fill",
                    title: "no camera available",
                    body: "this device doesn't have a camera GymLock can use. you can skip Day 0 and add it later.",
                    actionTitle: nil,
                    action: nil
                )
            case let .failed(reason):
                message(
                    icon: "exclamationmark.triangle.fill",
                    title: "camera unavailable",
                    body: reason,
                    actionTitle: nil,
                    action: nil
                )
            }

            closeButton
        }
        .preferredColorScheme(.dark)
        .onAppear {
            camera.start(onCaptured: onCaptured) { message in
                errorMessage = message
            }
        }
        .onDisappear { camera.stop() }
    }

    private var viewfinder: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            VStack {
                Text(kind == .photo ? "day 0 photo" : "day 0 · 5 seconds")
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

                shutter
                    .padding(.bottom, 30)
            }
        }
    }

    /// One control, sized for a thumb, doing the obvious thing.
    private var shutter: some View {
        Button {
            if kind == .photo {
                camera.capturePhoto()
            } else if !camera.isRecording {
                camera.startRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 76, height: 76)

                if camera.isRecording {
                    // A ring draining as the five seconds run out, so the user
                    // knows exactly how long is left without a number.
                    Circle()
                        .trim(from: 0, to: camera.recordingRemaining / Day0CameraModel.videoDuration)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 76, height: 76)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: camera.recordingRemaining)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.accent)
                        .frame(width: 30, height: 30)
                } else {
                    Circle()
                        .fill(kind == .video ? Theme.accent : .white)
                        .frame(width: 62, height: 62)
                }
            }
        }
        .disabled(camera.isCapturing || camera.isRecording)
        .accessibilityLabel(kind == .photo ? "Take Day 0 photo" : "Record Day 0 video")
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
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

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
