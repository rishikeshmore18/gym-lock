//
//  MissionCopy.swift
//  GymLock · mission screens
//
//  Sentence-case copy for the mission screens, derived from ActivationMissionType (whose own
//  strings are lower case, as the rest of the app writes them). Nothing here accuses: a photo the
//  app cannot read is a statement about the photo.
//

import Foundation

enum MissionCopy {
    /// "show your gym shoes" -> "Show your gym shoes". Only the first letter changes.
    ///
    /// The app's own strings sometimes carry an em dash (the shoes-on prompt, the verifier's "i can
    /// see the shoes, try ..." line). No em dash may reach these screens, so each one becomes a
    /// full stop and the next clause starts a new sentence.
    static func sentence(_ text: String) -> String {
        let clauses = text
            .replacingOccurrences(of: " \u{2014} ", with: "\u{2014}")
            .replacingOccurrences(of: " \u{2013} ", with: "\u{2014}")
            .split(separator: "\u{2014}", omittingEmptySubsequences: true)
            .map { capitalised(String($0).trimmingCharacters(in: .whitespaces)) }
        return clauses.joined(separator: ". ")
    }

    private static func capitalised(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// "Show your gym shoes" (camera header, no full stop).
    static func headline(_ mission: ActivationMissionType) -> String {
        sentence(mission.title)
    }

    /// "Show your gym shoes." (hero card).
    static func title(_ mission: ActivationMissionType) -> String {
        let text = sentence(mission.title)
        return text.hasSuffix(".") ? text : text + "."
    }

    /// "Point the camera at them."
    static func subtitle(_ mission: ActivationMissionType) -> String {
        sentence(mission.subtitle)
    }

    /// Short names for the swap tiles.
    static func shortTitle(_ mission: ActivationMissionType) -> String {
        switch mission {
        case .twentySteps: "20 steps"
        case .showGymShoes: "Gym shoes"
        case .shoesOn: "Shoes on"
        case .mirrorBoost: "Mirror line"
        case .grabWater: "Water bottle"
        case .gymBag: "Gym bag"
        case .walkToDoor: "Walk to the door"
        }
    }

    /// "Camera", "Motion", "Voice", or "Steps, then camera" for a mission with both parts.
    static func kind(_ mission: ActivationMissionType) -> String {
        switch mission.capability {
        case .camera: "Camera"
        case .speech: "Voice"
        case .motion: mission.visionSubject == nil ? "Motion" : "Steps, then camera"
        }
    }

    /// "Camera · 25 s"
    static func chip(_ mission: ActivationMissionType) -> String {
        "\(kind(mission)) · \(mission.estimatedSeconds) s"
    }

    /// The aiming line, from the subject's own prompt: "Point the camera at your gym shoes".
    static func aim(_ subject: VisionSubject) -> String {
        sentence(subject.prompt)
    }

    /// The camera header for the photo part of a mission.
    static func cameraHeader(for mission: ActivationMissionType) -> (title: String, subtitle: String) {
        if mission.capability == .motion, let subject = mission.visionSubject {
            // The door: the steps are done, one photo is left.
            return (sentence(subject.prompt), "Steps done. One photo left.")
        }
        return (headline(mission), subtitle(mission))
    }
}
