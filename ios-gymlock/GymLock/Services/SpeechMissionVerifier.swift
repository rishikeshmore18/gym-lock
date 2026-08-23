import AVFoundation
import Observation
import Speech

/// Listens for the mirror phrase being read out loud.
///
/// This mission is verified by speech rather than by a photo, and the reason is
/// worth stating plainly: a mirror selfie proves someone stood in front of a
/// mirror. It proves nothing about whether they read the sentence, which is the
/// part that actually does the work. Speech is the only honest check here.
///
/// Nothing is kept. Recognition runs on-device where the phone supports it, the
/// audio is never written to a file, and the transcript is discarded the moment
/// the mission completes or is abandoned.
@Observable
@MainActor
final class SpeechMissionVerifier {
    enum Availability: Equatable {
        case unknown
        case ready
        case denied
        case unsupported
    }

    private(set) var availability: Availability = .unknown
    private(set) var isListening = false
    /// Live transcript, shown so the user can see they are being heard.
    /// Held in memory only.
    private(set) var transcript = ""
    /// 0...1 share of the expected phrase matched so far.
    private(set) var match: Double = 0
    private(set) var didMatch = false

    private let recogniser = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var expectedTokens: Set<String> = []

    /// Share of the phrase's words that must be heard. Not 100%: people mumble,
    /// swallow small words, and read at a slant, and failing them for that would
    /// be pedantry dressed up as verification.
    private static let requiredMatch: Double = 0.6

    var canVerify: Bool { availability == .ready }

    // MARK: - Permissions

    func refreshAvailability() async {
        guard recogniser?.isAvailable == true else {
            availability = .unsupported
            return
        }

        let speech = SFSpeechRecognizer.authorizationStatus()
        let audio = AVAudioApplication.shared.recordPermission

        switch (speech, audio) {
        case (.denied, _), (.restricted, _), (_, .denied):
            availability = .denied
        case (.authorized, .granted):
            availability = .ready
        default:
            availability = .ready
        }
    }

    /// Asks for both permissions this mission needs, up front.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        let micGranted = await AVAudioApplication.requestRecordPermission()

        let granted = speechGranted && micGranted
        availability = granted ? .ready : .denied
        return granted
    }

    // MARK: - Listening

    func start(expecting phrase: String) async {
        guard !isListening else { return }
        guard await requestAuthorization() else { return }
        guard let recogniser, recogniser.isAvailable else {
            availability = .unsupported
            return
        }

        expectedTokens = Self.tokens(in: phrase)
        transcript = ""
        match = 0
        didMatch = false

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Keeps the audio on the phone when the hardware can manage it.
        if recogniser.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        do {
            try configureAudioSession()

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            engine.prepare()
            try engine.start()
            isListening = true

            task = recogniser.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.consume(result.bestTranscription.formattedString)
                    }
                    if error != nil, !self.didMatch {
                        self.stop()
                    }
                }
            }
        } catch {
            availability = .unsupported
            stop()
        }
    }

    func stop() {
        task?.cancel()
        task = nil

        request?.endAudio()
        request = nil

        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        isListening = false

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    /// Wipes everything heard. Called when the mission ends, whatever the
    /// outcome.
    func discard() {
        stop()
        transcript = ""
        match = 0
        didMatch = false
        expectedTokens = []
    }

    // MARK: - Private

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func consume(_ heard: String) {
        transcript = heard

        let spoken = Self.tokens(in: heard)
        guard !expectedTokens.isEmpty else { return }

        let hits = expectedTokens.intersection(spoken).count
        match = Double(hits) / Double(expectedTokens.count)

        if match >= Self.requiredMatch, !didMatch {
            didMatch = true
            Haptics.commit()
            stop()
        }
    }

    /// Comparable words: lowercased, stripped of punctuation, and with the very
    /// short filler words dropped so "I" and "to" cannot carry a match.
    private static func tokens(in phrase: String) -> Set<String> {
        let cleaned = phrase.lowercased().map { character -> Character in
            character.isLetter || character.isNumber || character.isWhitespace ? character : " "
        }

        return Set(
            String(cleaned)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count > 2 }
        )
    }
}
