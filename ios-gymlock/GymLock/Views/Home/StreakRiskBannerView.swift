import SwiftUI

/// The streak-at-risk banner on Home (FLOW, Flow 6).
///
/// Built only from existing pieces so the logic can be used and tested. The
/// real design comes later.
// PLACEHOLDER UI: designed in Step 3
struct StreakRiskBannerView: View {
    let banner: StreakRiskBanner
    let onReschedule: () -> Void
    let onHomeWorkout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(banner.line)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let freezeLine = banner.freezeLine {
                    Text(freezeLine)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            MorningPrimaryButton(
                title: StreakRiskBanner.rescheduleLabel,
                systemImage: "calendar.badge.clock",
                action: onReschedule
            )

            if banner.showsHomeWorkout {
                MorningChoiceRow(
                    title: banner.homeWorkoutLabel,
                    systemImage: "house.fill",
                    action: onHomeWorkout
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard(radius: 18)
        .accessibilityElement(children: .contain)
    }
}
