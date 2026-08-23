import AVFoundation
import SwiftUI

/// Runs one mission to completion.
///
/// The three kinds of mission are genuinely different interactions — a step
/// counter, a camera check, a spoken line — so each gets its own body. What they
/// share is the frame around them and, more importantly, the rules:
///
/// - **The image never lands on disk.** Photo missions hand the JPEG straight to
///   the verifier and drop the reference. There is no code path from here into
///   Day 0, progress, or any gallery.
/// - **Nothing spoken is kept.** The transcript exists while it is being matched
///   and is discarded on exit, whatever the outcome.
/// - **"Another mission" is always on screen.** A failed sensor, a denied
///   permission, or a photo the model cannot read must never trap someone who
///   has already committed to going.
struct MissionRunnerView: View {
    let mission: ActivationMissionType
    let phrase: String
    let camera: MissionCameraModel
    let motion: MotionMissionMonitor
    let speech: SpeechMissionVerifier
    let onVerified: () -> Void
    let onAnotherMission: () -> Void
    let onDismiss: () -> Void

    @State private var status: MissionVerificationStatus = .idle
    @State private var verifier: any MissionVerificationProviding = VisionMissionVerifier()
    @State private var hasFinished = false

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                MorningHeader(
                    trailingTitle: "Close",
                    trailingAction: dismiss,
                    leadingSymbol: "bolt.fill"
                )

                ScrollView {
                    VStack(spacing: 22) {
                        title

                        switch mission.capability {
                        case .motion: stepBody
                        case .camera: cameraBody
                        case .speech: speechBody
                        }

                        statusBanner
                    }
                    .padding(.horizontal, Theme.pageMargin)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)

                Button {
                    Haptics.tap()
                    cleanUp()
                    onAnotherMission()
                } label: {
                    Label("another mission", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .padding(.horizontal, Theme.pageMargin)
                .padding(.bottom, 8)
            }
        }
        .task { await begin() }
        .onDisappear { cleanUp() }
    }

    // MARK: - Shared chrome

    private var title: some View {
        VStack(spacing: 6) {
            Text(mission.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)

            Text(mission.subtitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch status {
        case .checking:
            banner(icon: "hourglass", tint: Theme.inkSecondary, text: "checking…")

        case .verified:
            banner(icon: "checkmark.circle.fill", tint: Theme.accent, text: "that's it. go.")

        case let .uncertain(message):
            // Never an accusation. The app could not tell; that is a statement
            // about the photo, not about the person holding the phone.
            banner(icon: "questionmark.circle.fill", tint: Theme.inkSecondary, text: message)

        case let .failed(message):
            banner(icon: "exclamationmark.circle.fill", tint: Theme.inkSecondary, text: message)

        case .permissionDenied:
            banner(
                icon: "lock.circle.fill",
                tint: Theme.inkSecondary,
                text: "that permission is off. try another mission instead."
            )

        case .offline:
            banner(
                icon: "wifi.slash",
                tint: Theme.inkSecondary,
                text: "no connection — using the on-device check."
            )

        case .idle:
            EmptyView()
        }
    }

    private func banner(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)

            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceMuted, in: .rect(cornerRadius: 14))
        .transition(.opacity)
        .animation(Theme.stateChange, value: status)
    }

    // MARK: - Step mission

    private var stepBody: some View {
        let target = mission.stepTarget ?? 20
        let progress = min(1, Double(motion.steps) / Double(target))

        return VStack(spacing: 20) {
            ZStack {
                CountdownRing(remainingFraction: progress, size: 216, lineWidth: 14)

                VStack(spacing: -2) {
                    Text("\(min(motion.steps, target))")
                        .font(.system(size: 62, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())

                    Text("of \(target) steps")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .frame(height: 226)

            if motion.availability == .denied || motion.availability == .unsupported {
                unavailableNote(
                    "GymLock can't count steps on this device right now.",
                    detail: "pick another mission and you'll be moving in a few seconds."
                )
            }
        }
        .onChange(of: motion.steps) { _, steps in
            guard steps >= target, !hasFinished else { return }
            succeed()
        }
    }

    // MARK: - Camera mission

    private var cameraBody: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Theme.surfaceMuted)

                switch camera.availability {
                case .ready:
                    MissionCameraPreview(session: camera.session)
                        .clipShape(.rect(cornerRadius: 24))
                        .allowsHitTesting(false)

                case .preparing:
                    ProgressView().tint(Theme.accent)

                case .permissionDenied:
                    cameraMessage(
                        icon: "camera.fill",
                        title: "camera access is off",
                        detail: "you can turn it on in Settings, or take a different mission."
                    )

                case .noCameraFound:
                    cameraMessage(
                        icon: "camera.fill",
                        title: "no camera found",
                        detail: "take a movement mission instead."
                    )

                case let .failed(message):
                    cameraMessage(icon: "camera.fill", title: "camera trouble", detail: message)
                }
            }
            .frame(height: 320)
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Theme.border, lineWidth: 1)
            }

            if camera.availability == .ready {
                Text(mission.visionSubject?.prompt ?? mission.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    guard !status.isBusy else { return }
                    withAnimation(Theme.stateChange) { status = .checking }
                    camera.capture()
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(Theme.accent, lineWidth: 3)
                            .frame(width: 76, height: 76)
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 62, height: 62)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .disabled(status.isBusy)
                .opacity(status.isBusy ? 0.5 : 1)
                .accessibilityLabel("Take the photo")
            }

            Text("this photo is checked on your phone and deleted straight after.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
                .multilineTextAlignment(.center)
        }
    }

    private func cameraMessage(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(detail)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    // MARK: - Mirror mission

    /// The mirror mission is verified by speech, not by a photo.
    ///
    /// A mirror selfie proves someone stood in front of a mirror. It says
    /// nothing about whether they read the line — and reading it out loud is the
    /// entire mechanism. So the camera is optional here and the microphone is
    /// what actually decides.
    private var speechBody: some View {
        VStack(spacing: 20) {
            VStack(spacing: 14) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.accent.opacity(0.5))

                Text(phrase)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text("look at yourself and read this out loud.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .warmCard(radius: 22)

            if speech.availability == .denied || speech.availability == .unsupported {
                unavailableNote(
                    "GymLock can't listen right now.",
                    detail: "take another mission — it'll be just as quick."
                )
            } else {
                listeningIndicator
            }
        }
        .onChange(of: speech.didMatch) { _, matched in
            guard matched, !hasFinished else { return }
            succeed()
        }
    }

    private var listeningIndicator: some View {
        VStack(spacing: 14) {
            HStack(spacing: 5) {
                ForEach(0..<5, id: \.self) { bar in
                    let weight = [0.5, 0.85, 1.0, 0.7, 0.45][bar]
                    let height = 8 + (speech.isListening ? speech.match * 30 * weight + 6 * weight : 0)

                    Capsule()
                        .fill(Theme.accent.opacity(speech.isListening ? 0.9 : 0.25))
                        .frame(width: 4, height: max(8, height))
                }
            }
            .frame(height: 44)
            .animation(.easeOut(duration: 0.18), value: speech.match)
            .animation(Theme.stateChange, value: speech.isListening)

            Text(speech.isListening ? "listening…" : "getting ready to listen…")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)

            // Live transcript, held in memory only and never written anywhere.
            if !speech.transcript.isEmpty {
                Text(speech.transcript)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .transition(.opacity)
            }

            ProgressView(value: speech.match)
                .tint(Theme.accent)
                .frame(maxWidth: 200)
        }
    }

    private func unavailableNote(_ title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(detail)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.surfaceMuted, in: .rect(cornerRadius: 16))
    }

    // MARK: - Lifecycle

    private func begin() async {
        status = .idle
        hasFinished = false

        switch mission.capability {
        case .motion:
            motion.reset()
            motion.start()
            if motion.availability == .denied || motion.availability == .unsupported {
                status = .permissionDenied
            }

        case .camera:
            camera.start { data in
                Task { await check(imageData: data) }
            }

        case .speech:
            await speech.start(expecting: phrase)
            if speech.availability == .denied || speech.availability == .unsupported {
                status = .permissionDenied
            }
        }
    }

    /// Runs the photo through the verifier and drops it immediately.
    private func check(imageData: Data) async {
        guard let subject = mission.visionSubject else { return }

        guard verifier.isAvailable else {
            // A remote provider that cannot be reached must not become a wall.
            status = .offline
            return
        }

        let result = await verifier.verify(imageData: imageData, subject: subject)
        // `imageData` goes out of scope here. It was never written to disk.

        withAnimation(Theme.stateChange) { status = result.status }

        if result.status == .verified { succeed() }
    }

    private func succeed() {
        guard !hasFinished else { return }
        hasFinished = true
        status = .verified
        Haptics.commit()

        Task {
            // A beat so the confirmation is actually seen before the screen
            // changes underneath the user.
            try? await Task.sleep(for: .milliseconds(650))
            cleanUp()
            onVerified()
        }
    }

    private func dismiss() {
        cleanUp()
        onDismiss()
    }

    /// Releases every sensor and wipes anything captured.
    private func cleanUp() {
        motion.stop()
        camera.stop()
        speech.discard()
    }
}

// MARK: - Preview layer

/// A plain camera preview. No overlays, no controls — the shutter lives in
/// SwiftUI above it.
struct MissionCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
    }

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // Safe by construction: `layerClass` guarantees the type.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
