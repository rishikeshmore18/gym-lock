import FamilyControls
import Foundation
import ManagedSettings

enum GymLockFamilySelection {
    static func load(from defaults: UserDefaults = GymLockScreenTime.defaults) -> FamilyActivitySelection {
        guard let data = defaults.data(forKey: GymLockScreenTime.selectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return selection
    }

    static func save(
        _ selection: FamilyActivitySelection,
        to defaults: UserDefaults = GymLockScreenTime.defaults
    ) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: GymLockScreenTime.selectionKey)
    }

    static func count(_ selection: FamilyActivitySelection) -> Int {
        selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
    }

    static func apply(
        _ selection: FamilyActivitySelection,
        to store: ManagedSettingsStore
    ) {
        store.shield.applications = selection.applicationTokens.isEmpty
            ? nil
            : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil
            : selection.webDomainTokens
    }
}
