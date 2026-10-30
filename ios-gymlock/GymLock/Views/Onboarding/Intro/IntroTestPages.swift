//
//  IntroTestPages.swift
//  GymLock
//
//  TEMPORARY A/B test: onboarding page 1 = V1 (chains), page 2 = V2 (app-icon wall).
//  Each page plays fully; when V1 finishes it moves on to V2, and when V2 finishes the
//  normal onboarding continues. A tap after the reveal skips ahead immediately.
//
//  After choosing, delete this file and use a single page instead:
//      GymLockIntroView(variant: .classic) { advanceOnboarding() }   // keep V1
//      GymLockIntroView(variant: .apps)    { advanceOnboarding() }   // keep V2
//

import SwiftUI

struct IntroTestPages: View {
    /// Continue to the rest of the onboarding.
    var onDone: () -> Void

    @State private var page = 0
    @State private var advancing = false

    var body: some View {
        ZStack {
            if page == 0 {
                GymLockIntroView(
                    variant: .classic,
                    onFinished: { advance(after: 1.2) },
                    onContinue: { advance(after: 0) }
                )
                .id("intro-v1")
                .transition(.opacity)
            } else {
                GymLockIntroView(
                    variant: .apps,
                    onFinished: { advance(after: 1.2) },
                    onContinue: { advance(after: 0) }
                )
                .id("intro-v2")
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: page)
        .ignoresSafeArea()
        .task { GymLockIntroView.prewarm() }
    }

    private func advance(after delay: TimeInterval) {
        guard !advancing else { return }
        advancing = true
        Task { @MainActor in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            if page == 0 {
                page = 1
                advancing = false
            } else {
                onDone()
            }
        }
    }
}

#Preview {
    IntroTestPages(onDone: {})
}
