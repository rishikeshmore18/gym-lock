//
//  HomeWorkoutView.swift
//  GymLock · the home workout host (setup + count-up timer)
//
//  One screen for both session states (.quickWorkoutPicker and .quickWorkoutActive), so the art
//  stays in place when "start" is tapped and morphs into the timer instead of cutting.
//
//  The host owns everything the four looks share: the facts (real data), the frame clock, the
//  haptics (fired once per moment, never replayed when the app comes back late), the glass
//  X / end control, the start / finish button, the end sheet, and keeping the screen awake while
//  the phone is propped up.
//
//  Approved prototype: docs/prototypes/home-workout-variations.html
//

import SwiftUI
import UIKit

struct HomeWorkoutView: View {
    let session: GymSession
    /// True while the session is in .quickWorkoutActive.
    let isRunning: Bool
    let isAtCap: Bool
    let onStart: () -> Void
    /// Called once when 20:00 is reached, so the apps unlock while the timer keeps going.
    let onReachedMinimum: () -> Void
    /// true = finished (20+ min), false = ended early without counting.
    let onFinish: (Bool) -> Void
    let onClose: () -> Void
    /// Back from the running screen before 20:00 (a mistaken start). The timer is thrown away.
    let onBack: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(HeroCardStyle.storageKey) private var cardStyleRaw = HeroCardStyle.default.rawValue
    @AppStorage(HomeWorkoutLook.rotationKey) private var rotation = 0

    @State private var facts: HomeWorkoutFacts?
    @State private var look: HomeWorkoutLook?
    @State private var setupStart = Date()
    @State private var runStart: Date?
    @State private var firedMoment: Double = 0
    @State private var firedMinute = 0
    @State private var reachedSent = false
    @State private var isConfirmingEnd = false
    @State private var isConfirmingBack = false

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let full = CGSize(
                width: geo.size.width + insets.leading + insets.trailing,
                height: geo.size.height + insets.top + insets.bottom
            )
            ZStack {
                (look?.isDark ?? true ? Color(red: 0.043, green: 0.043, blue: 0.047) : Theme.canvas)

                if let facts, let look {
                    TimelineView(.animation) { tl in
                        let f = frame(facts: facts, at: tl.date, size: full, insets: insets)
                        ZStack {
                            lookView(look, f)
                            chrome(look: look, frame: f, insets: insets)
                        }
                        .onChange(of: momentKey(f)) { _, _ in fireHaptics(f, look: look) }
                    }
                }
            }
            .ignoresSafeArea()
        }
        .onAppear(perform: prepare)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = isRunning }
        .onChange(of: isRunning) { _, running in
            UIApplication.shared.isIdleTimerDisabled = running
            if running, runStart == nil { runStart = Date() }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .confirmationDialog(HomeWorkoutCopy.endTitle, isPresented: $isConfirmingEnd, titleVisibility: .visible) {
            Button(HomeWorkoutCopy.keepGoing, role: .cancel) {}
            Button(HomeWorkoutCopy.endWithout, role: .destructive) { onFinish(false) }
        } message: {
            Text(HomeWorkoutCopy.endMessage)
        }
        .confirmationDialog(HomeWorkoutCopy.backTitle, isPresented: $isConfirmingBack, titleVisibility: .visible) {
            Button(HomeWorkoutCopy.stay, role: .cancel) {}
            Button(HomeWorkoutCopy.goBack, role: .destructive) { onBack() }
        } message: {
            Text(HomeWorkoutCopy.backMessage)
        }
        .blocksHeroHaptics("homeWorkout")
    }

    // MARK: - Looks

    @ViewBuilder
    private func lookView(_ look: HomeWorkoutLook, _ f: HomeWorkoutFrame) -> some View {
        switch look {
        case .ridgeAscent: RidgeAscentLook(frame: f)
        case .ridgeSunrise: RidgeSunriseLook(frame: f)
        case .matrixSwarm: MatrixSwarmLook(frame: f)
        case .matrixStack: MatrixStackLook(frame: f)
        }
    }

    // MARK: - Frame

    private func elapsed(at date: Date) -> Double {
        guard isRunning else { return 0 }
        let started = session.quickWorkoutStartedAt ?? runStart ?? date
        return max(0, date.timeIntervalSince(started))
    }

    private func frame(facts: HomeWorkoutFacts, at date: Date, size: CGSize, insets: EdgeInsets) -> HomeWorkoutFrame {
        let running = isRunning
        let e = elapsed(at: date)
        // A workout reopened mid-way (app relaunched) has no morph to play: runAge = elapsed.
        let runAge = running ? (runStart.map { min(e, date.timeIntervalSince($0)) } ?? e) : 0
        return HomeWorkoutFrame(
            facts: facts,
            phase: running ? .running : .setup,
            setupAge: max(0, date.timeIntervalSince(setupStart)),
            runAge: max(0, runAge),
            elapsed: e,
            size: size,
            safeTop: insets.top,
            safeBottom: insets.bottom,
            reduceMotion: reduceMotion,
            now: date.timeIntervalSinceReferenceDate
        )
    }

    // MARK: - Chrome (shared by all four looks)

    @ViewBuilder
    private func chrome(look: HomeWorkoutLook, frame f: HomeWorkoutFrame, insets: EdgeInsets) -> some View {
        let dark = look.isDark
        VStack(spacing: 0) {
            HStack {
                if f.isRunning, !f.isDone {
                    GlassCircleButton(symbol: "chevron.left", label: "back", diameter: HomeWorkoutLayout.topControlSize) {
                        // The first minute is the "tapped by mistake" window: no question asked.
                        if f.elapsed < HomeWorkoutLayout.mistakeWindow {
                            onBack()
                        } else {
                            isConfirmingBack = true
                        }
                    }
                }
                Spacer()
                if !f.isRunning {
                    GlassCircleButton(symbol: "xmark", label: "close", diameter: HomeWorkoutLayout.topControlSize, action: onClose)
                } else if !f.isDone {
                    Button {
                        Haptics.tap()
                        isConfirmingEnd = true
                    } label: {
                        Text(HomeWorkoutCopy.end)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 16)
                            .frame(height: HomeWorkoutLayout.topControlSize)
                            .glassCapsule()
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("ends the workout. it won't count before 20 minutes.")
                }
            }
            .frame(height: HomeWorkoutLayout.topControlSize)
            .padding(.top, insets.top + 8)
            .padding(.horizontal, 20)

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                if f.isDone {
                    Text(HomeWorkoutCopy.finishHint)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(dark ? Color.white.opacity(0.62) : Theme.inkSecondary)
                        .transition(.opacity)
                }
                primaryButton(frame: f, dark: dark)
            }
            .padding(.horizontal, HomeWorkoutLayout.margin)
            .padding(.bottom, insets.bottom + HomeWorkoutLayout.buttonBottomInset)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.18) : Theme.settle, value: f.isDone)
        .animation(Theme.stateChange, value: f.isRunning)
    }

    @ViewBuilder
    private func primaryButton(frame f: HomeWorkoutFrame, dark: Bool) -> some View {
        if !f.isRunning {
            if isAtCap {
                capsule(HomeWorkoutRules.capMessage, dark: dark, enabled: false) {}
            } else {
                capsule(HomeWorkoutCopy.start, dark: dark, enabled: true) {
                    Haptics.medium()
                    rotation += 1
                    runStart = Date()
                    onStart()
                }
            }
        } else if f.isDone {
            capsule(HomeWorkoutCopy.finish, dark: dark, enabled: true) {
                Haptics.tap()
                onFinish(true)
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 24)))
        } else {
            // Before 20 there is no button; the slot stays reserved so nothing jumps at 20:00.
            Color.clear.frame(height: HomeWorkoutLayout.buttonHeight)
        }
    }

    private func capsule(_ title: String, dark: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: enabled ? 18 : 15, weight: .semibold))
                .foregroundStyle(dark ? Theme.ink : Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: HomeWorkoutLayout.buttonHeight)
                .background(dark ? Color.white : Theme.ink, in: .capsule)
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(HomeWorkoutPressStyle())
        .disabled(!enabled)
    }

    // MARK: - Haptics and the 20:00 unlock

    /// Changes whenever a moment, a new minute or 20:00 is crossed.
    private func momentKey(_ f: HomeWorkoutFrame) -> Int {
        guard f.isRunning else { return -1 }
        return Int(f.elapsed / 60)
    }

    private func fireHaptics(_ f: HomeWorkoutFrame, look: HomeWorkoutLook) {
        guard f.isRunning else { return }
        let e = f.elapsed

        if HomeWorkoutClock.isDone(e), !reachedSent {
            reachedSent = true
            onReachedMinimum()
        }

        // Only a moment crossed in the last few seconds buzzes; a relaunch at 23:00 stays quiet.
        if let at = HomeWorkoutClock.lastMoment(e), at > firedMoment {
            let fresh = e - at < 3
            firedMoment = at
            if fresh {
                if at == HomeWorkoutClock.minimum { Haptics.commit() }
                else if at < HomeWorkoutClock.minimum { Haptics.medium() }
                else { Haptics.soft() }
                return
            }
        }

        let minute = Int(e / 60)
        if look.ticksEachMinute, minute > firedMinute, minute <= 20 {
            if e - Double(minute * 60) < 3 { Haptics.selection() }
        }
        firedMinute = max(firedMinute, minute)
    }

    // MARK: - Data

    private func prepare() {
        guard facts == nil else { return }
        let pause = PauseFactsProvider.facts(store: store, coordinator: coordinator, session: session, context: .windowOpen)
        facts = HomeWorkoutFacts(
            streakWeeks: pause.streakWeeks,
            weekDone: pause.weekDone,
            weekGoal: pause.weekGoal,
            week: pause.week,
            homeLeft: pause.homeLeft,
            healthUsable: coordinator.health.isUsable
        )
        let style = HeroCardStyle(rawValue: cardStyleRaw) ?? .default
        // While running, the look chosen at start is rotation - 1 (start already bumped it).
        look = HomeWorkoutLook.pick(style: style, rotation: isRunning ? max(0, rotation - 1) : rotation)
        setupStart = Date()
        if isRunning {
            let e = elapsed(at: Date())
            firedMoment = HomeWorkoutClock.lastMoment(e) ?? 0
            firedMinute = Int(e / 60)
            if HomeWorkoutClock.isDone(e) {
                reachedSent = true
                onReachedMinimum()
            }
        }
    }
}

private struct HomeWorkoutPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
