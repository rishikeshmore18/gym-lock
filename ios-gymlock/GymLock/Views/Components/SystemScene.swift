import SwiftUI

/// The scaffold for the system-building half of onboarding.
///
/// It anchors exactly like `OnboardingScene` — heading high, body in the middle,
/// action at the bottom — so a question does not feel like a different app from
/// the story that preceded it. The difference is that the middle is a control
/// rather than an illustration, and it is given as much room as it needs.
///
/// Nothing here scrolls. Every question is designed to fit one viewport, because
/// a scroll view nested inside the pager would fight it for the same gesture.
struct SystemScene<Header: View, Content: View, Footer: View>: View {
    var topAnchor: CGFloat = 0.11
    /// Space between the header block and the content.
    var contentSpacing: CGFloat = 22

    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                    .frame(height: max(24, height * topAnchor))

                header
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: contentSpacing)

                content
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: contentSpacing)

                footer
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 26)
            }
            .padding(.horizontal, Theme.pageMargin)
            .frame(width: proxy.size.width, height: height, alignment: .top)
        }
    }
}

/// The standard question heading: a bold ask, with an optional quieter line
/// underneath it.
struct SceneHeading: View {
    let title: String
    var highlighted: [String] = []
    var subtitle: String?
    var footnote: String?
    var size: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            AccentedText(full: title, highlighted: highlighted, size: size)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The recurring "Continue" action, plus an optional quiet line beneath it.
struct SceneContinueButton: View {
    var title: String = "continue"
    var caption: String?
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button {
                Haptics.tap()
                action()
            } label: {
                Text(title)
            }
            .buttonStyle(PrimaryCTAStyle(isEnabled: isEnabled))
            .disabled(!isEnabled)

            if let caption {
                Text(caption)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Staggers a group of sibling views in, one shortly after another.
///
/// The delay is derived from the item's index rather than scheduled with
/// timers, so the whole group reverses cleanly when `isShown` goes back to
/// false — which is what happens when the user swipes back up.
struct StaggeredAppearance: ViewModifier {
    let index: Int
    let isShown: Bool
    var step: Double = 0.07
    var travel: CGFloat = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .scaleEffect(reduceMotion || isShown ? 1 : 0.96)
            .offset(y: isShown || reduceMotion ? 0 : travel)
            .animation(
                Theme.settle.delay(isShown ? Double(index) * step : 0),
                value: isShown
            )
    }
}

extension View {
    /// Reveals this view as part of a staggered group.
    func staggered(_ index: Int, isShown: Bool, step: Double = 0.07, travel: CGFloat = 12) -> some View {
        modifier(StaggeredAppearance(index: index, isShown: isShown, step: step, travel: travel))
    }
}
