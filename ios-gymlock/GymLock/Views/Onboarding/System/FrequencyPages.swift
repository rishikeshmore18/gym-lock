import SwiftUI

/// System screen 3 — the target.
///
/// The number the user *wants*. Asked before the honest number, because being
/// asked for the ambition first makes the second question feel like calibration
/// rather than an audit.
struct TargetFrequencyPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @Environment(AppStore.self) private var store

    @State private var contentShown = false

    /// One through seven — zero is not a target anyone sets.
    private static let values = Array(1...7)

    var body: some View {
        @Bindable var store = store

        SystemScene(topAnchor: 0.10) {
            SceneHeading(
                title: "how many days do you want to show up?",
                highlighted: ["do you want"],
                subtitle: "days / week"
            )
            .staggered(0, isShown: contentShown)
        } content: {
            VStack(spacing: 14) {
                ValueWheel(
                    labels: Self.values.map(String.init),
                    selection: Binding(
                        get: { (store.profile.targetWorkoutsPerWeek - 1).clamped(to: 0...6) },
                        set: { store.profile.targetWorkoutsPerWeek = $0 + 1 }
                    ),
                    rowHeight: 46,
                    activeSize: 60,
                    accessibilityTitle: "Target days per week"
                )

                Text("minimum recommended: 3 days / week")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .frame(maxWidth: .infinity)
            }
            .staggered(1, isShown: contentShown)
        } footer: {
            SceneContinueButton(action: onContinue)
                .staggered(2, isShown: contentShown)
        }
        .task(id: isActive) { await reveal(isActive: isActive, into: $contentShown) }
    }
}

/// System screen 4 — the truth.
///
/// The same wheel as the previous screen, deliberately: putting the honest
/// number on an identical control makes the gap between the two something the
/// user reads for themselves, and screen 15 will later do the arithmetic.
struct CurrentFrequencyPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @Environment(AppStore.self) private var store

    @State private var contentShown = false

    /// Zero is a real and common answer here, so the range starts there.
    private static let values = Array(0...7)

    var body: some View {
        @Bindable var store = store

        SystemScene(topAnchor: 0.10) {
            SceneHeading(
                title: "how many workouts do you actually make right now?",
                highlighted: ["actually make"],
                subtitle: "days / week"
            )
            .staggered(0, isShown: contentShown)
        } content: {
            VStack(spacing: 14) {
                ValueWheel(
                    labels: Self.values.map(String.init),
                    selection: Binding(
                        get: { store.profile.currentWorkoutsPerWeek.clamped(to: 0...7) },
                        set: { store.profile.currentWorkoutsPerWeek = $0 }
                    ),
                    rowHeight: 46,
                    activeSize: 60,
                    accessibilityTitle: "Current workouts per week"
                )

                Text("be honest. this helps us build around your real week.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .staggered(1, isShown: contentShown)
        } footer: {
            SceneContinueButton(action: onContinue)
                .staggered(2, isShown: contentShown)
        }
        .task(id: isActive) { await reveal(isActive: isActive, into: $contentShown) }
    }
}

// MARK: - Shared helpers

extension Comparable {
    /// Keeps a value inside a range, used to guard persisted values that a
    /// future build might widen or narrow.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// The standard question entrance: a short beat after arrival, then the whole
/// block staggers in. Shared so every question screen breathes identically.
@MainActor
func reveal(isActive: Bool, into flag: Binding<Bool>, delay: Duration = .milliseconds(180)) async {
    guard isActive else {
        flag.wrappedValue = false
        return
    }

    try? await Task.sleep(for: delay)
    guard !Task.isCancelled else { return }
    withAnimation(Theme.settle) { flag.wrappedValue = true }
}
