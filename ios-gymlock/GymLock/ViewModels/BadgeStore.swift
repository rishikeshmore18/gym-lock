import Foundation
import Observation

/// The badges as the screens see them.
///
/// States are rebuilt from the record on every refresh. Two things are kept,
/// and only because the record cannot answer them: which badges have been
/// earned (so one never disappears when the ledger trims its oldest
/// outcomes) and which the user has already seen unlock (so the reveal plays
/// once and never again).
@Observable
final class BadgeStore {
    struct Record: Codable, Hashable {
        var unlockedOn: Date?
        var seen: Bool
    }

    static let recordsKey = "gymlock.badges.records"

    private(set) var states: [String: BadgeState] = [:]
    private(set) var records: [String: Record]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.recordsKey),
           let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = decoded
        } else {
            records = [:]
        }
    }

    // MARK: Reading

    func state(for id: String) -> BadgeState {
        states[id] ?? records[id].map { .earned(on: $0.unlockedOn) } ?? .locked(nil)
    }

    var earnedCount: Int {
        BadgeCatalog.all.filter { state(for: $0.id).isEarned }.count
    }

    /// The most recently earned badge, shown on the Progress tile.
    ///
    /// Latest unlock date wins; a badge with no known date sorts before dated
    /// ones. Ties (several unlocked the same day, or none dated) go to the
    /// higher tier, then the later rung in the catalog.
    var latestEarned: BadgeDefinition? {
        let earned = BadgeCatalog.all.enumerated().compactMap { index, badge -> (BadgeDefinition, Date?, Int)? in
            guard case let .earned(date) = state(for: badge.id) else { return nil }
            return (badge, date, index)
        }
        return earned.max { lhs, rhs in
            let l = lhs.1 ?? .distantPast, r = rhs.1 ?? .distantPast
            if l != r { return l < r }
            if lhs.0.tier.rank != rhs.0.tier.rank { return lhs.0.tier.rank < rhs.0.tier.rank }
            return lhs.2 < rhs.2
        }?.0
    }

    /// Earned badges whose unlock the user has not seen yet.
    var unseenEarned: [String] {
        BadgeCatalog.all.map(\.id).filter { state(for: $0).isEarned && records[$0]?.seen != true }
    }

    /// The one unseen badge worth the full reveal: the highest tier, and on a
    /// tie the later one in the catalog (the higher rung).
    func headlineReveal(among ids: [String]) -> String? {
        let order = BadgeCatalog.all
        return ids
            .compactMap { id in order.firstIndex { $0.id == id }.map { (id, $0) } }
            .max { lhs, rhs in
                let l = order[lhs.1].tier.rank, r = order[rhs.1].tier.rank
                return l == r ? lhs.1 < rhs.1 : l < r
            }?.0
    }

    // MARK: Updating

    func refresh(store: AppStore, now: Date = Date(), calendar: Calendar = .current) {
        let facts = BadgeEngine.facts(
            log: store.log,
            plan: store.plan,
            schedule: store.schedule,
            vault: store.streakVault,
            now: now,
            calendar: calendar
        )
        apply(BadgeRules.states(for: facts))
    }

    /// Merges freshly derived states with what has been earned before.
    func apply(_ derived: [String: BadgeState]) {
        var next = derived
        var changed = false
        for badge in BadgeCatalog.all {
            let id = badge.id
            if case let .earned(date) = derived[id] ?? .locked(nil) {
                var record = records[id] ?? Record(unlockedOn: date, seen: false)
                if record.unlockedOn == nil, let date { record.unlockedOn = date }
                if records[id] != record {
                    records[id] = record
                    changed = true
                }
                next[id] = .earned(on: record.unlockedOn)
            } else if let record = records[id] {
                next[id] = .earned(on: record.unlockedOn)
            }
        }
        if states != next { states = next }
        if changed { persist() }
    }

    func markSeen<S: Sequence>(_ ids: S) where S.Element == String {
        var changed = false
        for id in ids {
            guard var record = records[id], !record.seen else { continue }
            record.seen = true
            records[id] = record
            changed = true
        }
        if changed { persist() }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Self.recordsKey)
    }
}
