//
//  CantTodayHold.swift
//  GymLock · the "can't today" screen (three looks)
//
//  A long press that fills `progress` 0...1 over `duration` seconds. Lifting early drains it back
//  at twice the fill speed. Moving the finger more than 46 pt away cancels it, like the prototype.
//  Haptics are the caller's: `onBegan` (soft), `onComplete` (heavy), `onCancel`.
//

import SwiftUI

extension View {
    func cantTodayHold(duration: Double = 1.5,
                       progress: Binding<Double>,
                       isHolding: Binding<Bool>,
                       onBegan: @escaping () -> Void,
                       onComplete: @escaping () -> Void,
                       onCancel: @escaping () -> Void) -> some View {
        modifier(CantTodayHoldModifier(duration: duration,
                                       progress: progress,
                                       isHolding: isHolding,
                                       onBegan: onBegan,
                                       onComplete: onComplete,
                                       onCancel: onCancel))
    }
}

private struct CantTodayHoldModifier: ViewModifier {
    let duration: Double
    @Binding var progress: Double
    @Binding var isHolding: Bool
    let onBegan: () -> Void
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var loop: Task<Void, Never>?
    @State private var counting = false     // the finger is down and the fill is running
    @State private var spent = false        // this touch already completed or was cancelled
    @GestureState private var touching = false

    private let slop: CGFloat = 46

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { value in
                        if !counting && !spent {
                            begin()
                        }
                        if counting {
                            let d = hypot(value.translation.width, value.translation.height)
                            if d > slop { abandon() }
                        }
                    }
                    .onEnded { _ in
                        if counting { abandon() }
                        spent = false
                    }
            )
            .onChange(of: touching) { _, isDown in
                // The system took the touch away (no `onEnded`).
                if !isDown {
                    if counting { abandon() }
                    spent = false
                }
            }
            .onDisappear {
                loop?.cancel()
                loop = nil
                if counting {
                    counting = false
                    isHolding = false
                }
            }
    }

    private func begin() {
        counting = true
        isHolding = true
        onBegan()
        startLoop()
    }

    /// Released early or dragged away: the loop keeps running and drains `progress`.
    private func abandon() {
        counting = false
        spent = true
        isHolding = false
        onCancel()
    }

    private func startLoop() {
        loop?.cancel()
        loop = Task { @MainActor in
            var last = Date.timeIntervalSinceReferenceDate
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 16_000_000)
                if Task.isCancelled { return }
                let now = Date.timeIntervalSinceReferenceDate
                let dt = min(max(now - last, 0), 0.1)
                last = now
                let span = max(duration, 0.01)
                if counting {
                    let next = progress + dt / span
                    if next >= 1 {
                        progress = 1
                        counting = false
                        spent = true
                        isHolding = false
                        loop = nil
                        onComplete()
                        return
                    }
                    progress = next
                } else {
                    let next = progress - 2 * dt / span
                    if next <= 0 {
                        progress = 0
                        loop = nil
                        return
                    }
                    progress = next
                }
            }
        }
    }
}
