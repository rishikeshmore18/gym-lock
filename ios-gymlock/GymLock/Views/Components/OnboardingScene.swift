import SwiftUI

/// The shared scene scaffold that keeps every onboarding page anchored the same
/// way, so the user's eye never has to hunt for content after a swipe.
///
/// - headline sits around 15–22% from the top
/// - the hero visual is centred in the space beneath it, around 55% of the page
/// - the footer hugs the lower safe area
///
/// Pages must not top-align their own content; they hand their three blocks to
/// this scaffold instead.
struct OnboardingScene<Message: View, Hero: View, Footer: View>: View {
    /// Fraction of the page height reserved above the headline.
    var topAnchor: CGFloat = 0.15
    /// Ceiling for the hero visual, as a fraction of page height.
    var heroMaxHeightFraction: CGFloat = 0.46
    /// Horizontal alignment of the whole column.
    var alignment: HorizontalAlignment = .leading

    @ViewBuilder var message: Message
    @ViewBuilder var hero: Hero
    @ViewBuilder var footer: Footer

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height

            VStack(alignment: alignment, spacing: 0) {
                Spacer(minLength: 0)
                    .frame(height: max(28, height * topAnchor))

                message
                    .frame(maxWidth: .infinity, alignment: frameAlignment)

                Spacer(minLength: 14)

                hero
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: height * heroMaxHeightFraction)

                Spacer(minLength: 14)

                footer
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
                    .padding(.bottom, 26)
            }
            .padding(.horizontal, Theme.pageMargin)
            .frame(width: proxy.size.width, height: height, alignment: .top)
        }
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .center: return .center
        case .trailing: return .trailing
        default: return .leading
        }
    }
}

/// A quiet scene: a single centred block with generous negative space on both
/// sides. Used for the pages that are meant to be read, not studied.
struct QuietScene<Content: View, Footer: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            content
                .frame(maxWidth: .infinity)

            Spacer()

            footer
                .frame(maxWidth: .infinity)
                .padding(.bottom, 26)
        }
        .padding(.horizontal, Theme.pageMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
