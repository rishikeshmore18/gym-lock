import Foundation

/// The result of looking at one mission photo.
struct MissionVerificationResult: Equatable {
    var status: MissionVerificationStatus
    /// Best-guess confidence, only ever used for internal thresholds.
    var confidence: Double
}

/// How a mission photo gets checked.
///
/// Deliberately a protocol with no vendor in its name. Today this is Apple's
/// on-device Vision, which means the flow keeps working on a train with no
/// signal. If a remote multimodal model is added later it slots in behind this
/// same call, and no SwiftUI view has to learn about it.
///
/// Two rules any implementation must honour:
///
/// 1. **The image is ephemeral.** It exists in memory for the length of the
///    check and is never written to disk, never added to Day 0, and never
///    appears in a gallery.
/// 2. **Uncertainty is not accusation.** A check that cannot tell returns
///    `uncertain`, and the UI built on it offers another go or another mission.
protocol MissionVerificationProviding: Sendable {
    /// Whether this provider can run right now — a remote one would report
    /// `false` with no network, so mission selection can route around it.
    var isAvailable: Bool { get }

    /// Inspects the image data for the requested subject.
    func verify(imageData: Data, subject: VisionSubject) async -> MissionVerificationResult
}

// MARK: - Secrets

/// Where a remote verifier would get its credentials.
///
/// Nothing is embedded in the binary. A key shipped inside an app is a key that
/// has been given away, so the only supported shape is a backend that holds the
/// credential and exposes a narrow endpoint. Until that exists, the local Vision
/// provider is used and this returns nil.
enum MissionVerificationBackend {
    /// Base URL of a proxy that performs verification server-side.
    ///
    /// Read from the build configuration rather than hard-coded, and absent by
    /// default.
    static var proxyURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "GymLockVerificationProxyURL") as? String,
              !raw.isEmpty
        else { return nil }
        return URL(string: raw)
    }

    static var hasRemoteProvider: Bool { proxyURL != nil }
}
