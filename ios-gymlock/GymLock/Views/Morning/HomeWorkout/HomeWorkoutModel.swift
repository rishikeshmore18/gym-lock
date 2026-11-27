//
//  HomeWorkoutModel.swift
//  GymLock · the home workout (setup + count-up timer), four looks
//
//  The contract every look reads. Nothing here draws. Everything is real app state (PauseFacts)
//  or pure maths on the elapsed time, so a look is a function of (input, elapsed, ages) and a
//  resumed app lands on the right frame without replaying a beat.
//
//  Rules (FLOW, Flow 4, and the research behind the redesign):
//    - 20 minutes is the minimum that counts. There is no upper limit: the timer counts UP.
//    - At 20:00 the apps unlock, "finish" appears, and the timer keeps running ("+N min").
//    - Checkpoints at 5, 10, 15 and 20 (each a short beat), then "+5." every 5 minutes after.
//    - The small label shows minutes done before 10:00 and minutes left from 10:00 (the
//      "stuck in the middle" fix: always show the smaller of the two).
//
//  Approved prototype: docs/prototypes/home-workout-variations.html
//

import SwiftUI

// MARK: - Which look

/// The four approved looks. Ridge style alternates ascent / sunrise, Matrix style alternates
/// swarm / stack, one per home workout, so the same one never shows twice in a row.
enum HomeWorkoutLook: String, CaseIterable, Sendable {
    case ridgeAscent
    case ridgeSunrise
    case matrixSwarm
    case matrixStack

    /// Ridge looks are dark painted scenes (white button, white text). Matrix looks are light.
    var isDark: Bool { self == .ridgeAscent || self == .ridgeSunrise }

    /// Persisted rotation counter, bumped once per started home workout.
    static let rotationKey = "gymlock.homeWorkout.lookRotation"

    static func pick(style: HeroCardStyle, rotation: Int) -> HomeWorkoutLook {
        let even = rotation % 2 == 0
        switch style {
        case .ridge: return even ? .ridgeAscent : .ridgeSunrise
        case .matrix: return even ? .matrixSwarm : .matrixStack
        }
    }
}

// MARK: - Facts (real data only)

struct HomeWorkoutFacts: Equatable {
    /// Current streak in weeks. 0 hides every streak element.
    let streakWeeks: Int
    /// Counted days this week before today's home workout.
    let weekDone: Int
    /// This week's goal (planned days, minimum 3).
    let weekGoal: Int
    /// This week, Monday first. `.today` marks the session's day.
    let week: [PauseWeekDay]
    /// Home workouts left this month after this one is not yet counted (0...3).
    let homeLeft: Int
    /// Apple Health can be read, so it is the check. Otherwise a photo is.
    let healthUsable: Bool

    /// The week count once today counts.
    var weekAfter: Int { min(weekGoal, weekDone + 1) }
    /// Today completes the week's goal.
    var keepsWeek: Bool { weekDone + 1 >= weekGoal }
    var todayIndex: Int? { week.firstIndex { $0.state == .today } }
}

// MARK: - Copy (lowercase, no em dashes)

enum HomeWorkoutCopy {
    static let start = "start"
    static let finish = "finish"
    static let end = "end"
    static let sub = "20 min counts. go longer if you want."
    static let finishHint = "apps unlocked. finish when you want."

    static func streak(_ weeks: Int) -> String { "\(weeks) week streak" }

    static func stake(_ f: HomeWorkoutFacts) -> String {
        f.keepsWeek ? "today keeps your week." : "today makes it \(f.weekAfter) of \(f.weekGoal) this week."
    }

    static func check(_ f: HomeWorkoutFacts) -> String {
        f.healthUsable ? "apple health checks it when you finish." : "no watch? a photo after 20 min counts it."
    }

    static func quota(_ f: HomeWorkoutFacts) -> String { "\(f.homeLeft) of 3 home workouts left this month." }

    /// The big 20:00 result used by the stack look.
    static func weekResult(_ f: HomeWorkoutFacts) -> String {
        f.keepsWeek ? "week kept." : "\(f.weekAfter) of \(f.weekGoal)."
    }

    // End sheet (before 20:00 only).
    static let endTitle = "end now?"
    static let endMessage = "it won't count before 20 min."
    static let keepGoing = "keep going"
    static let endWithout = "end without counting"

    // Back sheet (after the first minute, before 20:00 only).
    static let backTitle = "go back?"
    static let backMessage = "your timer starts over."
    static let stay = "stay"
    static let goBack = "go back"
}

// MARK: - The clock (pure)

enum HomeWorkoutClock {
    /// 20 minutes, in seconds. Same number as FLOW and the gym's minimum.
    static let minimum: Double = Double(HomeWorkoutRules.defaultMinutes * 60)
    static let checkpoints: [Double] = [300, 600, 900, 1200]
    static let beatDuration: Double = 1.6
    static let bigMomentDuration: Double = 2.5

    static func isDone(_ e: Double) -> Bool { e >= minimum }

    /// "07:42". Minutes keep growing past 59 ("63:10").
    static func format(_ e: Double) -> String {
        let s = max(0, Int(e.rounded(.down)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// The small label under the clock (the small-area flip at 10:00).
    static func label(_ e: Double) -> String {
        if e >= minimum { return e < minimum + 60 ? "apps unlocked." : "+\(Int((e - minimum) / 60)) min" }
        if e < 600 { return "\(Int(e / 60)) min in" }
        if e >= minimum - 60 { return "under a minute" }
        return "\(Int(((minimum - e) / 60).rounded(.up))) min to go"
    }

    /// Which side of the flip the label is on (looks animate the roll between them).
    static func labelSide(_ e: Double) -> Int { e < 600 ? 0 : (e < minimum ? 1 : 2) }

    /// A checkpoint or "+5" moment that is still within its beat window.
    struct Beat: Equatable {
        /// 300, 600, 900, 1200, then 1500, 1800 ...
        let at: Double
        /// Seconds since it was crossed (0 ..< duration).
        let age: Double
        let text: String
        /// 0...3 for the four checkpoints, nil for the "+5." beats after 20.
        let checkpointIndex: Int?
        var isTwenty: Bool { at == 1200 }
    }

    static func beatText(at: Double) -> String {
        switch at {
        case 300: return "5 down."
        case 600: return "halfway."
        case 900: return "last 5."
        case 1200: return "20. it counts."
        default: return "+5."
        }
    }

    /// The last moment crossed (checkpoint or every 5 min after 20), or nil before 5:00.
    static func lastMoment(_ e: Double) -> Double? {
        guard e >= 300 else { return nil }
        return (e / 300).rounded(.down) * 300
    }

    static func beat(_ e: Double) -> Beat? {
        guard let at = lastMoment(e) else { return nil }
        let age = e - at
        let window = at == 1200 ? bigMomentDuration : beatDuration
        guard age < window else { return nil }
        let idx = checkpoints.firstIndex(of: at)
        return Beat(at: at, age: age, text: beatText(at: at), checkpointIndex: idx)
    }

    /// The next moment ahead (for end-spurt build-up), and seconds until it.
    static func next(_ e: Double) -> (at: Double, inSeconds: Double) {
        let at = ((e / 300).rounded(.down) + 1) * 300
        return (at, at - e)
    }

    /// 0 outside the last 60 s before the next moment, rising to 1 right at it.
    static func spurt(_ e: Double) -> Double {
        let n = next(e)
        return n.inSeconds <= 60 ? 1 - n.inSeconds / 60 : 0
    }

    /// Progress to 20 (0...1).
    static func progress(_ e: Double) -> Double { min(1, max(0, e / minimum)) }

    /// Whole minutes done, capped at 20 (floors, dots, camps).
    static func minutesDone(_ e: Double) -> Int { min(20, Int(e / 60)) }
}

// MARK: - What a look receives

/// Everything a look draws from. A look owns no timers and no state that the host can't rebuild.
struct HomeWorkoutFrame {
    enum Phase: Equatable { case setup, running }

    let facts: HomeWorkoutFacts
    let phase: Phase
    /// Seconds since the setup screen appeared (drives the one-time entrance).
    let setupAge: Double
    /// Seconds since start was tapped (the setup-to-timer morph). 0 while in setup.
    let runAge: Double
    /// Workout seconds elapsed (from the session's real start time). 0 while in setup.
    let elapsed: Double
    let size: CGSize
    let safeTop: CGFloat
    let safeBottom: CGFloat
    let reduceMotion: Bool
    /// Absolute time for tiny idle motions (stars twinkle once, jitter noise).
    let now: Double

    var isRunning: Bool { phase == .running }
    var isDone: Bool { isRunning && HomeWorkoutClock.isDone(elapsed) }
    var beat: HomeWorkoutClock.Beat? { isRunning ? HomeWorkoutClock.beat(elapsed) : nil }
}

/// Layout slots shared by all four looks. The host draws the top-right glass button and the
/// bottom primary button in these places, so a look keeps them clear.
enum HomeWorkoutLayout {
    /// Seconds after "start" in which back asks nothing.
    static let mistakeWindow: Double = 60
    static let margin: CGFloat = 28
    static let buttonHeight: CGFloat = 56
    /// Distance from the bottom safe edge to the button's bottom.
    static let buttonBottomInset: CGFloat = 20
    /// Top-right glass control: 44 pt, 20 pt from the right, 8 pt under the safe top.
    static let topControlSize: CGFloat = 44
    /// Space a look must leave free above the bottom safe edge (button + hint line).
    static let bottomReserved: CGFloat = 112
}

/// Matrix B's minute haptic: the host fires `Haptics.selection()` each new minute for this look only.
extension HomeWorkoutLook {
    var ticksEachMinute: Bool { self == .matrixStack }
}
