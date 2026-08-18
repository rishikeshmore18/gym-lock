import SwiftUI

/// The onboarding story: ten scenes on one continuous vertical scroll.
///
/// Two scenes are pinned narratives that hold sub-steps, so their content
/// changes under the user's swipe instead of becoming separate screens: the
/// "Problem" kinetic-typography sequence and the loop diagram.
struct OnboardingFlowView: View {
    @Environment(AppStore.self) private var store

    private enum Scene: Int, CaseIterable {
        case logo, name, greeting, problem, guilt, loop, excuses, chart, caution, solution
    }

    @State private var index = 0
    @State private var subStep = 0
    @State private var isEditingName = false

    private var maxReachableIndex: Int {
        // The name is the only hard gate in the story.
        store.hasName ? Scene.allCases.count - 1 : Scene.name.rawValue
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.canvas.ignoresSafeArea()

            VerticalPager(
                index: $index,
                subStep: $subStep,
                pageCount: Scene.allCases.count,
                maxReachableIndex: maxReachableIndex,
                subStepCount: subStepCount(for:),
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

    /// Sub-steps per scene. Only the pinned narrative scenes hold more than one.
    private func subStepCount(for pageIndex: Int) -> Int {
        switch Scene(rawValue: pageIndex) {
        case .problem: return ProblemReelPage.stepCount
        case .loop: return LoopState.sequence.count
        default: return 1
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
            GuiltPage(isActive: isActive)
        case .loop:
            LoopPage(isActive: isActive, step: subStep)
        case .excuses:
            ExcusesPage(isActive: isActive)
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
            subStep = 0
        }
    }
}
