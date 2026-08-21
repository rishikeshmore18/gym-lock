import SwiftUI

/// System screen 8 — what takes the time instead.
///
/// A grid rather than a list, because these are icons and icons are recognised
/// far faster than their names. This screen is personalisation only: it does not
/// ask for Screen Time permission, and nothing here blocks anything yet. The
/// apps chosen become the ones the user watches lock and unlock on screens 18
/// and 19.
struct DistractingAppsPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @Environment(AppStore.self) private var store

    @State private var contentShown = false

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private var chosen: Set<DistractingApp> { store.profile.selectedDistractingApps }

    var body: some View {
        @Bindable var store = store

        SystemScene(topAnchor: 0.08, contentSpacing: 18) {
            SceneHeading(
                title: "which apps usually get the time instead?",
                highlighted: ["get the time"],
                subtitle: "select all that apply"
            )
            .staggered(0, isShown: contentShown)
        } content: {
            VStack(spacing: 12) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(DistractingApp.displayOrder.enumerated()), id: \.element.id) { index, app in
                        appTile(app)
                            .staggered(index + 1, isShown: contentShown, step: 0.05)
                    }
                }

                OtherDetailField(
                    placeholder: "which app or type of app?",
                    text: $store.profile.distractingAppOther,
                    isShown: chosen.contains(.other)
                )
            }
        } footer: {
            SceneContinueButton(
                caption: chosen.isEmpty
                    ? "pick the ones that actually win."
                    : "we'll lock these during your gym window.",
                isEnabled: !chosen.isEmpty,
                action: onContinue
            )
            .staggered(10, isShown: contentShown)
        }
        .task(id: isActive) { await reveal(isActive: isActive, into: $contentShown) }
    }

    private func appTile(_ app: DistractingApp) -> some View {
        let isSelected = chosen.contains(app)

        return Button {
            toggle(app)
        } label: {
            HStack(spacing: 11) {
                AppGlyph(app: app, size: 38)

                Text(app.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Theme.accent.opacity(0.08) : Theme.surface,
                in: .rect(cornerRadius: Theme.controlRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .strokeBorder(
                        isSelected ? Theme.accent : Theme.border,
                        lineWidth: isSelected ? 1.6 : 1
                    )
            }
        }
        .buttonStyle(PressableRowStyle())
        .animation(Theme.stateChange, value: isSelected)
        .accessibilityLabel(app.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func toggle(_ app: DistractingApp) {
        Haptics.tap()
        withAnimation(Theme.stateChange) {
            if store.profile.selectedDistractingApps.contains(app) {
                store.profile.selectedDistractingApps.remove(app)
            } else {
                store.profile.selectedDistractingApps.insert(app)
            }
        }
    }
}
