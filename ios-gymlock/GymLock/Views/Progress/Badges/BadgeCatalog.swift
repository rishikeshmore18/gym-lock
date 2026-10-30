//
//  BadgeCatalog.swift
//  GymLock — Badges
//
//  The 30 badges: names, rules, tiers, groups, and the ladder logic.
//  Images live in the app bundle as <id>.webp (see BadgeArt.swift).
//

import SwiftUI

enum BadgeTier: String, CaseIterable, Codable {
    case bronze, copper, silver, chrome, gold, platinum, diamond, amethyst, obsidian, immortal

    /// 0…9 — drives ornament level and effect intensity in the rank-up.
    var rank: Int { BadgeTier.allCases.firstIndex(of: self)! }

    /// Accent used by the rank-up effects (rays, glow, sparks, label, tier chip).
    var accentRGB: (r: Double, g: Double, b: Double) {
        switch self {
        case .bronze:   return (255, 157, 92)
        case .copper:   return (255, 143, 122)
        case .silver:   return (232, 238, 248)
        case .chrome:   return (213, 224, 242)
        case .gold:     return (255, 201, 74)
        case .platinum: return (127, 184, 255)
        case .diamond:  return (124, 200, 255)
        case .amethyst: return (157, 125, 255)
        case .obsidian: return (255, 201, 74)
        case .immortal: return (196, 140, 255)
        }
    }

    var accent: Color { Color(.sRGB, red: accentRGB.r / 255, green: accentRGB.g / 255, blue: accentRGB.b / 255, opacity: 1) }
    func accent(_ opacity: Double) -> Color { accent.opacity(opacity) }

    /// Rainbow particles for the top tier.
    var isPrism: Bool { self == .immortal }
}

enum BadgeGroup: String, CaseIterable, Codable {
    case streak, days, achievement

    var title: String {
        switch self {
        case .streak: return "Streak"
        case .days: return "Workout Days"
        case .achievement: return "Achievements"
        }
    }
}

struct BadgeDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let group: BadgeGroup
    let tier: BadgeTier
    let number: Int?        // ladder badges show their threshold
    let rule: String        // line under the name

    var isLadder: Bool { group != .achievement }
}

enum BadgeCatalog {
    private static func streak(_ id: String, _ name: String, _ weeks: Int, _ tier: BadgeTier) -> BadgeDefinition {
        BadgeDefinition(id: id, name: name, group: .streak, tier: tier, number: weeks, rule: "\(weeks) WEEK STREAK")
    }
    private static func days(_ id: String, _ name: String, _ n: Int, _ tier: BadgeTier) -> BadgeDefinition {
        BadgeDefinition(id: id, name: name, group: .days, tier: tier, number: n, rule: "\(n) WORKOUT DAYS")
    }
    private static func ach(_ id: String, _ name: String, _ tier: BadgeTier, _ rule: String) -> BadgeDefinition {
        BadgeDefinition(id: id, name: name, group: .achievement, tier: tier, number: nil, rule: rule)
    }

    /// Only badges the record can prove. Three from the kit are left out until
    /// the app keeps the data they need: No Excuses (a reschedule is never
    /// linked to its makeup), Perfect Week (the planned weekdays of past weeks
    /// are not kept) and Freeze Saver (refunds are not recorded).
    static let all: [BadgeDefinition] = [
        // streak ladder (each rung implies the ones below it)
        streak("first-lock", "First Lock", 1, .bronze),
        streak("momentum", "Momentum", 2, .silver),
        streak("locked-in", "Locked In", 4, .gold),
        streak("habit-builder", "Habit Builder", 8, .copper),
        streak("getting-serious", "Getting Serious", 12, .chrome),
        streak("half-year", "Half Year", 26, .platinum),
        streak("year-one", "Year One", 52, .diamond),
        streak("relentless", "Relentless", 78, .amethyst),
        streak("iron-habit", "Iron Habit", 104, .obsidian),
        streak("immortal", "Immortal", 156, .immortal),
        // workout-days ladder
        days("showed-up", "Showed Up", 3, .bronze),
        days("ten-strong", "Ten Strong", 10, .silver),
        days("quarter-century", "Quarter Century", 25, .gold),
        days("fifty-club", "Fifty Club", 50, .platinum),
        days("century", "Century", 100, .amethyst),
        // achievements (independent)
        ach("first-proof", "First Proof", .bronze, "First verified gym workout."),
        ach("home-hero", "Home Hero", .silver, "First verified home workout."),
        ach("health-synced", "Health Synced", .gold, "First workout verified by Apple Health."),
        ach("comeback", "Comeback", .bronze, "Keep a week again after a break."),
        ach("second-wind", "Second Wind", .silver, "Work out again after 14 or more days away."),
        ach("overachiever", "Overachiever", .gold, "Finish one extra counted workout beyond the weekly goal."),
        ach("recovery", "Recovery", .amethyst, "Keep the week immediately after a frozen week."),
        ach("sunrise", "Sunrise", .gold, "Start a counted workout before 7 AM."),
        ach("night-owl", "Night Owl", .bronze, "Finish a counted workout after 9 PM."),
        ach("gym-regular", "Gym Regular", .silver, "Reach 25 verified gym workouts."),
        ach("home-saver", "Home Saver", .gold, "A home workout that completes the weekly goal."),
        ach("clean-run", "Clean Run", .diamond, "8 kept weeks without using a freeze."),
    ]

    static func badge(_ id: String) -> BadgeDefinition {
        guard let b = all.first(where: { $0.id == id }) else { fatalError("Unknown badge id \(id)") }
        return b
    }

    static func badges(in group: BadgeGroup) -> [BadgeDefinition] { all.filter { $0.group == group } }

    /// Previous rung on the same ladder — the rank-up shows the old rank turning into the new one.
    static func previousRung(of b: BadgeDefinition) -> BadgeDefinition? {
        guard b.isLadder else { return nil }
        let ladder = badges(in: b.group)
        guard let i = ladder.firstIndex(of: b), i > 0 else { return nil }
        return ladder[i - 1]
    }

    /// Unlocking a rung also unlocks every rung below it (a 26-week streak includes 1…12).
    static func impliedUnlocks(for b: BadgeDefinition) -> [String] {
        guard b.isLadder else { return [b.id] }
        let ladder = badges(in: b.group)
        guard let i = ladder.firstIndex(of: b) else { return [b.id] }
        return ladder[0...i].map(\.id)
    }
}
