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

    /// Wipes stored progress. Used by the developer reset affordance in Settings.
    func resetAll() {
        userName = ""
        schedule = .default
        stage = .onboarding
    }
}
