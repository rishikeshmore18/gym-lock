import Foundation

// MARK: - Card style (02-experience-spec §7)

/// Which Dynamic hero card draws Home. Only Dynamic ships; there is no Classic.
nonisolated enum HeroCardStyle: String, CaseIterable, Identifiable, Sendable {
    case ridge
    case matrix

    var id: String { rawValue }
    var title: String { rawValue }
    /// Ridge, the warm painted look of the prototype (`useState<Concept>('ridge')`).
    static let `default`: HeroCardStyle = .ridge
    /// `@AppStorage` key (spec §7).
    static let storageKey = "gymlock.home.cardStyle"
    /// The app-level switch for hero and done-flow haptics (default on).
    static let hapticsKey = "gymlock.hero.haptics"
    /// `DoneFlowLength` raw value.
    static let doneFlowLengthKey = "gymlock.doneFlow.length"
}

/// How long the done flow runs (spec §4.3 fatigue guard). The user's choice always wins.
nonisolated enum DoneFlowLength: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case full
    case short

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "auto"
        case .full: "full"
        case .short: "short"
        }
    }
}

// MARK: - Theme rotation (02-experience-spec §1.4, verbatim)

nonisolated enum HeroTheme: Int, CaseIterable, Codable, Sendable { case radiant, tiles, signal, levels, vectors, loops, week }

nonisolated struct ThemeLedger: Codable, Equatable, Sendable {
    var assigned: [String: Int] = [:]   // display-day key "yyyy-MM-dd" → theme; trimmed to 45 days
    var lastShown: [Int: String] = [:]  // theme → last display-day key it was assigned to
    var built: UInt8 = 0                // bit i = theme i built in this cycle
    var cycle = 0
    var lastTrainingTheme: Int?
    static let full: UInt8 = 0b111_1111

    /// Themes built in the current cycle, for the done flow's set strip ("3 of 7").
    var builtCount: Int { (0..<7).filter { built & (1 << $0) != 0 }.count }
    func isBuilt(_ t: HeroTheme) -> Bool { built & (1 << t.rawValue) != 0 }
}

nonisolated enum DayKind: Sendable { case training, other }

nonisolated enum ThemeRotation {
    static let rolloverHour = 4

    static func displayDay(_ date: Date, _ cal: Calendar) -> Date {
        cal.startOfDay(for: cal.date(byAdding: .hour, value: -rolloverHour, to: date)!)
    }
    static func key(_ day: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    /// Monday = 0 … Sunday = 6 (Calendar.weekday: Sunday = 1).
    static func weekdayIndex(_ day: Date, _ cal: Calendar) -> Int { (cal.component(.weekday, from: day) + 5) % 7 }
    private static func forward(_ c: Int, after base: Int) -> Int { (c - base - 1 + 14) % 7 }

    /// Pure: what a training day would get. Used to commit and to peek.
    static func trainingPick(_ l: ThemeLedger, day: Date, yesterday: Int?, _ cal: Calendar) -> Int {
        let w = weekdayIndex(day, cal)
        var c = Set((0..<7).filter { l.built & (1 << $0) == 0 })
        if c.isEmpty { c = Set(0..<7) }                       // defensive; built resets when full
        if let t = l.lastTrainingTheme, c.count > 1 { c.remove(t) }
        if let y = yesterday, c.count > 1 { c.remove(y) }
        if c.contains(w) { return w }
        let base = l.lastTrainingTheme ?? (w + 6) % 7
        return c.min { forward($0, after: base) < forward($1, after: base) }!
    }

    static func otherPick(_ l: ThemeLedger, day: Date, yesterday: Int?, nextTrainingDay: Date?, _ cal: Calendar) -> Int {
        let w = weekdayIndex(day, cal)
        let peek = nextTrainingDay.map { trainingPick(l, day: $0, yesterday: nil, cal) }
        var c = (0..<7).filter { $0 != yesterday && $0 != peek && $0 != l.lastTrainingTheme }
        if c.isEmpty { c = (0..<7).filter { $0 != yesterday } }
        func age(_ t: Int) -> String { l.lastShown[t] ?? "0000-00-00" }   // never shown = oldest
        return c.min {
            (age($0), $0 == w ? 0 : 1, forward($0, after: (w + 6) % 7)) <
            (age($1), $1 == w ? 0 : 1, forward($1, after: (w + 6) % 7))
        }!
    }

    /// The only writer. Call on the main actor; persist the ledger right after.
    static func theme(for date: Date, kind: DayKind, nextTrainingDay: Date?, ledger l: inout ThemeLedger, _ cal: Calendar) -> HeroTheme {
        let day = displayDay(date, cal), k = key(day, cal)
        if let t = l.assigned[k] { return HeroTheme(rawValue: t)! }   // rule 1: stable
        let yKey = key(cal.date(byAdding: .day, value: -1, to: day)!, cal)
        let y = l.assigned[yKey]
        let t = kind == .training
            ? trainingPick(l, day: day, yesterday: y, cal)
            : otherPick(l, day: day, yesterday: y, nextTrainingDay: nextTrainingDay, cal)
        l.assigned[k] = t
        l.lastShown[t] = k
        if kind == .training { l.lastTrainingTheme = t }
        l.assigned = l.assigned.filter { $0.key >= key(cal.date(byAdding: .day, value: -45, to: day)!, cal) }
        return HeroTheme(rawValue: t)!
    }

    /// Call when a session's done flow ends (sealed or closed) or its verified card is displayed.
    static func markBuilt(_ t: HeroTheme, ledger l: inout ThemeLedger) {
        l.built |= 1 << t.rawValue
        l.lastTrainingTheme = t.rawValue          // also covers an unplanned day that was "other"
        if l.built == ThemeLedger.full { l.built = 0; l.cycle += 1 }
    }
}

// MARK: - Week and month position (02-experience-spec §1.5)

nonisolated enum HeroWeekPos: String, Sendable, CaseIterable {
    case first, middle, last, bonus

    /// `.bonus` draws the `middle` visuals with FLOW's bonus line.
    var visual: MatrixWeekPos {
        switch self {
        case .first: .first
        case .middle, .bonus: .middle
        case .last: .last
        }
    }
}

nonisolated enum HeroPositions {
    /// k = counted session days this week including today; goal = the week's saved goal (min 3).
    static func weekPos(k: Int, goal: Int) -> HeroWeekPos {
        k > goal ? .bonus : k == goal ? .last : k == 1 ? .first : .middle
    }

    static func monthPos(earlierCountedThisMonth: Int, plannedDaysLeftAfterToday: Int, recapShownThisMonth: Bool) -> MatrixMonthPos {
        let isLast = plannedDaysLeftAfterToday == 0 && !recapShownThisMonth
        if isLast { return .last }                 // the recap is the truth of the month; it wins a tie
        return earlierCountedThisMonth == 0 ? .first : .middle
    }

    /// Climax taps: seven close the week, and the week object has one piece per weekday.
    static func taps(theme: HeroTheme, pos: HeroWeekPos) -> Int {
        pos == .last || theme == .week ? 7 : 5
    }
}

// MARK: - Persistence

/// What the hero remembers between launches, besides the theme ledger: the frozen ambient
/// state of each display day, the once-ever moments, which days already built their theme,
/// and which scene haptics were already felt today.
nonisolated struct HeroAmbientLedger: Codable, Equatable, Sendable {
    /// display-day key → ambient moment raw value (spec §2.1: one per day, frozen).
    var byDay: [String: String] = [:]
    /// once-ever moment raw value → the display-day key it was shown on.
    var onceEver: [String: String] = [:]
    /// display-day keys whose theme was marked built, so a replay never marks twice.
    var builtDays: [String] = []
    /// "dayKey|moment|style" entries: scene haptics already played (spec §6.2 play policy).
    var hapticsPlayed: [String] = []
    /// The lapse (key of the last counted day before it) and the days comeback was shown for it.
    var comebackLapse: String?
    var comebackDays: [String] = []
    /// Month keys "yyyy-MM" whose recap (month `.last`) was shown in a done flow.
    var recapMonths: [String] = []

    mutating func trim(keepingFrom oldest: String) {
        byDay = byDay.filter { $0.key >= oldest }
        builtDays = builtDays.filter { $0 >= oldest }
        hapticsPlayed = hapticsPlayed.filter { $0 >= oldest }
        comebackDays = comebackDays.filter { $0 >= oldest }
        if recapMonths.count > 24 { recapMonths = Array(recapMonths.suffix(24)) }
    }
}

/// Owns the theme ledger and the ambient ledger. Not observable on purpose: the hero derives
/// from the app's observable state and reads these as side tables. Writes are synchronous.
@MainActor
final class HeroRotationStore {
    static let shared = HeroRotationStore()

    static let ledgerKey = "hero.themeLedger.v1"
    static let ambientKey = "hero.ambient.v1"
    static let monthTargetPrefix = "gymlock.month.target."

    private let defaults: UserDefaults
    private(set) var ledger: ThemeLedger
    private(set) var ambient: HeroAmbientLedger

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ledger = defaults.data(forKey: Self.ledgerKey).flatMap { try? JSONDecoder().decode(ThemeLedger.self, from: $0) } ?? ThemeLedger()
        ambient = defaults.data(forKey: Self.ambientKey).flatMap { try? JSONDecoder().decode(HeroAmbientLedger.self, from: $0) } ?? HeroAmbientLedger()
    }

    // MARK: Themes

    /// Today's theme, assigned on first need and frozen for the display day.
    func theme(for date: Date, kind: DayKind, nextTrainingDay: Date?, calendar: Calendar) -> HeroTheme {
        var l = ledger
        let t = ThemeRotation.theme(for: date, kind: kind, nextTrainingDay: nextTrainingDay, ledger: &l, calendar)
        if l != ledger {
            ledger = l
            persistLedger()
        }
        return t
    }

    /// Peek without committing (the style preview, the lab).
    func peekTheme(for date: Date, calendar: Calendar) -> HeroTheme? {
        let k = ThemeRotation.key(ThemeRotation.displayDay(date, calendar), calendar)
        return ledger.assigned[k].flatMap(HeroTheme.init(rawValue:))
    }

    /// Marks today's theme built once per display day (done flow ended, or verified card shown).
    func markBuilt(_ t: HeroTheme, dayKey: String) {
        guard !ambient.builtDays.contains(dayKey) else { return }
        var l = ledger
        ThemeRotation.markBuilt(t, ledger: &l)
        ledger = l
        ambient.builtDays.append(dayKey)
        persistLedger()
        persistAmbient()
    }

    // MARK: Ambient

    func ambientMoment(dayKey: String) -> MatrixMoment? {
        ambient.byDay[dayKey].flatMap(MatrixMoment.init(rawValue:))
    }

    func freezeAmbient(_ m: MatrixMoment, dayKey: String, oldestKey: String) {
        guard ambient.byDay[dayKey] == nil else { return }
        ambient.byDay[dayKey] = m.rawValue
        if HeroMomentRules.onceEver.contains(m), ambient.onceEver[m.rawValue] == nil {
            ambient.onceEver[m.rawValue] = dayKey
        }
        ambient.trim(keepingFrom: oldestKey)
        persistAmbient()
    }

    /// The done flow shows a halfway or automatic variant: that spends the once-ever moment.
    func spendOnceEver(_ m: MatrixMoment, dayKey: String) {
        guard ambient.onceEver[m.rawValue] == nil else { return }
        ambient.onceEver[m.rawValue] = dayKey
        persistAmbient()
    }

    func noteComeback(lapse: String, dayKey: String) {
        if ambient.comebackLapse != lapse {
            ambient.comebackLapse = lapse
            ambient.comebackDays = []
        }
        if !ambient.comebackDays.contains(dayKey) { ambient.comebackDays.append(dayKey) }
        persistAmbient()
    }

    func noteRecap(monthKey: String) {
        guard !ambient.recapMonths.contains(monthKey) else { return }
        ambient.recapMonths.append(monthKey)
        persistAmbient()
    }

    // MARK: Haptics play policy

    func hapticsPlayed(_ entry: String) -> Bool { ambient.hapticsPlayed.contains(entry) }

    func markHapticsPlayed(_ entry: String) {
        guard !ambient.hapticsPlayed.contains(entry) else { return }
        ambient.hapticsPlayed.append(entry)
        if ambient.hapticsPlayed.count > 200 { ambient.hapticsPlayed.removeFirst(ambient.hapticsPlayed.count - 200) }
        persistAmbient()
    }

    // MARK: Month target

    func monthTarget(monthKey: String) -> Int? {
        let v = defaults.integer(forKey: Self.monthTargetPrefix + monthKey)
        return v > 0 ? v : nil
    }

    func setMonthTarget(_ n: Int, monthKey: String) {
        defaults.set(n, forKey: Self.monthTargetPrefix + monthKey)
    }

    // MARK: Writes

    private func persistLedger() {
        if let data = try? JSONEncoder().encode(ledger) { defaults.set(data, forKey: Self.ledgerKey) }
    }

    private func persistAmbient() {
        if let data = try? JSONEncoder().encode(ambient) { defaults.set(data, forKey: Self.ambientKey) }
    }
}
