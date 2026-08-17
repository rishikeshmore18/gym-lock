import SwiftUI

/// Page 5 — the reflective question, paired with the daydreaming figure.
/// The illustration drifts very slowly so the page feels alive but unhurried.
struct DreamPage: View {
    let isActive: Bool

    @State private var headlineShown = false
    @State private var cardShown = false
    @State private var drift = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 24)

            AccentedText(
                full: "so what's stopping them from being a better version of themselves?",
                highlighted: ["better version"],
                size: 30
            )
            .opacity(headlineShown ? 1 : 0)
            .offset(y: headlineShown ? 0 : 12)

            illustrationCard
                .padding(.top, 28)
                .opacity(cardShown ? 1 : 0)
                .scaleEffect(cardShown ? 1 : 0.97)

            Spacer()

            SwipeUpHint(isActive: isActive && cardShown)
                .frame(maxWidth: .infinity)
                .opacity(cardShown ? 1 : 0)
                .padding(.bottom, 40)
        }
        .padding(.horizontal, Theme.pageMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: isActive) {
            guard isActive else { return }
            withAnimation(Theme.settle) { headlineShown = true }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(Theme.settle) { cardShown = true }
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private var illustrationCard: some View {
        Color.clear
            .frame(height: 320)
            .overlay {
                Image("person_daydreaming_fitness")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(22)
                    .offset(y: drift ? -6 : 6)
                    .allowsHitTesting(false)
            }
            .warmCard()
            .accessibilityLabel("A person sitting and daydreaming about a stronger version of themselves")
    }
}
