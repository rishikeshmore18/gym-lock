import Foundation
import Observation

/// Where the user currently is in the app's lifecycle.
enum AppStage: String, Codable {
    case onboarding
    case scheduleSetup
    case home
}

/// Single source of truth for user-entered onboarding data, the schedule,
/// and which stage of the app should be on screen.
///
/// Persistence is deliberately narrow: only values the user would expect to
/// survive a relaunch are written to `UserDefaults`.
@Observable
final class AppStore {
    private enum Key {
        static let name = "gymlock.userName"
        static let stage = "gymlock.stage"
        static let schedule = "gymlock.schedule"
        static let profile = "gymlock.profile"
    }

    private let defaults: UserDefaults

    var userName: String {
        didSet { defaults.set(userName, forKey: Key.name) }
    }

    var stage: AppStage {
        didSet { defaults.set(stage.rawValue, forKey: Key.stage) }
    }

    var schedule: GymSchedule {
        didSet { persistSchedule() }
    }

    /// Everything the user told GymLock while building their system.
    var profile: OnboardingProfile {
        didSet { persistProfile() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        userName = defaults.string(forKey: Key.name) ?? ""

        if let raw = defaults.string(forKey: Key.stage), let stored = AppStage(rawValue: raw) {
            stage = stored
        } else {
            stage = .onboarding
        }

        if let data = defaults.data(forKey: Key.schedule),
           let decoded = try? JSONDecoder().decode(GymSchedule.self, from: data) {
            schedule = decoded
        } else {
            schedule = .default
        }

        if let data = defaults.data(forKey: Key.profile),
           let decoded = try? JSONDecoder().decode(OnboardingProfile.self, from: data) {
            profile = decoded
        } else {
            profile = .default
        }
    }

    /// Trimmed display name, falling back to a neutral greeting target.
    var greetingName: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "friend" : trimmed
    }

    var hasName: Bool {
        !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toggleTrainingDay(_ day: Weekday) {
        var days = schedule.trainingDays
        if days.contains(day) {
            days.remove(day)
        } else {
            days.insert(day)
        }
        schedule.trainingDays = days
    }

    private func persistSchedule() {
        guard let data = try? JSONEncoder().encode(schedule) else { return }
        defaults.set(data, forKey: Key.schedule)
    }

    private func persistProfile() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: Key.profile)
    }

    /// Folds the onboarding answers into the live schedule the rest of the app
    /// runs on, so the home screen reflects the system the user just built
    /// rather than the defaults.
    ///
    /// Training days are chosen by spreading the requested count across the week
    /// with rest days in between, which is a far better starting point than the
    /// first N weekdays and is still fully editable later.
    func applyProfileToSchedule() {
        schedule.gymTime = profile.failureTime
        if profile.wantsNightLock {
            schedule.bedtime = profile.bedtime
        }
        schedule.trainingDays = Self.spreadTrainingDays(count: profile.targetWorkoutsPerWeek)
    }

    /// Picks `count` days spread as evenly as possible across the week.
    static func spreadTrainingDays(count: Int) -> Set<Weekday> {
        let ordered = Weekday.allCases
        let clamped = min(max(count, 1), ordered.count)
        guard clamped < ordered.count else { return Set(ordered) }

        let stride = Double(ordered.count) / Double(clamped)
        let picked = (0..<clamped).map { step -> Weekday in
            let index = min(ordered.count - 1, Int((Double(step) * stride).rounded(.down)))
            return ordered[index]
        }
        return Set(picked)
    }

    /// Wipes stored progress. Used by the developer reset affordance in Settings.
    func resetAll() {
        userName = ""
        schedule = .default
        profile = .default
        stage = .onboarding
    }
}
