import SwiftUI

/// The onboarding story: ten scenes on one continuous vertical scroll.
///
/// Every scene plays itself. The two multi-part scenes — the "Problem" kinetic
/// typography sequence and the loop diagram — run on their own timelines and open
/// the way forward when they are done, so a swipe always means "next scene" and
/// never "advance this one".
struct OnboardingFlowView: View {
    @Environment(AppStore.self) private var store

    private enum Scene: Int, CaseIterable {
        case logo, name, greeting, problem, guilt, loop, excuses, chart, caution, solution
    }

    @State private var index = 0
    @State private var isEditingName = false
    /// The loop scene holds the story until it has played to its halfway mark.
    @State private var isLoopUnlocked = false

    private var maxReachableIndex: Int {
        guard store.hasName else { return Scene.name.rawValue }
        guard isLoopUnlocked else { return Scene.loop.rawValue }
        return Scene.allCases.count - 1
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.canvas.ignoresSafeArea()

            VerticalPager(
                index: $index,
                pageCount: Scene.allCases.count,
                maxReachableIndex: maxReachableIndex,
                isDragDisabled: isEditingName
            ) { pageIndex in
                scene(at: pageIndex)
            }

            progressRail
                .padding(.trailing, 10)
                .opacity(index == 0 ? 0 : 1)
                .animation(Theme.settle, value: index)
        }
    }

    @ViewBuilder
    private func scene(at pageIndex: Int) -> some View {
        let isActive = index == pageIndex

        switch Scene(rawValue: pageIndex) ?? .logo {
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
                onContinue: advance
            )
        case .greeting:
            GreetingPage(isActive: isActive, name: store.greetingName)
        case .problem:
            ProblemReelPage(isActive: isActive)
        case .guilt:
            GuiltPage(isActive: isActive, name: store.greetingName)
        case .loop:
            LoopPage(isActive: isActive) {
                withAnimation(Theme.settle) { isLoopUnlocked = true }
            }
        case .excuses:
            ExcusesPage(isActive: isActive, name: store.greetingName)
        case .chart:
            ChartPage(isActive: isActive)
        case .caution:
            CautionPage(isActive: isActive)
        case .solution:
            SolutionPage(isActive: isActive) {
                store.stage = .scheduleSetup
            }
        }
    }

    /// A quiet rail showing position in the story.
    private var progressRail: some View {
        VStack(spacing: 6) {
            ForEach(Scene.allCases.dropFirst(), id: \.rawValue) { scene in
                let isCurrent = index == scene.rawValue

                Capsule()
                    .fill(isCurrent ? Theme.accent : Theme.ink.opacity(0.14))
                    .frame(width: 3, height: isCurrent ? 18 : 8)
                    .animation(Theme.settle, value: isCurrent)
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
