//
//  CantTodayNudger.swift
//  GymLock · the "can't today" screen (three looks)
//
//  The "this is interactive" wave. A pure, time-based state machine: nothing here owns a timer.
//  The look calls `amount(_:at:)` every frame from its TimelineView and maps the 0...1...0
//  envelope to its own movement (peek, drift, lift, glow).
//
//    - items are named by id, ordered top to bottom; each starts 140 ms after the previous
//    - the first wave starts 0.35 s after `settle(at:)`
//    - a wave repeats once after 3 s of idle: two waves for the whole screen, then it stays still
//    - a kind stops nudging for good once the user touched it
//    - `cancel()` stops everything at once; `rest(at:)` restarts the idle clock
//    - haptics: .light at each peak, .soft at the last peak of the wave, one cue id per wave and item
//

import Foundation

@MainActor
final class CantTodayNudger {
    private let haptics: PauseHaptics
    private let reduceMotion: Bool

    private var ids: [String] = []
    private var kindOf: [String: String] = [:]
    private var touchedKinds: Set<String> = []

    private var waveItems: [String] = []
    private var waveStart: Double?
    private var waveLength: Double = 0
    private var nextStart: Double?
    private var wavesRun = 0
    private var waveSerial = 0        // never reset, so haptic cue ids stay unique for the life of the screen

    private let stagger = 0.14
    private let envelopeLength = 0.6
    private let firstDelay = 0.35
    private let idleGap = 3.0
    private let maxWaves = 2          // the first wave plus one repeat, for the life of the screen

    init(haptics: PauseHaptics, reduceMotion: Bool) {
        self.haptics = haptics
        self.reduceMotion = reduceMotion
    }

    /// True while a wave is playing or one is scheduled (keep the timeline running).
    var isRunning: Bool { waveStart != nil || nextStart != nil }

    func setItems(_ ids: [String], kinds: [String: String]) {
        self.ids = ids
        self.kindOf = kinds
        if waveStart == nil, nextStart != nil, eligibleIds().isEmpty { nextStart = nil }
    }

    func settle(at time: Double) {
        // The two waves are for the whole screen, not per step: a new step does not start more.
        waveStart = nil
        waveItems = []
        nextStart = (wavesRun >= maxWaves || eligibleIds().isEmpty) ? nil : time + firstDelay
    }

    func touched(kind: String) {
        touchedKinds.insert(kind)
        if waveStart == nil, eligibleIds().isEmpty { nextStart = nil }
    }

    func cancel() {
        waveStart = nil
        waveItems = []
        nextStart = nil
    }

    func rest(at time: Double) {
        guard wavesRun < maxWaves, !eligibleIds().isEmpty else {
            nextStart = nil
            return
        }
        nextStart = time + idleGap
    }

    /// 0 outside the wave; inside it an envelope that rises to 1 (about 12% overshoot), settles and returns to 0.
    func amount(_ id: String, at time: Double) -> Double {
        advance(to: time)
        guard let start = waveStart,
              !isTouched(id),
              let index = waveItems.firstIndex(of: id) else { return 0 }
        let u = (time - start - Double(index) * stagger) / envelopeLength
        guard u >= 0, u < 1 else { return 0 }
        if u >= 0.5 {
            let last = index == waveItems.count - 1
            haptics.cue("cant-nudge-\(waveSerial)-\(index)", last ? .soft : .light)
        }
        return envelope(u)
    }

    // MARK: Private

    private func kind(of id: String) -> String { kindOf[id] ?? id }

    private func isTouched(_ id: String) -> Bool { touchedKinds.contains(kind(of: id)) }

    private func eligibleIds() -> [String] { ids.filter { !isTouched($0) } }

    private func envelope(_ u: Double) -> Double {
        let raw = sin(Double.pi * u) - 0.15 * sin(2 * Double.pi * u)   // peaks near 1.04
        return max(0, raw * 1.078)                                      // main peak about 1.12
    }

    private func advance(to time: Double) {
        if let start = waveStart, time >= start + waveLength {
            waveStart = nil
            waveItems = []
            if wavesRun < maxWaves, !eligibleIds().isEmpty {
                nextStart = start + waveLength + idleGap
            } else {
                nextStart = nil
            }
        }
        if waveStart == nil, let due = nextStart, time >= due {
            let items = eligibleIds()
            guard !items.isEmpty else {
                nextStart = nil
                return
            }
            waveItems = items
            waveStart = time
            waveLength = Double(items.count - 1) * stagger + envelopeLength + 0.05
            wavesRun += 1
            waveSerial += 1
            nextStart = nil
        }
    }
}
