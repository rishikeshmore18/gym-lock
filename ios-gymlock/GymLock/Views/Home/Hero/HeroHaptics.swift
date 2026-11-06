//
//  HeroHaptics.swift
//  GymLock · Matrix / Ridge hero (native port)
//
//  Fires a scene's haptic cues on the same frame as its visual beats.
//
//  The web prototype keeps, per scene, a list `hap: [{t, kind}]` in scene seconds (T, seconds since
//  the card entered the state) and fires a cue on the first frame where `lastT < cue.t <= T`
//  (app13.tsx, the `hapList` effect). This file does the same against the TimelineView clock that also
//  drives the drawing, so the tap lands on the frame where the dots land.
//
//  Design:
//    - HeroHapticPlayer: owns one generator per kind, prepares them ahead, rate-limits, and maps
//      light / medium / heavy -> UIImpactFeedbackGenerator, success -> UINotificationFeedbackGenerator.
//    - HeroHapticScheduler: a cue list on one timeline. `tick(T)` is called once per drawn frame.
//      It fires cues crossed since the last tick, prepares cues coming within `lookahead`, never
//      replays stale cues (after a pause, a warm-up or a jump forward), and collapses several cues
//      crossed in one frame into the strongest one (a frame hitch must not buzz three times).
//
//  System setting: UIFeedbackGenerator already respects Settings > Sounds & Haptics > System Haptics
//  and does nothing on hardware without a Taptic Engine; `isEnabled` is the app-level switch on top.
//  Reduce Motion does not silence haptics (the web keeps them too); only flashes and shakes go.
//
//  Depends on: UIKit, CoreHaptics (capability check only).
//

import UIKit
import CoreHaptics

// MARK: - Cue types (shared with MatrixScene.swift and the Ridge port)

public enum HapticKind: String, Sendable, CaseIterable {
    case light, medium, heavy, success

    /// Order used when several cues land in one frame: the strongest wins.
    var rank: Int {
        switch self {
        case .light: return 0
        case .medium: return 1
        case .heavy: return 2
        case .success: return 3
        }
    }
}

/// One haptic on a scene's timeline: `t` in seconds since the scene (or screen) started.
public struct HapticCue: Sendable, Equatable {
    public var t: Double
    public var kind: HapticKind
    public init(t: Double, kind: HapticKind) {
        self.t = t
        self.kind = kind
    }
}

// MARK: - Player

@MainActor
public final class HeroHapticPlayer {
    public static let shared = HeroHapticPlayer()

    /// App-level switch (Profile > Preferences > haptics). The system switch is honoured by UIKit.
    public var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: HeroCardStyle.hapticsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: HeroCardStyle.hapticsKey) }
    }
    /// Spec §6.1: two different sources never land closer than this.
    public var minInterval: CFTimeInterval = 0.05
    /// Spec §6.1: at most one heavy or success from different sources inside this window.
    public var strongInterval: CFTimeInterval = 0.3

    /// Reasons the hero must stay silent right now ("alarm", "camera", "overlay", "background").
    /// Any entry blocks every hero haptic, including the done flow's taps.
    public private(set) var blockers: Set<String> = []

    public func setBlocked(_ reason: String, _ blocked: Bool) {
        if blocked { blockers.insert(reason) } else { blockers.remove(reason) }
    }

    public var isOpen: Bool { isEnabled && blockers.isEmpty }

    private var lastSource: ObjectIdentifier?
    private var lastStrongFire: CFTimeInterval = -1
    private var lastStrongSource: ObjectIdentifier?

    public let supportsHaptics: Bool = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notify = UINotificationFeedbackGenerator()
    private var lastFire: CFTimeInterval = -1
    private var lastRank = -1

    public init() {}

    /// Wake the Taptic Engine so the next cue of this kind plays without latency. Cheap; the system
    /// keeps a generator prepared for a couple of seconds.
    public func prepare(_ kind: HapticKind) {
        guard isOpen, supportsHaptics else { return }
        switch kind {
        case .light: light.prepare()
        case .medium: medium.prepare()
        case .heavy: heavy.prepare()
        case .success: notify.prepare()
        }
    }

    /// - Parameter source: the scheduler (or flow) playing. Cues from one source keep their authored
    ///   spacing (the seal is heavy, heavy, success inside 160 ms); the gaps apply between sources.
    public func play(_ kind: HapticKind, source: ObjectIdentifier? = nil, now: CFTimeInterval = CACurrentMediaTime()) {
        guard isOpen, supportsHaptics else { return }
        let otherSource = source == nil || source != lastSource
        if lastFire >= 0, now - lastFire < (otherSource ? minInterval : 0.03), kind.rank <= lastRank, kind != .success { return }
        let strong = kind == .heavy || kind == .success
        if strong, lastStrongFire >= 0, now - lastStrongFire < strongInterval, source == nil || source != lastStrongSource { return }
        lastFire = now
        lastRank = kind.rank
        lastSource = source
        if strong {
            lastStrongFire = now
            lastStrongSource = source
        }
        switch kind {
        case .light: light.impactOccurred()
        case .medium: medium.impactOccurred()
        case .heavy: heavy.impactOccurred()
        case .success: notify.notificationOccurred(.success)
        }
    }
}

// MARK: - Policy (spec §6.1)

enum HeroHapticPolicy {
    /// Moments whose card scene may play a `.success`: the proof (verified), week kept, automatic.
    /// The seal inside the done flow is the fourth, and plays from the flow itself.
    static func allowsSuccess(_ m: MatrixMoment) -> Bool {
        m == .verified || m == .weekkept || m == .automatic
    }
}

// MARK: - Scheduler

@MainActor
public final class HeroHapticScheduler {
    private var cues: [HapticCue] = []
    private var lastT: Double = -1
    private let player: HeroHapticPlayer

    /// Cues crossed more than this long ago (seconds of timeline) are skipped, not replayed.
    public var staleWindow: Double = 0.12
    /// How far ahead generators are prepared.
    public var lookahead: Double = 0.15
    /// Off while the host is not the frontmost owner of haptics (e.g. the card under the done flow).
    public var isActive = true
    /// Spec §6.1: `.success` belongs to the proof, the seal, week kept and automatic. Elsewhere a
    /// success cue plays as heavy.
    public var allowsSuccess = true

    public init(player: HeroHapticPlayer = .shared) {
        self.player = player
    }

    /// Replace the cue list (a new state, day or done screen) and restart the timeline at `T`.
    /// Like the web, cues at exactly `T` are still due on the next tick (`lastT < t`).
    public func reset(cues: [HapticCue], at T: Double = 0) {
        self.cues = cues.sorted { $0.t < $1.t }
        lastT = T - 1e-9
    }

    /// Add a one-off cue on the same timeline (e.g. the seal's heavy, heavy +70 ms, success +160 ms).
    public func add(_ cue: HapticCue) {
        let i = cues.firstIndex { $0.t > cue.t } ?? cues.count
        cues.insert(cue, at: i)
    }

    /// Call once per drawn frame with the timeline value the frame was drawn for.
    public func tick(_ T: Double) {
        defer { lastT = T }
        guard isActive else { return }
        if T < lastT { return } // the timeline restarted; `reset` sets the new origin
        var strongest: HapticKind?
        for cue in cues {
            if cue.t > T { break }
            guard cue.t > lastT else { continue }
            if T - cue.t > staleWindow { continue }
            if let s = strongest, s.rank >= cue.kind.rank { continue }
            strongest = cue.kind
        }
        for cue in cues where cue.t > T {
            if cue.t - T > lookahead { break }
            player.prepare(cue.kind)
        }
        if let k = strongest { player.play(mapped(k), source: ObjectIdentifier(self)) }
    }

    /// Play now, outside the schedule (taps on the done flow).
    public func playNow(_ kind: HapticKind) {
        guard isActive else { return }
        player.play(mapped(kind), source: ObjectIdentifier(self))
    }

    private func mapped(_ k: HapticKind) -> HapticKind {
        k == .success && !allowsSuccess ? .heavy : k
    }
}
