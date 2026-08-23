import Foundation
import Vision

/// On-device mission verification using Apple's Vision framework.
///
/// Chosen over a remote model for one reason that matters at 6:30 in the
/// morning: it works with no signal. It also means the photo never leaves the
/// phone, which makes the "mission images are ephemeral" promise something the
/// architecture enforces rather than something the app asks to be trusted on.
///
/// The thresholds below are forgiving on purpose. A hurried, badly lit photo of
/// a trainer on a dark floor is the normal case, not the exception, and the cost
/// of a false `uncertain` is a user standing in their hallway being told to try
/// again — which is exactly the friction this whole flow exists to remove.
final class VisionMissionVerifier: MissionVerificationProviding {
    let isAvailable = true

    /// Minimum classification confidence for a match to count.
    private static let matchThreshold: Double = 0.12
    /// Minimum confidence for the person check on "shoes on".
    private static let personThreshold: Float = 0.35

    func verify(imageData: Data, subject: VisionSubject) async -> MissionVerificationResult {
        await withCheckedContinuation { continuation in
            // Vision is CPU-heavy and must not block the main actor, which is
            // where the mission UI is animating a progress ring.
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Self.classify(imageData: imageData, subject: subject)
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Private

    private nonisolated static func classify(
        imageData: Data,
        subject: VisionSubject
    ) -> MissionVerificationResult {
        let handler = VNImageRequestHandler(data: imageData, options: [:])
        let request = VNClassifyImageRequest()

        do {
            try handler.perform([request])
        } catch {
            return MissionVerificationResult(
                status: .uncertain("couldn't read that photo."),
                confidence: 0
            )
        }

        guard let observations = request.results else {
            return MissionVerificationResult(
                status: .uncertain("couldn't read that photo."),
                confidence: 0
            )
        }

        let wanted = Set(subject.identifiers)
        let best = observations
            .filter { wanted.contains($0.identifier) }
            .map { Double($0.confidence) }
            .max() ?? 0

        guard best >= matchThreshold else {
            return MissionVerificationResult(
                status: .uncertain("couldn't verify that photo."),
                confidence: best
            )
        }

        // "Shoes on" additionally wants a person in frame. This is a rectangle
        // detector, not a face matcher — GymLock never works out *who* it is,
        // only that somebody is there.
        if subject.requiresPerson, !containsPerson(handler: handler) {
            return MissionVerificationResult(
                status: .uncertain("i can see the shoes — try to get your feet in frame."),
                confidence: best
            )
        }

        return MissionVerificationResult(status: .verified, confidence: best)
    }

    private nonisolated static func containsPerson(handler: VNImageRequestHandler) -> Bool {
        let bodies = VNDetectHumanRectanglesRequest()
        bodies.upperBodyOnly = false

        // A photo of your own feet rarely contains a recognisable body, so a
        // detected foot or leg pose counts too.
        let pose = VNDetectHumanBodyPoseRequest()

        try? handler.perform([bodies, pose])

        let hasBody = (bodies.results ?? []).contains { $0.confidence >= personThreshold }
        let hasPose = !(pose.results ?? []).isEmpty
        return hasBody || hasPose
    }
}
