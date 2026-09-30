import ManagedSettings
import ManagedSettingsUI
import UIKit

final class GymLockShieldConfigExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration()
    }

    private func configuration() -> ShieldConfiguration {
        let owner = ShieldLedgerStore(defaults: GymLockScreenTime.defaults).current?.owner
        let subtitle = switch owner {
        case .windDown:
            "this app stays blocked until your wake time."
        case .gymSession:
            "this app stays blocked until you reach the gym or the session ends."
        case nil:
            "this app is blocked by your GymLock plan."
        }

        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterialLight,
            backgroundColor: UIColor(red: 0.980, green: 0.976, blue: 0.965, alpha: 1),
            icon: UIImage(systemName: "lock.fill"),
            title: .init(
                text: "gymlock is active",
                color: UIColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1)
            ),
            subtitle: .init(
                text: subtitle,
                color: UIColor(white: 0.42, alpha: 1)
            ),
            primaryButtonLabel: .init(text: "close app", color: UIColor.white),
            primaryButtonBackgroundColor: UIColor(red: 0.910, green: 0.365, blue: 0.306, alpha: 1)
        )
    }
}
