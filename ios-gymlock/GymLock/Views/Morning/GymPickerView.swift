import CoreLocation
import SwiftUI

/// Choosing the gym — the one extra thing the user ever configures.
///
/// Deliberately a search field and a list rather than a map with a draggable
/// pin. People know the name of their gym; almost nobody knows where it sits on
/// an unlabelled map, and a pin they place by eye is a pin that unlocks their
/// apps in the wrong car park. Search results carry a real coordinate from
/// Apple's own data.
///
/// Nothing here mentions geofences, radii, or metres. Those are engineering
/// details the user should never have to hold in their head.
struct GymPickerView: View {
    let onPicked: (GymLocation) -> Void
    var onSkip: (() -> Void)?

    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss

    @State private var search = GymSearchService()
    @State private var term = ""
    @State private var userCoordinate: CLLocationCoordinate2D?
    @FocusState private var isFocused: Bool

    var body: some View {
        MorningScreen(
            trailingTitle: onSkip == nil ? nil : "Skip",
            trailingAction: onSkip
        ) {
            VStack(alignment: .leading, spacing: 20) {
                heading
                searchField
                permissionNote
                results
            }
        } footer: {
            if let existing = store.primaryGym {
                currentGymFooter(existing)
            }
        }
        .task {
            coordinator.arrival.refreshAvailability()
            userCoordinate = CLLocationManager().location?.coordinate
        }
        .onChange(of: term) { _, new in
            search.search(new, near: userCoordinate)
        }
    }

    // MARK: - Pieces

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("where do you train?")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Theme.ink)

            Text("GymLock uses your location to know when you actually reached the gym — that's what unlocks your apps.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)

            TextField("search your gym", text: $term)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)

            if search.isSearching {
                ProgressView().controlSize(.small).tint(Theme.accent)
            } else if !term.isEmpty {
                Button {
                    term = ""
                    search.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isFocused ? Theme.accent.opacity(0.5) : Theme.border, lineWidth: 1)
        }
        .animation(Theme.stateChange, value: isFocused)
    }

    /// Explains the location ask in one plain sentence, and only when it is
    /// actually relevant.
    @ViewBuilder
    private var permissionNote: some View {
        switch coordinator.arrival.availability {
        case .denied:
            noteCard(
                icon: "location.slash.fill",
                title: "location is off",
                detail: "automatic gym unlock needs it. you can still pick your gym now and turn location on afterwards.",
                action: ("Open Settings", openSettings)
            )

        case .whenInUseOnly:
            noteCard(
                icon: "location.fill",
                title: "one more step after this",
                detail: "GymLock needs background location so it can notice you arrived without you opening the app.",
                action: ("Allow", { coordinator.arrival.requestAlways() })
            )

        case .unknown:
            noteCard(
                icon: "location.fill",
                title: "location needed",
                detail: "so GymLock knows when you reached the gym.",
                action: ("Allow", { coordinator.arrival.requestWhenInUse() })
            )

        case .ready, .unsupported:
            EmptyView()
        }
    }

    private func noteCard(
        icon: String,
        title: String,
        detail: String,
        action: (label: String, run: () -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let action {
                    Button(action.label) {
                        Haptics.tap()
                        action.run()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.07), in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var results: some View {
        if let failure = search.failureMessage, !term.isEmpty {
            Text(failure)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)
        }

        VStack(spacing: 10) {
            ForEach(search.results) { result in
                resultRow(result)
            }
        }
    }

    private func resultRow(_ result: GymSearchResult) -> some View {
        Button {
            Haptics.medium()
            isFocused = false
            onPicked(result.asGymLocation())
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 42, height: 42)
                    .background(Theme.accent.opacity(0.12), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    if !result.subtitle.isEmpty {
                        Text(result.subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if let distance = result.distanceLabel {
                    Text(distance)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MorningCardStyle())
    }

    private func currentGymFooter(_ gym: GymLocation) -> some View {
        VStack(spacing: 8) {
            Text("currently: \(gym.name)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
                .lineLimit(1)

            Button("keep this gym") {
                Haptics.tap()
                dismiss()
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.accent)
        }
        .padding(.bottom, 6)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
