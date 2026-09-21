import SwiftUI

/// Edits the wind-down lock: whether it is on, and whether its window follows
/// the sleep rhythm or was tuned by hand.
///
/// Presented from the alarm settings screen. The equivalent window on the
/// morning plan screen is driven by the rhythm screen; this editor is where a
/// hand-tuned window is set, which is exactly the case
/// `RhythmChangeProposer` exists to protect.
struct WindDownEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss

    @State private var followsRhythm = true
    @State private var customStart = TimeOfDay(hour: 23, minute: 0)
    @State private var customEnd = TimeOfDay(hour: 6, minute: 30)
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        followsCard

                        if !followsRhythm {
                            customWheels
                        }

                        honestNote
                    }
                    .padding(.horizontal, Theme.pageMargin)
                    .padding(.vertical, 18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("wind-down lock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("cancel") { dismiss() }
                        .foregroundStyle(Theme.inkSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") {
                        Haptics.tap()
                        apply()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                }
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            followsRhythm = store.plan.nightLock.followsRhythm
            customStart = store.plan.nightLock.customStart
            customEnd = store.plan.nightLock.customEnd
        }
    }

    // MARK: - Cards

    private var followsCard: some View {
        Toggle(isOn: Binding(
            get: { followsRhythm },
            set: { followsRhythm = $0; Haptics.selection() }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("follow your sleep times")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(followsRhythm ? "bedtime to wake time, updated automatically" : "set your own window")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .warmCard(radius: 18)
    }

    private var customWheels: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                Text("locks at")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TimeWheel(time: $customStart, accessibilityTitle: "Wind-down start")
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .warmCard(radius: 18)

            VStack(spacing: 10) {
                Text("unlocks at")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TimeWheel(time: $customEnd, accessibilityTitle: "Wind-down end")
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .warmCard(radius: 18)
        }
    }

    /// Copy matches what the build actually does. The lock engages when
    /// GymLock next runs inside the window, so the heads-up notification is
    /// what makes that next run happen. When a `DeviceActivityMonitor`
    /// extension lands, this line becomes a straight promise.
    private var honestNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)

            Text("a heads-up arrives when the window starts. apps lock when you next open gymlock after that.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceMuted, in: .rect(cornerRadius: 14))
    }

    // MARK: - Actions

    private func apply() {
        store.plan.nightLock.followsRhythm = followsRhythm
        store.plan.nightLock.customStart = customStart
        store.plan.nightLock.customEnd = customEnd
        // A window that follows the rhythm re-syncs from it; a hand-tuned
        // window keeps exactly what was just set.
        if followsRhythm {
            store.applyRhythmToNightLock()
        }
        // Someone setting the window at 11:15 while standing inside it should
        // see the lock go on without a relaunch.
        coordinator.reconcileWindDown()
    }
}
