import Foundation

/// What a mission needs from the device before it can honestly be offered.
///
/// A mission the app cannot verify is worse than no mission at all: it either
/// traps the user on a screen that will never complete, or it quietly accepts
/// anything and teaches them the check is theatre. Selection therefore filters
/// on this first.
enum MissionCapability: String, Codable, Hashable, CaseIterable {
    case motion
    case camera
    case speech

    var label: String {
        switch self {
        case .motion: "Motion & Fitness"
        case .camera: "Camera"
        case .speech: "Speech Recognition"
        }
    }
}

/// One tiny physical action that breaks inertia.
///
/// Missions are deliberately 20–60 seconds. The point is not exercise, it is
/// getting the body out of the position it was arguing from.
enum ActivationMissionType: String, Codable, Hashable, CaseIterable, Identifiable {
    case twentySteps
    case showGymShoes
    case shoesOn
    case mirrorBoost
    case grabWater
    case gymBag
    case walkToDoor

    var id: String { rawValue }

    var capability: MissionCapability {
        switch self {
        case .twentySteps, .walkToDoor: .motion
        case .showGymShoes, .shoesOn, .grabWater, .gymBag: .camera
        case .mirrorBoost: .speech
        }
    }

    var title: String {
        switch self {
        case .twentySteps: "take 20 steps"
        case .showGymShoes: "show your gym shoes"
        case .shoesOn: "put your shoes on"
        case .mirrorBoost: "go to a mirror"
        case .grabWater: "grab your water"
        case .gymBag: "grab your gym bag"
        case .walkToDoor: "walk toward the door"
        }
    }

    var subtitle: String {
        switch self {
        case .twentySteps: "get your body moving."
        case .showGymShoes: "point the camera at them."
        case .shoesOn: "then show me your feet."
        case .mirrorBoost: "read one line out loud."
        case .grabWater: "show me the bottle."
        case .gymBag: "show me the bag."
        case .walkToDoor: "30 more steps, that direction."
        }
    }

    var icon: String {
        switch self {
        case .twentySteps: "figure.walk"
        case .showGymShoes, .shoesOn: "shoe.2"
        case .mirrorBoost: "quote.bubble.fill"
        case .grabWater: "waterbottle.fill"
        case .gymBag: "bag.fill"
        case .walkToDoor: "door.left.hand.open"
        }
    }

    /// Roughly how long this takes, shown so the ask feels small.
    var estimatedSeconds: Int {
        switch self {
        case .twentySteps: 30
        case .walkToDoor: 45
        case .showGymShoes, .grabWater, .gymBag: 25
        case .shoesOn: 45
        case .mirrorBoost: 40
        }
    }

    /// Steps required, for the movement missions.
    var stepTarget: Int? {
        switch self {
        case .twentySteps: 20
        case .walkToDoor: 30
        default: nil
        }
    }

    /// What Vision is being asked to find, for the camera missions.
    var visionSubject: VisionSubject? {
        switch self {
        case .showGymShoes: .athleticShoes
        case .shoesOn: .athleticShoesWorn
        case .grabWater: .waterBottle
        case .gymBag: .gymBag
        default: nil
        }
    }

    /// Missions that assume the user owns a particular thing are only offered
    /// when there is a reason to think they do.
    var requiresOwnership: Bool { self == .gymBag }

    /// The always-available fallback: needs no camera, no speech, and no
    /// equipment.
    static let universalFallback: ActivationMissionType = .walkToDoor

    /// One short sentence to read out loud, rotated per attempt.
    static let mirrorPhrases: [String] = [
        "I don't have to feel ready. I just have to start.",
        "One decision. Then momentum.",
        "My job is not to want it. My job is to move.",
        "Future me gets built by what I do next.",
    ]
}

/// What the vision verifier is looking for.
enum VisionSubject: String, Codable, Hashable {
    case athleticShoes
    case athleticShoesWorn
    case waterBottle
    case gymBag

    /// Classification identifiers that count as a match. These are drawn from
    /// the built-in Vision taxonomy, which is broad enough to be forgiving of a
    /// hurried photo taken in bad morning light.
    var identifiers: [String] {
        switch self {
        case .athleticShoes, .athleticShoesWorn:
            ["running_shoe", "sneaker", "shoe", "footwear", "clog", "sandal", "boot"]
        case .waterBottle:
            ["water_bottle", "bottle", "drinking_vessel", "thermos", "flask", "cup", "tumbler"]
        case .gymBag:
            ["backpack", "bag", "duffel_bag", "tote_bag", "luggage", "handbag", "suitcase"]
        }
    }

    /// Whether a person also has to be in frame. Used only for "shoes on", and
    /// only as a rectangle detection — GymLock never identifies who it is.
    var requiresPerson: Bool { self == .athleticShoesWorn }

    var prompt: String {
        switch self {
        case .athleticShoes: "point the camera at your gym shoes"
        case .athleticShoesWorn: "shoes on — show me your feet"
        case .waterBottle: "show me your water bottle"
        case .gymBag: "show me your gym bag"
        }
    }
}

// MARK: - Selection

extension ActivationMissionType {
    /// Picks the next mission.
    ///
    /// Three rules, in order: never offer something the device cannot verify,
    /// never repeat the previous mission, and never leave the pool empty. If
    /// filtering removes everything, the motion fallback is returned regardless
    /// so the user is never stuck on a screen with nothing to do.
    static func next(
        available capabilities: Set<MissionCapability>,
        excluding previous: ActivationMissionType?,
        allowingOwnershipMissions ownership: Bool,
        randomSource: () -> Int = { Int.random(in: 0..<Int.max) }
    ) -> ActivationMissionType? {
        let pool = candidates(
            available: capabilities,
            excluding: previous,
            allowingOwnershipMissions: ownership
        )
        guard !pool.isEmpty else { return nil }
        return pool[randomSource() % pool.count]
    }

    /// Every mission that could honestly be offered right now.
    static func candidates(
        available capabilities: Set<MissionCapability>,
        excluding previous: ActivationMissionType?,
        allowingOwnershipMissions ownership: Bool
    ) -> [ActivationMissionType] {
        let verifiable = allCases.filter { mission in
            guard capabilities.contains(mission.capability) else { return false }
            if mission.requiresOwnership && !ownership { return false }
            return true
        }

        // Dropping the previous mission is only allowed while something else
        // remains — a single-capability device should still get a mission.
        let withoutRepeat = verifiable.filter { $0 != previous }
        return withoutRepeat.isEmpty ? verifiable : withoutRepeat
    }
}

// MARK: - Verification status

/// Where a mission attempt currently stands.
///
/// `uncertain` is deliberately distinct from `failed`: the app could not tell,
/// which is a statement about the photo, not about the user. Nothing in the UI
/// built on this may imply cheating.
enum MissionVerificationStatus: Equatable {
    case idle
    case checking
    case verified
    case uncertain(String)
    case failed(String)
    case offline
    case permissionDenied

    var isTerminalSuccess: Bool { self == .verified }

    var isBusy: Bool { self == .checking }
}
