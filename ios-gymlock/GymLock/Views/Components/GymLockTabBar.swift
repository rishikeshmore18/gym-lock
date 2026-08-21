import SwiftUI

/// The four destinations of the app shell.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case alarm
    case progress
    case profile

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: "Home"
        case .alarm: "Alarm"
        case .progress: "Progress"
        case .profile: "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .alarm: "alarm.fill"
        case .progress: "chart.bar.fill"
        case .profile: "person.fill"
        }
    }
}

/// A floating charcoal pill with one expanded white capsule.
///
/// The capsule is a single view that moves between slots with
/// `matchedGeometryEffect`, so selecting a tab *travels* — the old capsule
/// collapses into an icon as the new one opens, rather than two rectangles
/// swapping visibility. Widths are laid out so the expanded tab takes whatever
/// space is left after the three collapsed icons, which means it can never push
/// a sibling out of the bar, however narrow the phone.
struct GymLockTabBar: View {
    @Binding var selection: AppTab

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var capsule

    /// Fixed footprint of a collapsed tab. Three of these plus the container
    /// padding is the worst case, and it fits comfortably on a 320pt screen.
    private let collapsedWidth: CGFloat = 46

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(5)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Theme.logoBackdrop.opacity(0.94))
                .background {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        }
        .accessibilityElement(children: .contain)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isActive = selection == tab

        return Button {
            guard selection != tab else { return }
            Haptics.tap()
            // High damping: it settles rather than wobbles.
            withAnimation(
                reduceMotion
                    ? .easeInOut(duration: 0.18)
                    : .spring(response: 0.32, dampingFraction: 0.86)
            ) {
                selection = tab
            }
        } label: {
            ZStack {
                if isActive {
                    Capsule(style: .continuous)
                        .fill(.white)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Theme.accent, lineWidth: 1.5)
                        }
                        .matchedGeometryEffect(id: "activeCapsule", in: capsule)
                }

                HStack(spacing: 6) {
                    Image(systemName: tab.icon)
                        .font(.system(size: isActive ? 14 : 15, weight: .semibold))
                        .foregroundStyle(isActive ? Theme.accent : Color.white.opacity(0.62))

                    if isActive {
                        Text(tab.label)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .fixedSize()
                            .transition(.opacity.combined(with: .scale(scale: 0.86, anchor: .leading)))
                    }
                }
                .padding(.horizontal, isActive ? 14 : 0)
            }
            .frame(height: 44)
            .frame(maxWidth: isActive ? .infinity : collapsedWidth)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
