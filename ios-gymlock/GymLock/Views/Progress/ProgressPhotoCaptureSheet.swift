import SwiftUI

/// Full-screen viewfinder for a progress photo.
///
/// Reuses the `CameraPreview` layer-backed view already built for Day 0 rather
/// than declaring a second one, and keeps the same dark, chrome-free treatment
/// so capturing a progress photo feels like the same act as capturing Day 0.
struct ProgressPhotoCaptureSheet: View {
    let onCaptured: (Data) -> Void
    let onCancel: () -> Void

    @State private var camera = ProgressPhotoCameraModel()
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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

                shutter
                    .padding(.bottom, 30)
            }
        }
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
