import SwiftUI
import StoreKit

/// System screen 22 — activation.
///
/// This is a paywall, and it is written as one without any of the usual tricks.
/// There is no countdown, no threat of losing the system they just built, and no
/// hidden pricing. The persuasion is supposed to come from the checklist: the
/// user configured all of it themselves over the previous twenty-one screens,
/// and this screen simply switches it on.
///
/// Every price, period and trial term is read from StoreKit's own localised
/// product data. When no products are configured the screen presents itself
/// without pricing rather than inventing any — an honest screen with no numbers
/// beats a convincing one with fake numbers.
struct ActivationPage: View {
    let isActive: Bool
    let onActivated: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(SubscriptionStore.self) private var subscriptions: SubscriptionStore?
    @Environment(\.openURL) private var openURL

    @State private var contentShown = false
    @State private var checksShown = false
    @State private var isRestoring = false

    private var profile: OnboardingProfile { store.profile }

    /// Each line names something the user actually chose.
    private var checklist: [String] {
        var items: [String] = [
            "\(profile.targetWorkoutsPerWeek) gym days / week",
            "persistent gym alarm",
            profile.alarmSoundLabel.lowercased(),
        ]

        if !profile.orderedDistractingApps.isEmpty {
            items.append("\(profile.lockedAppsSummary.lowercased()) lock")
        }

        items.append("gym + health verification")

        if profile.wantsNightLock {
            items.append("night lock at \(profile.bedtime.displayString.lowercased())")
        }
        if profile.comebackModeEnabled {
            items.append("comeback mode")
        }

        items.append("private progress timeline")
        return items
    }

    var body: some View {
        SystemScene(topAnchor: 0.07, contentSpacing: 16) {
            SceneHeading(
                title: "your GymLock is ready.",
                highlighted: ["is ready."],
                subtitle: "everything you just built is waiting for you.",
                size: 32
            )
            .staggered(0, isShown: contentShown)
        } content: {
            VStack(spacing: 16) {
                checklistCard
                    .staggered(1, isShown: contentShown)

                if let subscriptions, subscriptions.hasProducts {
                    planPicker(subscriptions)
                        .staggered(2, isShown: checksShown, step: 0.06)
                }
            }
        } footer: {
            footer
                .staggered(3, isShown: checksShown, step: 0.05)
        }
        .task(id: isActive) {
            guard isActive else {
                contentShown = false
                checksShown = false
                return
            }

            await subscriptions?.load()

            try? await Task.sleep(for: .milliseconds(170))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.settle) { contentShown = true }

            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            checksShown = true
        }
    }

    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(checklist.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 18)

                    Text(item)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .staggered(index, isShown: checksShown, step: 0.05)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
    }

    private func planPicker(_ subscriptions: SubscriptionStore) -> some View {
        VStack(spacing: 8) {
            ForEach(subscriptions.products, id: \.id) { product in
                planRow(product, isSelected: subscriptions.selectedID == product.id) {
                    subscriptions.select(product)
                }
            }
        }
    }

    private func planRow(_ product: Product, isSelected: Bool, select: @escaping () -> Void) -> some View {
        Button(action: select) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.border)

                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName.lowercased())
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(Theme.ink)

                    // The offer is described in the offer's own terms, taken
                    // straight from StoreKit — never paraphrased.
                    if let offer = product.introductoryOfferDescription {
                        Text(offer)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(product.displayPrice)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text(product.periodDescription)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                isSelected ? Theme.accent.opacity(0.07) : Theme.surface,
                in: .rect(cornerRadius: Theme.controlRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .strokeBorder(isSelected ? Theme.accent : Theme.border, lineWidth: isSelected ? 1.6 : 1)
            }
        }
        .buttonStyle(PressableRowStyle())
        .animation(Theme.stateChange, value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var footer: some View {
        VStack(spacing: 11) {
            Button {
                Task { await activate() }
            } label: {
                if subscriptions?.isPurchasing == true {
                    ProgressView().tint(.white)
                } else {
                    Text(ctaTitle)
                }
            }
            .buttonStyle(PrimaryCTAStyle(isEnabled: true))
            .disabled(subscriptions?.isPurchasing == true)

            if let terms = renewalTerms {
                Text(terms)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            // Secondary by weight and colour, but never hidden.
            HStack(spacing: 16) {
                Button {
                    Task { await restore() }
                } label: {
                    Text(isRestoring ? "restoring…" : "restore purchases")
                }
                .disabled(isRestoring)

                Link("terms", destination: URL(string: "https://rork.app/terms")!)
                Link("privacy", destination: URL(string: "https://rork.app/privacy")!)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.inkTertiary)
        }
    }

    /// Only claims a free trial when the selected product actually has one.
    private var ctaTitle: String {
        guard let product = subscriptions?.selectedProduct, product.hasFreeTrial else {
            return "activate GymLock"
        }
        return "start my free trial"
    }

    /// Plain renewal terms, assembled from the real product.
    private var renewalTerms: String? {
        guard let product = subscriptions?.selectedProduct else { return nil }

        let period = product.periodDescription.replacingOccurrences(of: "per ", with: "")
        if let offer = product.introductoryOfferDescription {
            return "\(offer), then \(product.displayPrice) per \(period). cancel any time in the App Store."
        }
        return "\(product.displayPrice) per \(period). cancel any time in the App Store."
    }

    // MARK: - Actions

    private func activate() async {
        // With products on hand this is a real purchase; without them the
        // system still switches on, because the user's configuration is theirs
        // either way.
        if let subscriptions, subscriptions.hasProducts {
            let succeeded = await subscriptions.purchase()
            guard succeeded else { return }
        }

        Haptics.commit()
        store.profile.hasActivated = true
        store.applyProfileToSchedule()
        onActivated()
    }

    private func restore() async {
        isRestoring = true
        await subscriptions?.restore()
        isRestoring = false

        if subscriptions?.isEntitled == true {
            Haptics.commit()
            store.profile.hasActivated = true
            store.applyProfileToSchedule()
            onActivated()
        }
    }
}
