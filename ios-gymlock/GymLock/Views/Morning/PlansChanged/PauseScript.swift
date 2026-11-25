//
//  PauseScript.swift
//  GymLock · the "plans changed" pause
//
//  The words of the pause and their timing, built from PauseFacts. Exact port of the approved
//  prototype's shared engine (docs/prototypes/plans-changed-pause.html, shared.js): the same lines,
//  the same priorities, the same reading pace. The three looks (Ridge, Matrix printer, Day 0) only
//  draw what this file decides.
//
//  Reading pace: adults read about 238 words a minute silently (Brysbaert, 2019). Just after waking,
//  sleep inertia slows thinking (Hilditch, 2019), so lines are paced for 150 wpm = 2.5 words a
//  second, plus a moment to notice the line and a dwell before the next one. Lines that do not fit
//  the 30 seconds are dropped lowest priority first.
//

import Foundation

struct PauseLine: Hashable, Identifiable {
    enum Kind: Hashable {
        /// Where you are right now.
        case ground
        /// The lead-in and follow-up around their own words.
        case own
        /// Their own words from day 0, quoted.
        case quote
        /// What is at stake, from real numbers.
        case stake
        /// One concrete fact for their stage of the habit, with its source.
        case fact
        /// The way forward.
        case close
    }

    let id: Int
    let kind: Kind
    let text: String
    let source: String?
    /// Seconds after the pause opened.
    let start: Double
    let duration: Double
    var end: Double { start + duration }
    var words: [String] { text.split(separator: " ").map(String.init) }
}

struct PauseChoice: Hashable, Identifiable {
    enum Key: String, Hashable {
        case gym
        case home
        case cant
    }

    let key: Key
    let title: String
    let lead: String
    let perks: [String]
    let primary: String
    let secondary: String
    var id: Key { key }
}

/// One row of the printed receipt: a label on the left, a value on the right, dot leaders between.
struct PauseReceiptRow: Hashable {
    let label: String
    let value: String
}

struct PauseScript: Hashable {
    static let wait: Double = 30

    // Reading pace (see the header).
    static let wordsPerSecond = 2.5
    static let notice = 0.5
    static let dwell = 1.1
    static let minimumLine = 2.4
    static let firstLine = 0.7

    let lines: [PauseLine]
    let choices: [PauseChoice]
    let receiptRows: [PauseReceiptRow]
    /// Their own words, quoted, or nil when they gave none.
    let quote: String?
    let ifGo: String
    let ifSkip: String
    /// The stage fact and its source (also one of `lines`).
    let fact: PauseLine?

    static func lineDuration(_ text: String) -> Double {
        let words = Double(text.split(separator: " ").count)
        return max(minimumLine, notice + words / wordsPerSecond + dwell)
    }

    /// "0:24" while waiting, "continue" once the 30 seconds are up.
    static func timerLabel(elapsed: Double) -> String {
        let left = max(0, Int((wait - elapsed).rounded(.up)))
        return left > 0 ? String(format: "0:%02d", left) : "continue"
    }

    enum Stage: Hashable {
        case new, building, close, habit
    }

    static func stage(visitsBefore: Int) -> Stage {
        switch visitsBefore {
        case ..<10: .new
        case ..<40: .building
        case ..<66: .close
        default: .habit
        }
    }

    static func quoteLine(for reason: FailureReason?) -> String? {
        switch reason {
        case .laterToday: "\"i tell myself i'll go later.\""
        case .scrolling: "\"i start scrolling.\""
        case .exhausted: "\"i'm exhausted.\""
        case .scheduleChanges: "\"my schedule changes.\""
        // "i snooze the alarm" is past by the time this screen shows, so it has no line here.
        case .snooze, .somethingElse, .none: nil
        }
    }

    static func afterQuote(for reason: FailureReason?, homeMinutes: Int) -> String? {
        switch reason {
        case .laterToday: "this is that sentence, happening."
        case .scrolling: "skip, and the apps open. that is the trade."
        case .exhausted: "10 easy minutes lifts energy. today can be a light one."
        case .scheduleChanges: "if it really did, \(homeMinutes) minutes at home still counts."
        case .snooze, .somethingElse, .none: nil
        }
    }

    init(facts f: PauseFacts) {
        struct Draft { let priority: Int; let kind: PauseLine.Kind; let text: String; let source: String? }
        var drafts: [Draft] = []
        func add(_ p: Int, _ k: PauseLine.Kind, _ t: String, _ s: String? = nil) {
            drafts.append(Draft(priority: p, kind: k, text: t, source: s))
        }

        // 1. where you are right now
        switch f.context {
        case .windowOpen:
            add(1, .ground, "you beat the alarm. the rest is shoes and a door.")
        case .windowClosed:
            if let gymBy = f.gymBy {
                add(1, .ground, "gym time was \(gymBy). it is \(f.nowLabel) now.")
            } else {
                add(1, .ground, "the window closed. it is \(f.nowLabel) now.")
            }
        }

        // 2. their own words from day 0
        let quote = Self.quoteLine(for: f.reason)
        if let quote, let after = Self.afterQuote(for: f.reason, homeMinutes: f.homeMinutes) {
            add(2, .own, "on day 0 you told us why you miss:")
            add(2, .quote, quote)
            add(2, .own, after)
        }

        // 3. the stakes, from real numbers
        if f.lastSkipped {
            add(3, .stake, "last time was a skip too. two in a row is where habits slip.")
        } else if f.weekAtRisk {
            add(3, .stake, "skip today and \(f.weekGoal) this week is out of reach.")
        } else {
            add(6, .stake, "today would make it \(f.weekDone + 1) of \(f.weekGoal) this week.")
        }

        // 4. one concrete fact for where they are in the habit
        let n = f.visitsBefore
        let factDraft: Draft
        switch Self.stage(visitsBefore: n) {
        case .new:
            factDraft = Draft(priority: 4, kind: .fact, text: "people expect a workout to feel worse than it does. they only picture the first minutes.", source: "ruby et al., 2011")
        case .building:
            factDraft = Draft(priority: 4, kind: .fact, text: "every visit makes the next one take less effort. you have \(n) behind you.", source: "lally et al., 2010")
        case .close:
            factDraft = Draft(priority: 4, kind: .fact, text: "\(66 - n) more visits and going stops being a decision.", source: "lally et al., 2010")
        case .habit:
            factDraft = Draft(priority: 4, kind: .fact, text: "\(n) visits. one more keeps it automatic.", source: "lally et al., 2010")
        }
        drafts.append(factDraft)

        // 5. the way forward
        switch f.context {
        case .windowClosed: add(5, .close, "go now and you get \(f.graceMinutes) more minutes.")
        case .windowOpen:
            if let gymBy = f.gymBy { add(5, .close, "gym by \(gymBy). you can still make it.") }
            else { add(5, .close, "you can still make it.") }
        }

        // Fit into 30 s at reading pace: drop the lowest priority until it fits. Their own words
        // travel as a block of three: the whole block or none.
        var fitted = drafts
        func total(_ a: [Draft]) -> Double { Self.firstLine + a.reduce(0) { $0 + Self.lineDuration($1.text) } }
        while total(fitted) > Self.wait - 0.4, fitted.count > 1 {
            let worst = fitted.max { $0.priority < $1.priority }!
            fitted = worst.priority == 2 ? fitted.filter { $0.priority != 2 } : fitted.filter { $0.text != worst.text }
        }
        var t = Self.firstLine
        var built: [PauseLine] = []
        for (i, d) in fitted.enumerated() {
            let dur = Self.lineDuration(d.text)
            built.append(PauseLine(id: i, kind: d.kind, text: d.text, source: d.source, start: t, duration: dur))
            t += dur
        }
        lines = built
        fact = built.first { $0.kind == .fact } ?? PauseLine(id: -1, kind: .fact, text: factDraft.text, source: factDraft.source, start: 0, duration: Self.lineDuration(factDraft.text))
        self.quote = quote

        // The three doors, in order.
        var c: [PauseChoice] = []
        c.append(PauseChoice(
            key: .gym, title: "still going",
            lead: f.context == .windowClosed
                ? "\(f.graceMinutes) more minutes. not a new window."
                : (f.gymBy.map { "gym by \($0)." } ?? "the gym is still on."),
            perks: ["visit \(f.visitNumber) of 66", "this week becomes \(f.weekDone + 1) of \(f.weekGoal)", "apps unlock when you arrive"],
            primary: "i'm going", secondary: "not this"
        ))
        if f.homeLeft > 0 {
            c.append(PauseChoice(
                key: .home, title: "quick workout instead",
                lead: "\(f.homeMinutes) minutes at home counts as a full day.",
                perks: ["this week becomes \(f.weekDone + 1) of \(f.weekGoal)", "checked by apple health or a photo", "\(f.homeLeft) of \(HomeWorkoutRules.monthlyLimit) left this month"],
                primary: "start \(f.homeMinutes) minutes", secondary: "not this either"
            ))
        }
        c.append(PauseChoice(
            key: .cant, title: "can't today",
            lead: f.weekAtRisk ? "make it up. this keeps your streak." : "no problem. you need \(max(0, f.weekGoal - f.weekDone)) more this week.",
            perks: ["one skip won't undo \(n) visits", "next, pick a day to make it up"],
            primary: "can't today", secondary: "back to the gym"
        ))
        choices = c

        // The printed receipt.
        var rows = [PauseReceiptRow(label: "gym by", value: f.gymBy ?? "today")]
        if f.streakWeeks > 0 { rows.append(PauseReceiptRow(label: "streak", value: f.streakWeeks == 1 ? "1 week" : "\(f.streakWeeks) weeks")) }
        if f.lastSkipped { rows.append(PauseReceiptRow(label: "last time", value: "skipped")) }
        rows.append(PauseReceiptRow(label: "this week", value: "\(f.weekDone) of \(f.weekGoal)"))
        rows.append(PauseReceiptRow(label: "this visit", value: "\(f.visitNumber) of 66"))
        receiptRows = rows
        ifGo = "\(f.weekDone + 1) of \(f.weekGoal)"
        ifSkip = "\(max(0, f.weekGoal - f.weekDone)) still to do"
    }
}
