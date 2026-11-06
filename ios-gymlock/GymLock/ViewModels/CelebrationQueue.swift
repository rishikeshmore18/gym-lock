import Foundation
import Observation
import CoreGraphics

/// One celebration waiting for its turn (02-experience-spec §3.2).
nonisolated struct PendingCelebration: Codable, Identifiable, Equatable, Sendable {
    enum Kind: Codable, Equatable, Sendable {
        /// keyed by the counted outcome's id
        case doneFlow(sessionID: UUID)
        case rankUp(badgeID: String, sessionID: UUID?)
    }

    var id = UUID()
    var kind: Kind
    var earnedAt: Date
    /// display-day key ("yyyy-MM-dd") the celebration belongs to
    var displayDay: String

    var flowSessionID: UUID? {
        if case .doneFlow(let id) = kind { return id }
        return nil
    }

    var badgeID: String? {
        if case .rankUp(let id, _) = kind { return id }
        return nil
    }

    var rankUpSessionID: UUID? {
        if case .rankUp(_, let s) = kind { return s }
        return nil
    }
}

/// The only presenter of full-screen celebrations: the done flow and badge rank-ups.
///
/// Rules (spec §3.2):
/// 1. One full-screen sequence per foreground session (a session ends after 10 min in the background).
/// 2. At most two rank-ups inside the flow, streak > days > achievement then tier, lower shown first,
///    the highest rung per ladder.
/// 3. The rest go quiet: a coral dot on Progress, and the Badges screen reveals them.
/// 4. Standalone rank-ups: at most one per foreground session, never in one that had a flow, only in a
///    session that began 30 min or more after the last celebration ended, quiet after 7 days.
/// 5. Only the latest valid session gets a flow; older ones are consumed silently.
@Observable
@MainActor
final class CelebrationQueue {
    static let shared = CelebrationQueue()
    static let storageKey = "celebrations.v1"

    static let sessionGap: TimeInterval = 600
    static let standaloneGap: TimeInterval = 1800
    static let rankUpLifetime: TimeInterval = 7 * 86_400

    /// Where a flow was when the app left (spec §3.4); written on every change.
    struct FlowProgress: Codable, Equatable {
        var sessionID: UUID
        var dayKey: String
        var index: Int
        var taps: Int
        var sealed: Bool
        var savedAt: Date
        var short: Bool
    }

    struct Persisted: Codable, Equatable {
        var pending: [PendingCelebration] = []
        /// counted outcomes that already had (or silently skipped) their flow; the last 60
        var consumed: [UUID] = []
        var completedFlows = 0
        /// whether each of the last five flows was closed before the seal
        var closedEarlyHistory: [Bool] = []
        var progress: FlowProgress?
        var lastCelebrationEndedAt: Date?
        var sessionStartedAt: Date?
        var sessionHadFlow = false
        var sessionHadStandalone = false
        var backgroundedAt: Date?
        var seeded = false
        /// badges already turned into celebrations (or present before the queue existed)
        var knownBadges: [String] = []
        /// rank-ups that went quiet; the Progress dot shows while any is unseen
        var quietBadges: [String] = []
        /// today's finished flow, replayable from the verified card until the day ends
        var replaySessionID: UUID?
        var replayDayKey: String?
    }

    /// A flow on screen.
    struct Presentation: Identifiable {
        let id = UUID()
        let sessionID: UUID
        let model: MatrixStoryModel
        let style: HeroCardStyle
        let isReplay: Bool
        let dayKey: String
        let monthKey: String
        let short: Bool
        /// in-flow rank-ups still to show, lower first
        var rankUps: [String]
        /// captured when the flow opened, so the collapse flies into the card where it was
        let cardFrame: CGRect?
    }

    private(set) var data: Persisted {
        didSet { if data != oldValue { persist() } }
    }

    private(set) var presentation: Presentation?
    /// the in-flow rank-up on screen
    private(set) var rankUp: BadgeRankUpRequest?
    /// a standalone rank-up (presented by the shell with `.badgeRankUp`)
    var standalone: BadgeRankUpRequest?
    /// the session whose collapse reached 70%: the card shows verified from here on
    private(set) var landedSessionID: UUID?
    /// bumped when a flow ends (completed, closed or discarded) so the shell can follow up
    private(set) var flowEndCount = 0
    /// the Progress spotlight the notification asked for, opened once the flow collapses (§4.1 N)
    var spotlightAfterFlow: Date?

    /// The hero card's frame in global space, reported continuously; read when a flow opens.
    @ObservationIgnored var cardFrame: CGRect?

    @ObservationIgnored private var store: AppStore?
    @ObservationIgnored private var coordinator: GymSessionCoordinator?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let rotation: HeroRotationStore

    init(defaults: UserDefaults = .standard, rotation: HeroRotationStore = .shared) {
        self.defaults = defaults
        self.rotation = rotation
        if let raw = defaults.data(forKey: Self.storageKey), let decoded = try? JSONDecoder().decode(Persisted.self, from: raw) {
            data = decoded
        } else {
            data = Persisted()
        }
    }

    private func persist() {
        if let raw = try? JSONEncoder().encode(data) { defaults.set(raw, forKey: Self.storageKey) }
    }

    // MARK: Days

    private var cal: Calendar { HeroMomentResolver.displayCalendar() }

    func dayKey(_ now: Date = Date()) -> String {
        let c = cal
        return ThemeRotation.key(ThemeRotation.displayDay(now, c), c)
    }

    private func isToday(_ o: SessionOutcome, now: Date) -> Bool {
        let c = cal
        let day = o.countingDay(calendar: c)
        return c.isDate(day, inSameDayAs: ThemeRotation.displayDay(now, c)) || c.isDate(day, inSameDayAs: now)
    }

    // MARK: Reading

    /// Today's flow that has not played yet.
    func pendingFlow(now: Date = Date()) -> PendingCelebration? {
        let key = dayKey(now)
        return data.pending.first { $0.flowSessionID != nil && $0.displayDay == key }
    }

    var hasPendingFlow: Bool { pendingFlow() != nil }

    /// The coral dot on Home: a flow is waiting for Home.
    var showsHomeDot: Bool { hasPendingFlow && presentation == nil }

    /// The coral dot on Progress: a rank-up went quiet and the Badges screen has not revealed it.
    var showsProgressDot: Bool {
        let badges = BadgeStore.shared
        return data.quietBadges.contains { badges.records[$0]?.seen != true }
    }

    /// The hero must stay paused and muted, and other celebrations wait (spec §3.5).
    var isCelebrating: Bool { presentation != nil || standalone != nil }

    /// Card and quiet haptics hold while a flow is pending or up.
    var holdsHomeHaptics: Bool { isCelebrating || hasPendingFlow }

    /// Whether the verified card can replay today's flow.
    func canReplay(now: Date = Date()) -> Bool {
        guard presentation == nil, !hasPendingFlow, data.replayDayKey == dayKey(now), let id = data.replaySessionID else { return false }
        return store?.log.outcomes.contains { $0.id == id && $0.counts } ?? false
    }

    /// A flow ran (or is running) for this display day: the verified card skips its own scene haptics.
    func flowRan(dayKey key: String) -> Bool {
        data.replayDayKey == key || presentation?.dayKey == key
    }

    /// The streak intro must not open while a flow could still cover the kept week (spec §3.5).
    func suppressesStreakIntro(now: Date = Date()) -> Bool {
        if isCelebrating || hasPendingFlow { return true }
        guard data.seeded, let store else { return false }
        let consumed = Set(data.consumed)
        return store.log.outcomes.contains { $0.counts && !consumed.contains($0.id) && isToday($0, now: now) }
    }

    /// Fatigue guard (spec §4.3): the user's choice wins; auto turns short after 21 completed flows
    /// when 3 of the last 5 were closed early.
    var isShort: Bool {
        let raw = defaults.string(forKey: HeroCardStyle.doneFlowLengthKey) ?? DoneFlowLength.automatic.rawValue
        switch DoneFlowLength(rawValue: raw) ?? .automatic {
        case .full: return false
        case .short: return true
        case .automatic:
            return data.completedFlows >= 21 && data.closedEarlyHistory.suffix(5).filter { $0 }.count >= 3
        }
    }

    // MARK: Detection

    /// Reads the record: new counted sessions become flows, new badges become rank-ups.
    /// Call on every log change and when the scene becomes active.
    func sync(store: AppStore, coordinator: GymSessionCoordinator, now: Date = Date()) {
        self.store = store
        self.coordinator = coordinator
        let badges = BadgeStore.shared
        badges.refresh(store: store)
        let earned = BadgeCatalog.all.map(\.id).filter { badges.state(for: $0).isEarned }
        let counted = store.log.outcomes.filter(\.counts)

        var d = data
        if !d.seeded {
            // First run: nothing that happened before the queue existed celebrates.
            d.consumed = Array(counted.map(\.id).suffix(60))
            d.knownBadges = earned
            d.seeded = true
            d.sessionStartedAt = d.sessionStartedAt ?? now
            data = d
            return
        }

        let key = dayKey(now)
        let consumed = Set(d.consumed)

        // Expired flows (04:00 of the next display day) are consumed; their rank-ups become standalones.
        var expiredSessions: [UUID] = []
        d.pending.removeAll { p in
            if let s = p.flowSessionID, p.displayDay != key, presentation?.sessionID != s {
                expiredSessions.append(s)
                return true
            }
            return false
        }
        if let pr = d.progress, pr.dayKey != key, presentation?.sessionID != pr.sessionID { d.progress = nil }

        // Rule 5: the latest valid session of today gets the flow.
        let pendingIDs = Set(d.pending.compactMap(\.flowSessionID))
        let todays = counted.filter { isToday($0, now: now) && !consumed.contains($0.id) && presentation?.sessionID != $0.id }
        let candidates = todays.filter { !pendingIDs.contains($0.id) } + counted.filter { pendingIDs.contains($0.id) }
        if let latest = candidates.max(by: { $0.date < $1.date }) {
            for p in d.pending where p.flowSessionID != nil && p.flowSessionID != latest.id {
                expiredSessions.append(p.flowSessionID!)
            }
            d.pending.removeAll { $0.flowSessionID != nil && $0.flowSessionID != latest.id }
            for o in todays where o.id != latest.id { expiredSessions.append(o.id) }
            if !pendingIDs.contains(latest.id) {
                d.pending.append(PendingCelebration(kind: .doneFlow(sessionID: latest.id), earnedAt: latest.date, displayDay: key))
            }
        }
        // A pending flow whose session stopped counting (undone, deleted) is dropped.
        let countedIDs = Set(counted.map(\.id))
        d.pending.removeAll { p in p.flowSessionID.map { !countedIDs.contains($0) } ?? false }
        for s in expiredSessions { Self.consume(s, in: &d) }
        for i in d.pending.indices {
            if let s = d.pending[i].rankUpSessionID, expiredSessions.contains(s), let b = d.pending[i].badgeID {
                d.pending[i].kind = .rankUp(badgeID: b, sessionID: nil)
            }
        }

        // New badges: attached to today's pending flow, or standalone.
        let known = Set(d.knownBadges)
        let fresh = earned.filter { !known.contains($0) && badges.records[$0]?.seen != true }
        let flowID = d.pending.first { $0.flowSessionID != nil && $0.displayDay == key }?.flowSessionID
        for b in fresh {
            d.pending.append(PendingCelebration(kind: .rankUp(badgeID: b, sessionID: flowID), earnedAt: now, displayDay: key))
        }
        d.knownBadges = Array(Set(d.knownBadges).union(earned)).sorted()

        // Seen elsewhere (the Badges screen) or older than 7 days: no longer a celebration.
        d.pending.removeAll { p in
            guard let b = p.badgeID else { return false }
            if badges.records[b]?.seen == true { return true }
            if now.timeIntervalSince(p.earnedAt) > Self.rankUpLifetime {
                if !d.quietBadges.contains(b) { d.quietBadges.append(b) }
                return true
            }
            return false
        }
        d.quietBadges.removeAll { badges.records[$0]?.seen == true }
        data = d
    }

    private static func consume(_ id: UUID, in d: inout Persisted) {
        d.pending.removeAll { $0.flowSessionID == id }
        if !d.consumed.contains(id) { d.consumed.append(id) }
        if d.consumed.count > 60 { d.consumed.removeFirst(d.consumed.count - 60) }
    }

    // MARK: Foreground sessions

    func sceneBecameActive(now: Date = Date()) {
        var d = data
        let away = d.backgroundedAt.map { now.timeIntervalSince($0) }
        if d.sessionStartedAt == nil || (away ?? Self.sessionGap) >= Self.sessionGap {
            d.sessionStartedAt = now
            d.sessionHadFlow = presentation != nil
            d.sessionHadStandalone = false
        }
        d.backgroundedAt = nil
        data = d

        guard let p = presentation else { return }
        if dayKey(now) != p.dayKey {
            // The day ended while away: discard; the theme stays unbuilt.
            discard(p)
            return
        }
        let gone = away ?? 0
        if gone < Self.sessionGap || p.model.isSealed || p.isReplay {
            p.model.thaw(now)
        } else if let store, let coordinator,
                  let outcome = store.log.outcomes.first(where: { $0.id == p.sessionID }) {
            // Ten minutes or more, not sealed: resume at the climax with the taps kept.
            let taps = p.model.tapTimes.count
            let built = DoneFlowBuilder.make(outcome: outcome, store: store, coordinator: coordinator, style: p.style, short: p.short, replay: false,
                                             resume: .init(atClimax: true, taps: taps), now: now, rotation: rotation)
            install(built.model, for: p.sessionID, isReplay: false, monthKey: p.monthKey)
            built.model.holdsCollapse = !p.rankUps.isEmpty
            p.model.onFinished = nil
            p.model.onLanded = nil
            presentation = Presentation(sessionID: p.sessionID, model: built.model, style: p.style, isReplay: false, dayKey: p.dayKey,
                                        monthKey: p.monthKey, short: p.short, rankUps: p.rankUps, cardFrame: p.cardFrame)
            saveProgress()
        } else {
            p.model.thaw(now)
        }
    }

    func sceneLeftForeground(now: Date = Date()) {
        guard data.backgroundedAt == nil else { return }
        data.backgroundedAt = now
        presentation?.model.freeze(now)
        saveProgress()
    }

    // MARK: Presenting the flow

    /// Opens today's pending flow. The shell checks the gate (Home visible, nothing over it).
    @discardableResult
    func presentFlow(store: AppStore, coordinator: GymSessionCoordinator, style: HeroCardStyle, now: Date = Date()) -> Bool {
        self.store = store
        self.coordinator = coordinator
        guard presentation == nil, standalone == nil, let pending = pendingFlow(now: now), let id = pending.flowSessionID else { return false }
        guard let outcome = store.log.outcomes.first(where: { $0.id == id && $0.counts }) else {
            var d = data
            Self.consume(id, in: &d)
            data = d
            return false
        }

        var resume: DoneFlowBuilder.Resume?
        var short = isShort
        if let pr = data.progress, pr.sessionID == id {
            short = pr.short
            if pr.sealed {
                // The count already landed before the app went away: done, quietly.
                finishSilently(sessionID: id, dayKey: pending.displayDay, now: now)
                return false
            }
            resume = .init(atClimax: true, taps: pr.taps)
        }

        let built = DoneFlowBuilder.make(outcome: outcome, store: store, coordinator: coordinator, style: style, short: short, replay: false,
                                         resume: resume, now: now, rotation: rotation)
        if let m = built.onceEver { rotation.spendOnceEver(m, dayKey: built.dayKey) }
        let rankUps = selectRankUps(for: id)
        built.model.holdsCollapse = !rankUps.isEmpty
        install(built.model, for: id, isReplay: false, monthKey: built.monthKey)
        presentation = Presentation(sessionID: id, model: built.model, style: style, isReplay: false, dayKey: built.dayKey,
                                    monthKey: built.monthKey, short: short, rankUps: rankUps, cardFrame: cardFrame)
        landedSessionID = nil
        data.sessionHadFlow = true
        saveProgress()
        return true
    }

    /// The verified card's replay: no rank-ups, a read-only month, the theme unchanged (§4.1 X).
    @discardableResult
    func replay(store: AppStore, coordinator: GymSessionCoordinator, style: HeroCardStyle, now: Date = Date()) -> Bool {
        self.store = store
        self.coordinator = coordinator
        guard canReplay(now: now), let id = data.replaySessionID,
              let outcome = store.log.outcomes.first(where: { $0.id == id }) else { return false }
        let built = DoneFlowBuilder.make(outcome: outcome, store: store, coordinator: coordinator, style: style, short: false, replay: true, now: now, rotation: rotation)
        install(built.model, for: id, isReplay: true, monthKey: built.monthKey)
        presentation = Presentation(sessionID: id, model: built.model, style: style, isReplay: true, dayKey: built.dayKey,
                                    monthKey: built.monthKey, short: false, rankUps: [], cardFrame: cardFrame)
        landedSessionID = nil
        return true
    }

    private func install(_ model: MatrixStoryModel, for id: UUID, isReplay: Bool, monthKey: String) {
        let rotation = self.rotation
        model.onProgress = { [weak self] in self?.saveProgress() }
        model.onLanded = { [weak self] in self?.landedSessionID = id }
        model.onFinished = { [weak self, weak model] in
            guard let self, let model else { return }
            self.finishFlow(model: model)
        }
        model.onHold = { [weak self] in self?.startRankUps() }
        if !isReplay {
            model.onPickTarget = { n in rotation.setMonthTarget(n, monthKey: monthKey) }
            model.onScreen = { [weak model] screen in
                if screen == .month, model?.monthPos == .last { rotation.noteRecap(monthKey: monthKey) }
            }
        }
    }

    /// The glass X or the swipe down: skip everything left, collapse at once.
    func close(now: Date = Date()) {
        guard let p = presentation else { return }
        if rankUp != nil {
            rankUp = nil
            quiet(p.rankUps)
            presentation?.rankUps = []
        }
        p.model.close(at: p.model.time(now))
    }

    private func saveProgress() {
        guard let p = presentation, !p.isReplay else { return }
        let m = p.model
        data.progress = FlowProgress(sessionID: p.sessionID, dayKey: p.dayKey, index: m.idx, taps: m.tapTimes.count,
                                     sealed: m.isSealed || m.closedEarly, savedAt: Date(), short: p.short)
    }

    private func finishFlow(model: MatrixStoryModel) {
        guard let p = presentation, p.model === model else { return }
        var d = data
        if !p.isReplay {
            Self.consume(p.sessionID, in: &d)
            d.progress = nil
            d.completedFlows += 1
            d.closedEarlyHistory.append(model.closedEarly)
            if d.closedEarlyHistory.count > 5 { d.closedEarlyHistory.removeFirst(d.closedEarlyHistory.count - 5) }
            d.replaySessionID = p.sessionID
            d.replayDayKey = p.dayKey
            // Built even when closed early (spec §4.3).
            if let theme = HeroTheme(rawValue: model.day) { rotation.markBuilt(theme, dayKey: p.dayKey) }
        }
        d.lastCelebrationEndedAt = Date()
        data = d
        if !p.rankUps.isEmpty { quiet(p.rankUps) }
        rankUp = nil
        presentation = nil
        flowEndCount += 1
    }

    private func finishSilently(sessionID: UUID, dayKey key: String, now: Date) {
        var d = data
        Self.consume(sessionID, in: &d)
        d.progress = nil
        d.replaySessionID = sessionID
        d.replayDayKey = key
        d.lastCelebrationEndedAt = now
        data = d
        if let store, let coordinator {
            let st = HeroMomentResolver.peek(store: store, coordinator: coordinator, now: now, rotation: rotation)
            rotation.markBuilt(st.theme, dayKey: key)
        }
        for p in data.pending where p.rankUpSessionID == sessionID {
            if let b = p.badgeID, let i = data.pending.firstIndex(of: p) { data.pending[i].kind = .rankUp(badgeID: b, sessionID: nil) }
        }
        flowEndCount += 1
    }

    private func discard(_ p: Presentation) {
        var d = data
        if !p.isReplay {
            Self.consume(p.sessionID, in: &d)
            d.progress = nil
        }
        data = d
        if !p.rankUps.isEmpty {
            for b in p.rankUps {
                data.pending.append(PendingCelebration(kind: .rankUp(badgeID: b, sessionID: nil), earnedAt: Date(), displayDay: dayKey()))
            }
        }
        p.model.onFinished = nil
        p.model.onLanded = nil
        presentation = nil
        rankUp = nil
        landedSessionID = p.sessionID
        flowEndCount += 1
    }

    // MARK: Rank-ups inside the flow

    /// Rule 2: the highest rung per ladder, ranked streak > days > achievement then tier; two at most,
    /// the lower shown first. The rest go quiet.
    private func selectRankUps(for sessionID: UUID) -> [String] {
        let attached = data.pending.filter { $0.rankUpSessionID == sessionID }.compactMap(\.badgeID)
        guard !attached.isEmpty else { return [] }
        let defs = attached.compactMap { id in BadgeCatalog.all.first { $0.id == id } }
        var top: [BadgeDefinition] = []
        var superseded: [String] = []
        for group in [BadgeGroup.streak, .days] {
            let ladder = defs.filter { $0.group == group }
            if let best = ladder.max(by: { (BadgeCatalog.all.firstIndex(of: $0) ?? 0) < (BadgeCatalog.all.firstIndex(of: $1) ?? 0) }) {
                top.append(best)
                superseded += ladder.filter { $0 != best }.map(\.id)
            }
        }
        top += defs.filter { $0.group == .achievement }.sorted { $0.tier.rank > $1.tier.rank }
        let ranked = top.sorted { a, b in
            let ga = Self.groupRank(a.group), gb = Self.groupRank(b.group)
            return ga == gb ? a.tier.rank > b.tier.rank : ga < gb
        }
        let shown = Array(ranked.prefix(2))
        let rest = ranked.dropFirst(2).map(\.id)
        // A lower rung of a ladder shown here is covered by the rank-up from its previous rung.
        BadgeStore.shared.markSeen(superseded)
        data.pending.removeAll { p in p.rankUpSessionID == sessionID }
        quiet(rest)
        return shown.reversed().map(\.id)
    }

    private static func groupRank(_ g: BadgeGroup) -> Int {
        switch g {
        case .streak: 0
        case .days: 1
        case .achievement: 2
        }
    }

    private func quiet(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        var d = data
        for b in ids where !d.quietBadges.contains(b) { d.quietBadges.append(b) }
        d.pending.removeAll { p in p.badgeID.map(ids.contains) ?? false }
        data = d
    }

    private func startRankUps() {
        guard let p = presentation, let first = p.rankUps.first, let def = BadgeCatalog.all.first(where: { $0.id == first }) else {
            presentation?.model.release(at: presentation?.model.time(Date()) ?? 0)
            return
        }
        rankUp = BadgeRankUpRequest(unlocking: def)
    }

    /// The tap after a rank-up's reveal: the next one, or the collapse 200 ms later.
    func continueRankUp() {
        guard var p = presentation, let current = rankUp else { return }
        BadgeStore.shared.markSeen([current.to.id])
        BadgeHaptics.shared.playLand()
        p.rankUps.removeAll { $0 == current.to.id }
        presentation = p
        if let next = p.rankUps.first, let def = BadgeCatalog.all.first(where: { $0.id == next }) {
            rankUp = BadgeRankUpRequest(unlocking: def)
        } else {
            rankUp = nil
            p.model.release(at: p.model.time(Date()))
        }
    }

    // MARK: Standalone rank-ups (rule 4)

    func standaloneCandidate(now: Date = Date()) -> PendingCelebration? {
        guard presentation == nil, standalone == nil, !hasPendingFlow else { return nil }
        guard !data.sessionHadFlow, !data.sessionHadStandalone else { return nil }
        if let ended = data.lastCelebrationEndedAt, let start = data.sessionStartedAt, start < ended.addingTimeInterval(Self.standaloneGap) { return nil }
        let open = data.pending.filter { p in
            guard p.badgeID != nil else { return false }
            guard now.timeIntervalSince(p.earnedAt) <= Self.rankUpLifetime else { return false }
            if let s = p.rankUpSessionID, data.pending.contains(where: { $0.flowSessionID == s }) { return false }
            return true
        }
        return open.max { a, b in
            guard let da = BadgeCatalog.all.first(where: { $0.id == a.badgeID }),
                  let db = BadgeCatalog.all.first(where: { $0.id == b.badgeID }) else { return false }
            let ga = Self.groupRank(da.group), gb = Self.groupRank(db.group)
            return ga == gb ? da.tier.rank < db.tier.rank : ga > gb
        }
    }

    @discardableResult
    func presentStandalone(now: Date = Date()) -> Bool {
        guard let p = standaloneCandidate(now: now), let b = p.badgeID,
              let def = BadgeCatalog.all.first(where: { $0.id == b }) else { return false }
        data.pending.removeAll { $0.id == p.id }
        data.sessionHadStandalone = true
        standalone = BadgeRankUpRequest(unlocking: def)
        return true
    }

    func standaloneLanded(_ request: BadgeRankUpRequest) {
        BadgeStore.shared.markSeen([request.to.id])
        data.lastCelebrationEndedAt = Date()
    }
}
