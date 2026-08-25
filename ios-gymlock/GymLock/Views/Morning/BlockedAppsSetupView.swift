import SwiftUI

#if canImport(FamilyControls)
import FamilyControls
#endif

/// Choosing what GymLock actually blocks. Asked once, then never again.
///
/// Onboarding already asked which apps usually win — that answer shapes the
/// story, the lock demonstration, and the copy throughout. But real blocking
/// cannot use it: Apple's Screen Time model is deliberately privacy-preserving,
/// and an app is not allowed to know which apps you have or name them itself.
/// The user has to pick through Apple's own picker, which hands back opaque
/// tokens GymLock can shield but never read.
///
/// So this screen exists to bridge the two: it shows what the user already told
/// us, then asks them to point Apple's picker at the same things.
struct BlockedAppsSetupView: View {
    let onDone: () -> Void
    var onSkip: (() -> Void)?

    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator

    @State private var isPresentingPicker = false
    @State private var isRequesting = false

    #if canImport(FamilyControls)
    @State private var selection = FamilyActivitySelection()
    #endif

    private var shield: any AppShielding { coordinator.shield }

    var body: some View {
        MorningScreen(
            trailingTitle: onSkip == nil ? nil : "Skip",
            trailingAction: onSkip
        ) {
            VStack(alignment: .leading, spacing: 20) {
                heading
                if !store.profile.orderedDistractingApps.isEmpty { reminderStrip }
                statusCard
                if shield.capability == .demo { demoNotice }
            }
        } footer: {
            footer
        }
        .task {
            shield.refreshAuthorization()
            loadExistingSelection()
        }
        #if canImport(FamilyControls)
        .familyActivityPicker(isPresented: $isPresentingPicker, selection: $selection)
        .onChange(of: selection) { _, new in
            guard let real = shield as? FamilyControlsShieldService else { return }
            real.updateSelection(new)
            store.hasConfiguredBlockedApps = real.hasSelection
        }
        #endif
    }

    // MARK: - Pieces

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("choose what GymLock should block during gym time")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)

            Text("you'll only do this once. these apps go away when your alarm rings and come back the moment you reach the gym.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the user already told us, shown so the picker feels like a
    /// continuation rather than a repeat.
    private var reminderStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("you told us these usually win")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)

            HStack(spacing: 10) {
                ForEach(store.profile.orderedDistractingApps.prefix(6)) { app in
                    AppGlyph(app: app, size: 42)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceMuted, in: .rect(cornerRadius: 18))
    }

    @ViewBuilder
    private var statusCard: some View {
        switch shield.authorization {
        case .approved:
            selectionCard

        case .denied, .revoked:
            infoCard(
                icon: "lock.slash.fill",
                title: shield.authorization == .revoked
                    ? "Screen Time access was turned off"
                    : "Screen Time access is off",
                detail: "GymLock can't block anything without it. Everything else still works — you'll just have to close the apps yourself."
            )

        case .unavailable:
            infoCard(
                icon: "iphone.slash",
                title: "blocking isn't available on this device",
                detail: "the rest of your morning works exactly the same."
            )

        case .notDetermined:
            infoCard(
                icon: "shield.lefthalf.filled",
                title: "GymLock needs Screen Time permission",
                detail: "that's what lets it hide the apps you chose while you get to the gym."
            )
        }
    }

    private var selectionCard: some View {
        HStack(spacing: 14) {
            Image(systemName: shield.hasSelection ? "checkmark.shield.fill" : "shield")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(shield.hasSelection ? Theme.accent : Theme.inkTertiary)
                .frame(width: 46, height: 46)
                .background(
                    (shield.hasSelection ? Theme.accent : Theme.inkTertiary).opacity(0.12),
                    in: .circle
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(shield.hasSelection ? "\(shield.selectionCount) selected" : "nothing selected yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                Text(shield.hasSelection
                    ? "these will be blocked during gym time."
                    : "pick the apps and categories to block.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard(radius: 18)
    }

    private func infoCard(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceMuted, in: .rect(cornerRadius: 18))
    }

    /// Says plainly that nothing is being blocked yet.
    ///
    /// This is the difference between a demo and a lie. A user testing on the
    /// simulator, or on a build without Apple's entitlement, must not come away
    /// believing their apps will actually disappear tomorrow morning.
    private var demoNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)

            VStack(alignment: .leading, spacing: 4) {
                Text("demo mode")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("this build can run the whole morning, but it can't actually block other apps yet. real blocking needs Apple's Screen Time approval.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceMuted, in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var footer: some View {
        switch shield.authorization {
        case .approved:
            VStack(spacing: 10) {
                MorningPrimaryButton(
                    title: shield.hasSelection ? "change what's blocked" : "choose apps",
                    systemImage: "square.grid.2x2.fill",
                    trailingImage: nil
                ) {
                    presentPicker()
                }

                if shield.hasSelection {
                    Button("done") {
                        Haptics.tap()
                        store.hasConfiguredBlockedApps = true
                        onDone()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(height: 30)
                }
            }

        case .denied, .revoked, .unavailable:
            MorningPrimaryButton(title: "continue without blocking", systemImage: nil) {
                store.hasConfiguredBlockedApps = true
                onDone()
            }

        case .notDetermined:
            MorningPrimaryButton(
                title: isRequesting ? "asking…" : "allow Screen Time",
                systemImage: "shield.fill",
                trailingImage: nil,
                isEnabled: !isRequesting
            ) {
                Task {
                    isRequesting = true
                    let result = await shield.requestAuthorization()
                    isRequesting = false
                    // Straight into the picker on success: two taps for a
                    // one-time setup is one tap too many.
                    if result == .approved { presentPicker() }
                }
            }
        }
    }

    // MARK: - Actions

    private func presentPicker() {
        #if canImport(FamilyControls)
        if shield is FamilyControlsShieldService {
            isPresentingPicker = true
            return
        }
        #endif

        // Demo mode has no real picker to show, so it records a plausible
        // selection and clearly says nothing is actually being blocked.
        if let demo = shield as? DemoShieldService {
            let count = max(1, store.profile.orderedDistractingApps.count)
            demo.setDemoSelection(count: count)
            store.hasConfiguredBlockedApps = true
            Haptics.commit()
            onDone()
        }
    }

    private func loadExistingSelection() {
        #if canImport(FamilyControls)
        guard let real = shield as? FamilyControlsShieldService else { return }
        selection = real.selection
        #endif
    }
}
