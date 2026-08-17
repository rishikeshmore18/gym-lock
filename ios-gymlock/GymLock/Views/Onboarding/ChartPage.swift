import SwiftUI

/// Page 4 — the data reveal. The lines draw themselves from left to right so
/// the divergence is something the user watches happen, not just reads.
struct ChartPage: View {
    let isActive: Bool

    @State private var headlineShown = false
    @State private var drawProgress: CGFloat = 0
    @State private var captionShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 24)

            AccentedText(
                full: "Do you know 60% of people quit the gym within 3 months?",
                highlighted: ["60%", "3 months"],
                size: 30
            )
            .opacity(headlineShown ? 1 : 0)
            .offset(y: headlineShown ? 0 : 12)

            RetentionChart(progress: drawProgress)
                .padding(20)
                .warmCard()
                .padding(.top, 30)
                .opacity(headlineShown ? 1 : 0)

            Text("same start. two paths.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 24)
                .opacity(captionShown ? 1 : 0)

            Spacer()

            SwipeUpHint(isActive: isActive && captionShown)
                .frame(maxWidth: .infinity)
                .opacity(captionShown ? 1 : 0)
                .padding(.bottom, 40)
        }
        .padding(.horizontal, Theme.pageMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: isActive) {
            guard isActive else { return }
            withAnimation(Theme.settle) { headlineShown = true }
            try? await Task.sleep(for: .milliseconds(360))
            withAnimation(.easeInOut(duration: 1.9)) { drawProgress = 1 }
            try? await Task.sleep(for: .milliseconds(1700))
            withAnimation(Theme.settle) { captionShown = true }
        }
    }
}
