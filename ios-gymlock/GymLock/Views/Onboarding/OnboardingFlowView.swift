import SwiftUI

/// The vertical onboarding journey. Seven full-screen pages, one continuous
/// upward scroll, gated so the user cannot outrun the name question.
struct OnboardingFlowView: View {
    @Environment(AppStore.self) private var store

    private enum Page: Int, CaseIterable {
        case logo, name, greeting, chart, dream, problems, solution
    }

    @State private var index = 0
    @State private var isEditingName = false

    private var maxReachableIndex: Int {
        // The name is the only hard gate in the flow.
        store.hasName ? Page.allCases.count - 1 : Page.name.rawValue
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.canvas.ignoresSafeArea()

            VerticalPager(
                index: $index,
                pageCount: Page.allCases.count,
                maxReachableIndex: maxReachableIndex,
                isDragDisabled: isEditingName
            ) { pageHeight in
                ForEach(Page.allCases, id: \.rawValue) { page in
                    pageContent(page)
                        .frame(height: pageHeight)
                }
            }

            progressRail
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .opacity(index == 0 ? 0 : 1)
                .animation(Theme.settle, value: index)
        }
        .statusBarHidden(false)
    }

    @ViewBuilder
    private func pageContent(_ page: Page) -> some View {
        let isActive = index == page.rawValue

        switch page {
        case .logo:
            LogoSplashPage(isActive: isActive)
        case .name:
            NamePage(
                isActive: isActive,
                name: Binding(
                    get: { store.userName },
                    set: { store.userName = $0 }
                ),
                isEditing: $isEditingName,
                onContinue: { advance() }
            )
        case .greeting:
            GreetingPage(isActive: isActive, name: store.greetingName)
        case .chart:
            ChartPage(isActive: isActive)
        case .dream:
            DreamPage(isActive: isActive)
        case .problems:
            ProblemCyclePage(isActive: isActive)
        case .solution:
            SolutionPage(isActive: isActive) {
                store.stage = .scheduleSetup
            }
        }
    }

    /// A quiet vertical rail showing position in the journey.
    private var progressRail: some View {
        VStack(spacing: 6) {
            ForEach(Page.allCases.dropFirst(), id: \.rawValue) { page in
                Capsule()
                    .fill(index == page.rawValue ? Theme.accent : Theme.ink.opacity(0.14))
                    .frame(width: 3, height: index == page.rawValue ? 18 : 8)
                    .animation(Theme.settle, value: index)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .accessibilityHidden(true)
    }

    private func advance() {
        withAnimation(Theme.pageTurn) {
            index = min(index + 1, maxReachableIndex)
        }
    }
}
