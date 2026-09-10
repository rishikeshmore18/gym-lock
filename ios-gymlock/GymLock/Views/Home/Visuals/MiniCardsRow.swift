import SwiftUI

/// Which mini card was tapped.
enum MiniCardRole: String, CaseIterable {
    case protection
    case next
    case path
}

/// The three cards under the hero.
///
/// The roles are fixed — Protection, Next, Path — while the content inside each
/// evolves with the day. They share one geometry and one type scale so the row
/// reads as a single system, and none of them contains a control: they display
/// what the system is doing, they don't offer toggles.
struct MiniCardsRow: View {
    let protection: ProtectionCard
    let next: NextCard
    let path: PathCard
    /// Optional destinations; a card without one renders non-interactive.
    var onTap: ((MiniCardRole) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, HeroMetrics.maxWidth)
            let metrics = MiniMetrics(width: (width - MiniMetrics.gap * 2) / 3)

            HStack(spacing: MiniMetrics.gap) {
                ProtectionMini(state: protection, metrics: metrics)
                    .frame(maxWidth: .infinity)
                    .makeTappable(role: .protection, onTap: onTap)

                NextMini(state: next, metrics: metrics)
                    .frame(maxWidth: .infinity)
                    .makeTappable(role: .next, onTap: onTap)

                PathMini(state: path, metrics: metrics)
                    .frame(maxWidth: .infinity)
                    .makeTappable(role: .path, onTap: onTap)
            }
            .frame(width: proxy.size.width)
        }
        .frame(maxWidth: HeroMetrics.maxWidth)
        .aspectRatio(MiniCardsRow.aspect, contentMode: .fit)
    }

    /// Row height comes from the card aspect, not a magic constant.
    static let aspect: CGFloat = 3 / 1.18
}

/// Shared sizing for the three minis, relative to one card's width.
struct MiniMetrics {
    static let gap: CGFloat = 10

    let width: CGFloat

    var height: CGFloat { width * 1.18 }
    var cornerRadius: CGFloat { 18 }
    var padding: CGFloat { max(10, width * 0.11) }

    var iconCircle: CGFloat { max(22, width * 0.20) }
    var labelSize: CGFloat { max(8.5, width * 0.088) }
    var valueSize: CGFloat { width * 0.185 }
    var detailSize: CGFloat { max(8.5, width * 0.082) }
    var dotSize: CGFloat { width * 0.062 }
    var arrowDiameter: CGFloat { width * 0.24 }
}

private extension View {
    /// Wraps a mini in its tap behaviour, or leaves it inert.
    @ViewBuilder
    func makeTappable(
        role: MiniCardRole,
        onTap: ((MiniCardRole) -> Void)?
    ) -> some View {
        if let onTap {
            Button {
                Haptics.selection()
                onTap(role)
            } label: {
                self
            }
            .buttonStyle(PressDownStyle())
        } else {
            self
        }
    }
}

/// Shared mini surface: warm white, soft corner, hairline, barely-lifted.
private struct MiniSurface<Content: View>: View {
    let metrics: MiniMetrics
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(metrics.padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: metrics.height, alignment: .topLeading)
            .background(Theme.surface, in: .rect(cornerRadius: metrics.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: metrics.cornerRadius)
                    .strokeBorder(Theme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.045), radius: 10, y: 4)
            .clipShape(.rect(cornerRadius: metrics.cornerRadius))
    }
}

// MARK: - Card 1 · Protection

struct ProtectionMini: View {
    let state: ProtectionCard
    let metrics: MiniMetrics

    var body: some View {
        MiniSurface(metrics: metrics) {
            VStack(alignment: .leading, spacing: 0) {
                GymLockStatusIcon(
                    systemName: iconName,
                    circleSize: metrics.iconCircle
                )

                Text(eyebrow)
                    .font(.system(size: metrics.labelSize, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.top, metrics.padding * 0.55)

                Text(valueText)
                    .font(.system(size: metrics.valueSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .padding(.top, 1)

                Text(state.detail)
                    .font(.system(size: metrics.detailSize, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch state.mood {
        case .shielding: "lock.fill"
        case .released: "lock.open.fill"
        case .ready: "lock.badge.clock.fill"
        case .unset: "lock.slash.fill"
        }
    }

    private var eyebrow: String {
        switch state.mood {
        case .shielding: "PROTECTED"
        case .released: "RELEASED"
        case .ready: "APPS READY"
        case .unset: "APPS"
        }
    }

    private var valueText: String {
        guard state.appCount > 0 else { return "—" }
        return "\(state.appCount)"
    }
}

// MARK: - Card 2 · Next

struct NextMini: View {
    let state: NextCard
    let metrics: MiniMetrics

    var body: some View {
        MiniSurface(metrics: metrics) {
            VStack(alignment: .leading, spacing: 0) {
                GymLockStatusIcon(
                    systemName: "alarm.fill",
                    circleSize: metrics.iconCircle
                )

                Text(state.eyebrow)
                    .font(.system(size: metrics.labelSize, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.top, metrics.padding * 0.55)

                Text(state.value)
                    .font(.system(size: metrics.valueSize * 0.86, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 1)

                if let detail = state.detail {
                    Text(detail)
                        .font(.system(size: metrics.detailSize, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.top, 1)
                }

                if state.showsArrow {
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: metrics.arrowDiameter * 0.42, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Card 3 · Path

struct PathMini: View {
    let state: PathCard
    let metrics: MiniMetrics

    var body: some View {
        MiniSurface(metrics: metrics) {
            VStack(alignment: .leading, spacing: 0) {
                GymLockStatusIcon(
                    systemName: "scope",
                    circleSize: metrics.iconCircle
                )

                Text("PATH")
                    .font(.system(size: metrics.labelSize, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.top, metrics.padding * 0.55)

                Text(valueText)
                    .font(.system(size: metrics.valueSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .padding(.top, 1)

                Spacer(minLength: 0)

                if let placeholder = state.placeholder {
                    Text(placeholder)
                        .font(.system(size: metrics.detailSize, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                } else {
                    GymLockStepDots(
                        total: state.totalSteps,
                        completed: state.completedSteps,
                        dotSize: metrics.dotSize,
                        isActive: state.completedSteps > 0
                    )
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
    }

    /// A path in progress reads as a fraction; a path that has not started
    /// reads as a word.
    ///
    /// "0 / 4" before the first morning is a score, and a score of zero is the
    /// wrong first impression for someone who has done nothing wrong yet. The
    /// four outlined dots underneath already say everything the fraction would.
    private var valueText: String {
        guard state.placeholder == nil else { return "Ready" }
        return state.completedSteps > 0
            ? "\(state.completedSteps) / \(state.totalSteps)"
            : "Ready"
    }
}

#Preview("Mini cards") {
    HStack(spacing: 0) {
        MiniCardsRow(
            protection: ProtectionCard(mood: .shielding, appCount: 3, detail: "until verification"),
            next: NextCard(eyebrow: "NEXT", value: "6:40 AM", detail: "Tomorrow", showsArrow: true),
            path: PathCard(completedSteps: 2, placeholder: nil)
        )
    }
    .padding(18)
    .background(Theme.canvas)
}
