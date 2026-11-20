import AVFoundation
import SwiftUI

/// Runs one mission to completion.
///
/// The three kinds of mission are genuinely different interactions, so each has its own page: a
/// full-bleed camera (`MissionCameraStage`), a step counter (`MissionStepsStage`) and a spoken line
/// (`MissionSpeechStage`). This view owns the state and the rules, and the pages only draw it:
///
/// - **The image never lands on disk.** Photo missions hand the JPEG straight to the verifier and
///   drop the reference. There is no code path from here into Day 0, progress, or any gallery.
/// - **Nothing spoken is kept.** The transcript exists while it is being matched and is discarded
///   on exit, whatever the outcome.
/// - **Uncertain is not failure.** A photo the app cannot read is a statement about the photo. The
///   copy is gentle, and it counts toward the swap, never against the person.
/// - **Swap is earned, and nobody is trapped.** "Try a different one" appears after two failed
///   attempts on the same mission (a camera miss, a speech line not heard in 30 s, 45 s without a
///   step), counted in `MissionAttemptLedger`. It appears at once when the mission cannot run at
///   all (permission denied, no camera, motion or speech unsupported).
/// - **The door is steps, then a photo.** 30 steps, then "Show me the open door." If the camera
///   cannot verify on this device, the door completes after the steps: it stays the universal
///   fallback that needs only the pedometer.
struct MissionRunnerView: View {
    /// The mission the runner opened with. The runner follows its own `active` mission after an
    /// earned swap, and reports the swap through `onAnotherMission`.
    let mission: ActivationMissionType
    let phrase: String
    let camera: MissionCameraModel
    let motion: MotionMissionMonitor
    let speech: SpeechMissionVerifier
    /// Counts failed attempts across relaunches. Nil counts for this run only.
    let sessionID: UUID?
    /// Every mission the device can verify. The runner offers the ones other than the active one.
    let swapChoices: [ActivationMissionType]
    let onVerified: () -> Void
    /// The user picked a different mission from the earned swap sheet. The runner stays open and
    /// starts it; the caller only has to record the choice (`onChoose`).
    let onAnotherMission: (ActivationMissionType) -> Void
    let onDismiss: () -> Void

    private enum Stage: Hashable { case steps, photo, speech }
    private struct RunKey: Hashable {
        let mission: ActivationMissionType
        let stage: Stage
    }
    private struct AimKey: Hashable {
        let token: Int
        let mission: ActivationMissionType
        let stage: Stage
    }

    /// No steps for this long counts as one failed attempt.
    private static let stepsPatience: TimeInterval = 45
    /// A spoken line not matched within this many seconds counts as one failed attempt.
    private static let speechWindow = 30

    @AppStorage(HeroCardStyle.storageKey) private var cardStyleRaw = HeroCardStyle.default.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var active: ActivationMissionType
    @State private var stage: Stage
    @State private var verifier: any MissionVerificationProviding = VisionMissionVerifier()
    @State private var hasFinished = false
    @State private var phase: MissionCameraPhase = .aim
    @State private var pillNote: String?
    @State private var isFlashing = false
    @State private var isTorchOn = false
    @State private var failures: Int
    @State private var isVerifierOffline = false
    @State private var aimToken = 0
    @State private var pulse = 0
    @State private var stepNote: String?
    @State private var speechNote: String?
    @State private var speechStarted = false
    @State private var isSwapOpen = false
    @State private var settleDelay = false

    init(
        mission: ActivationMissionType,
        phrase: String,
        camera: MissionCameraModel,
        motion: MotionMissionMonitor,
        speech: SpeechMissionVerifier,
        sessionID: UUID? = nil,
        swapChoices: [ActivationMissionType] = [],
        onVerified: @escaping () -> Void,
        onAnotherMission: @escaping (ActivationMissionType) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.mission = mission
        self.phrase = phrase
        self.camera = camera
        self.motion = motion
        self.speech = speech
        self.sessionID = sessionID
        self.swapChoices = swapChoices
        self.onVerified = onVerified
        self.onAnotherMission = onAnotherMission
        self.onDismiss = onDismiss
        _active = State(initialValue: mission)
        _stage = State(initialValue: Self.firstStage(for: mission))
        _failures = State(
            initialValue: sessionID.map { MissionAttemptLedger.failures(sessionID: $0, mission: mission) } ?? 0
        )
    }

    private static func firstStage(for mission: ActivationMissionType) -> Stage {
        switch mission.capability {
        case .motion: .steps
        case .camera: .photo
        case .speech: .speech
        }
    }

    private var style: MissionStyle {
        MissionStyle(HeroCardStyle(rawValue: cardStyleRaw) ?? .default)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            switch stage {
            case .photo: cameraStage.transition(.opacity)
            case .steps: stepsStage.transition(.opacity)
            case .speech: speechStage.transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: stage)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .sheet(isPresented: $isSwapOpen) {
            MissionSwapSheet(
                missions: swapOptions,
                style: style,
                onPick: { picked in
                    isSwapOpen = false
                    switchMission(to: picked)
                }
            )
        }
        .task(id: RunKey(mission: active, stage: stage)) { await begin() }
        .task(id: AimKey(token: aimToken, mission: active, stage: stage)) { await watchAim() }
        .onChange(of: motion.steps) { old, new in stepsChanged(from: old, to: new) }
        .onChange(of: speech.didMatch) { _, matched in
            guard matched, stage == .speech else { return }
            succeed()
        }
        .onChange(of: speech.transcript) { _, _ in speechNote = nil }
        .onChange(of: camera.availability) { _, new in cameraAvailabilityChanged(new) }
        .onDisappear { cleanUp() }
    }

    // MARK: - Pages

    private var cameraStage: some View {
        let header = MissionCopy.cameraHeader(for: active)
        let isReady = camera.availability == .ready
        return MissionCameraStage(
            style: style,
            figure: MissionFigure(active),
            title: header.title,
            subtitle: header.subtitle,
            phase: phase,
            pillText: pillText,
            previewSession: isReady ? camera.session : nil,
            notice: cameraNotice,
            isFlashing: isFlashing,
            canTakePhoto: isReady && !hasFinished && (phase == .aim || phase == .found),
            showsLight: isReady && torchDevice != nil,
            isTorchOn: isTorchOn,
            canSwap: canSwap,
            onClose: closeRunner,
            onShutter: shutter,
            onLight: toggleTorch,
            onSwap: { isSwapOpen = true }
        )
    }

    private var stepsStage: some View {
        MissionStepsStage(
            style: style,
            figure: MissionFigure(active),
            count: motion.steps,
            target: active.stepTarget ?? 20,
            pulseToken: pulse,
            isDone: hasFinished,
            note: stepNote ?? (active.visionSubject != nil ? "Then one photo of the open door." : nil),
            notice: stepsNotice,
            canSwap: canSwap,
            onClose: closeRunner,
            onSwap: { isSwapOpen = true }
        )
    }

    private var speechStage: some View {
        MissionSpeechStage(
            style: style,
            figure: MissionFigure(active),
            phrase: phrase,
            match: speech.match,
            isListening: speech.isListening,
            statusText: speechStatus,
            transcript: speech.transcript,
            isDone: hasFinished,
            note: speechNote,
            notice: speechNotice,
            canSwap: canSwap,
            onClose: closeRunner,
            onSwap: { isSwapOpen = true },
            onMic: restartListening
        )
    }

    // MARK: - Derived state

    private var swapOptions: [ActivationMissionType] {
        swapChoices.filter { $0 != active }
    }

    /// The mission cannot run at all on this phone right now (so the swap is offered at once).
    private var cannotRun: Bool {
        switch stage {
        case .steps:
            return motion.availability == .denied || motion.availability == .unsupported
        case .photo:
            return isVerifierOffline || isCameraBlocked
        case .speech:
            return speech.availability == .denied || speech.availability == .unsupported
        }
    }

    private var isCameraBlocked: Bool {
        switch camera.availability {
        case .permissionDenied, .noCameraFound, .failed: true
        case .preparing, .ready: false
        }
    }

    /// "Try a different one" is earned: two failed attempts on this mission, or it cannot run.
    private var canSwap: Bool {
        guard !hasFinished, !swapOptions.isEmpty else { return false }
        return failures >= MissionAttemptLedger.failuresToEarnSwap || cannotRun
    }

    private var aimLine: String {
        active.visionSubject.map(MissionCopy.aim) ?? MissionCopy.headline(active)
    }

    private var pillText: String {
        switch phase {
        case .aim: pillNote ?? aimLine
        case .found: "In frame. Tap to check."
        case .checking: "Checking on your phone"
        case .done: "Got it."
        }
    }

    private var cameraNotice: MissionCameraNotice? {
        if isVerifierOffline {
            return MissionCameraNotice(title: "Can't check right now", detail: "Try a different one instead.")
        }
        switch camera.availability {
        case .permissionDenied:
            return MissionCameraNotice(
                title: "Camera access is off",
                detail: "You can turn it on in Settings, or try a different one."
            )
        case .noCameraFound:
            return MissionCameraNotice(title: "No camera found", detail: "Try a different one instead.")
        case let .failed(message):
            return MissionCameraNotice(title: "Camera trouble", detail: MissionCopy.sentence(message))
        case .preparing, .ready:
            return nil
        }
    }

    private var stepsNotice: MissionCameraNotice? {
        guard cannotRun else { return nil }
        return MissionCameraNotice(
            title: "Can't count steps right now",
            detail: "Motion & Fitness access may be off on this phone."
        )
    }

    private var speechNotice: MissionCameraNotice? {
        guard cannotRun else { return nil }
        return MissionCameraNotice(
            title: "Can't listen right now",
            detail: "Microphone or Speech access may be off on this phone."
        )
    }

    private var speechStatus: String {
        if speech.isListening { return "Listening" }
        return speechStarted ? "Tap the mic to listen again" : "Getting ready to listen"
    }

    // MARK: - Lifecycle

    private func begin() async {
        if settleDelay {
            // A swap just released the sensors; let them settle before the next mission starts.
            settleDelay = false
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
        }

        switch stage {
        case .steps: await runSteps()
        case .photo: startPhoto()
        case .speech: await runSpeech()
        }
    }

    /// Counts steps, and counts 45 s without one as a failed attempt.
    private func runSteps() async {
        motion.reset()
        motion.start()

        var seen = motion.steps
        var lastProgress = Date()

        while !Task.isCancelled, !hasFinished, stage == .steps {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, !hasFinished, stage == .steps else { return }
            if cannotRun { continue }

            if motion.steps > seen {
                seen = motion.steps
                lastProgress = Date()
            } else if Date().timeIntervalSince(lastProgress) >= Self.stepsPatience {
                lastProgress = Date()
                registerFailure()
                stepNote = "No steps yet. Keep walking, or try again in a moment."
            }
        }
    }

    private func stepsChanged(from old: Int, to new: Int) {
        guard stage == .steps, !hasFinished, new > old, new > 0 else { return }
        stepNote = nil
        if !reduceMotion { pulse += 1 }

        if new >= (active.stepTarget ?? 20) {
            stepsReached()
        } else {
            MissionHaptic.selection.play()
        }
    }

    /// The steps are done: a door goes on to its photo, anything else is complete. A door whose
    /// camera cannot verify on this device is complete here.
    private func stepsReached() {
        guard stage == .steps, !hasFinished else { return }
        motion.stop()

        guard active.visionSubject != nil, camera.canVerify else {
            succeed()
            return
        }

        MissionHaptic.medium.play()
        stepNote = nil
        phase = .aim
        pillNote = nil
        aimToken += 1
        stage = .photo
    }

    private func startPhoto() {
        isVerifierOffline = false
        camera.start { data in
            Task { await check(imageData: data) }
        }
    }

    /// Aiming turns into "in frame" after 2.2 s with the camera running.
    private func watchAim() async {
        guard stage == .photo, phase == .aim, !hasFinished else { return }

        while camera.availability != .ready {
            if cannotRun { return }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, stage == .photo, !hasFinished else { return }
        }

        try? await Task.sleep(for: .milliseconds(2200))
        guard !Task.isCancelled, stage == .photo, phase == .aim, !hasFinished else { return }

        withAnimation(Theme.stateChange) { phase = .found }
        pillNote = nil
        MissionHaptic.soft.play()
    }

    private func shutter() {
        guard stage == .photo, !hasFinished, camera.availability == .ready,
              phase == .aim || phase == .found
        else { return }

        MissionHaptic.rigid.play()
        isFlashing = true
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            isFlashing = false
        }

        pillNote = nil
        withAnimation(Theme.stateChange) { phase = .checking }
        camera.capture()
    }

    /// Runs the photo through the verifier and drops it immediately.
    private func check(imageData: Data) async {
        guard stage == .photo, !hasFinished, let subject = active.visionSubject else { return }

        guard verifier.isAvailable else {
            // A remote provider that cannot be reached must not become a wall.
            isVerifierOffline = true
            withAnimation(Theme.stateChange) { phase = .aim }
            return
        }

        let result = await verifier.verify(imageData: imageData, subject: subject)
        // `imageData` goes out of scope here. It was never written to disk.

        guard !hasFinished else { return }

        switch result.status {
        case .verified:
            succeed()
        case let .uncertain(message), let .failed(message):
            photoMissed(message)
        case .idle, .checking, .offline, .permissionDenied:
            photoMissed(nil)
        }
    }

    /// A miss is a statement about the photo. Gentle copy, one more attempt on the ledger, and
    /// straight back to aiming.
    private func photoMissed(_ message: String?) {
        registerFailure()
        pillNote = message.map(MissionCopy.sentence) ?? "Couldn't verify that photo."
        withAnimation(Theme.stateChange) { phase = .aim }
        aimToken += 1
    }

    /// Listens for the line, and counts 30 s without a match as a failed attempt.
    private func runSpeech() async {
        speechNote = nil

        while !Task.isCancelled, !hasFinished, stage == .speech {
            await speech.start(expecting: phrase)
            speechStarted = true
            if cannotRun { return }

            var waited = 0
            while waited < Self.speechWindow, !Task.isCancelled, !hasFinished {
                try? await Task.sleep(for: .seconds(1))
                waited += 1
            }
            guard !Task.isCancelled, !hasFinished, stage == .speech else { return }

            speech.discard()
            registerFailure()
            speechNote = "I didn't catch that. Read it once more."
        }
    }

    private func restartListening() {
        guard stage == .speech, !hasFinished, !speech.isListening else { return }
        Task {
            speech.discard()
            await speech.start(expecting: phrase)
            speechStarted = true
        }
    }

    private func cameraAvailabilityChanged(_ new: MissionCameraModel.Availability) {
        guard stage == .photo, !hasFinished else { return }

        switch new {
        case .permissionDenied, .noCameraFound, .failed:
            if phase == .checking { withAnimation(Theme.stateChange) { phase = .aim } }
            // The door only uses the camera as its second half. Without it, the steps are the
            // mission, so it completes here and never traps anyone.
            if active.capability == .motion { succeed() }
        case .preparing, .ready:
            break
        }
    }

    // MARK: - Outcomes

    private func registerFailure() {
        if let sessionID {
            failures = MissionAttemptLedger.recordFailure(sessionID: sessionID, mission: active)
        } else {
            failures += 1
        }
        MissionHaptic.warning.play()
    }

    private func succeed() {
        guard !hasFinished else { return }
        hasFinished = true
        stepNote = nil
        pillNote = nil
        // The speech verifier plays the success haptic itself when the line matches ("Haptics.commit:
        // never twice for one event"), so this one covers the other two kinds of mission.
        if stage != .speech { MissionHaptic.success.play() }
        withAnimation(Theme.settle) { phase = .done }

        Task {
            // A beat so the confirmation is actually seen before the screen changes underneath
            // the user.
            try? await Task.sleep(for: .milliseconds(1200))
            cleanUp()
            onVerified()
        }
    }

    /// The earned swap: release the sensors, start the picked mission in place, and tell the
    /// caller so it can record the choice.
    private func switchMission(to picked: ActivationMissionType) {
        cleanUp()
        hasFinished = false
        phase = .aim
        pillNote = nil
        stepNote = nil
        speechNote = nil
        isVerifierOffline = false
        speechStarted = false
        pulse = 0
        failures = sessionID.map { MissionAttemptLedger.failures(sessionID: $0, mission: picked) } ?? 0
        settleDelay = true
        aimToken += 1
        active = picked
        stage = Self.firstStage(for: picked)
        onAnotherMission(picked)
    }

    private func closeRunner() {
        cleanUp()
        onDismiss()
    }

    /// Releases every sensor and wipes anything captured.
    private func cleanUp() {
        setTorch(false)
        motion.stop()
        camera.stop()
        speech.discard()
    }

    // MARK: - Light

    private var torchDevice: AVCaptureDevice? {
        camera.session.inputs
            .compactMap { ($0 as? AVCaptureDeviceInput)?.device }
            .first { $0.hasTorch }
    }

    private func toggleTorch() {
        MissionHaptic.selection.play()
        setTorch(!isTorchOn)
    }

    private func setTorch(_ on: Bool) {
        if !on && !isTorchOn { return }
        guard let device = torchDevice else {
            isTorchOn = false
            return
        }

        let mode: AVCaptureDevice.TorchMode = on ? .on : .off
        guard device.isTorchModeSupported(mode) else { return }

        do {
            try device.lockForConfiguration()
            device.torchMode = mode
            device.unlockForConfiguration()
            isTorchOn = on
        } catch {
            isTorchOn = false
        }
    }
}

// MARK: - Preview layer

/// A plain camera preview. No overlays, no controls: the shutter lives in
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
