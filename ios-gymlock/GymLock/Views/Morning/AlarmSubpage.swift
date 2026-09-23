import SwiftUI

/// A page pushed from the Alarm screen, built the way the Alarm screen is:
/// warm canvas, the glass header floating over a scroll view, and the system
/// bar hidden so nothing but our own chrome is on screen.
///
/// The edge swipe back still works (see `InteractivePopEnabler`), and the
/// glass back button pops the page.
struct AlarmSubpage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    @Environment(\.dismiss) private var dismiss
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Color.clear.frame(height: AlarmPageHeader.band)
                    content
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                scrollOffset = offset
            }
            .overlay(alignment: .top) {
                AlarmPageHeader(title: title, scrollOffset: scrollOffset) {
                    dismiss()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background {
            InteractivePopEnabler()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}
