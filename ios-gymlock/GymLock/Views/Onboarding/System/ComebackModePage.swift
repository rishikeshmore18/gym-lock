import SwiftUI

/// System screen 13 — what happens after a miss.
///
/// Every other habit app treats a broken streak as a punishment, which is
/// precisely the mechanism that turns one missed Tuesday into a lost month. This
/// screen shows the alternative as a two-card diagram, and the toggle defaults
/// on. Leaving it on is never framed as weakness.
struct ComebackModePage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var contentShown = false
    @State private var missShown = false
    @State private var comebackShown = false

    var body: some View {
        @Bindable var store = store

        SystemScene(topAnchor: 0.09, contentSpacing: 18) {
            SceneHeading(
                title: "and when life actually gets in the way?",
                highlighted: ["gets in the way?"],
                subtitle: "no broken streak. no \u{201C}start again monday.\u{201D}"
            )
            .staggered(0, isShown: contentShown)
        } content: {
            VStack(spacing: 16) {
                dayDiagram

                Text("your next opportunity becomes the priority.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .staggered(3, isShown: comebackShown)

                Toggle(isOn: $store.profile.comebackModeEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("keep comeback mode on")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text("recommended")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
                .tint(Theme.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(Theme.surface, in: .rect(cornerRadius: Theme.controlRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .strokeBorder(Theme.border, lineWidth: 1)
                }
                .staggered(4, isShown: comebackShown)
                .onChange(of: store.profile.comebackModeEnabled) { _, _ in
                    Haptics.tap()
                }
            }
        } footer: {
            SceneContinueButton(action: onContinue)
                .staggered(5, isShown: comebackShown)
        }
        .task(id: isActive) { await run() }
    }

    /// Two days and an arrow. The missed day arrives first and sits alone for a
    /// beat — that pause is the feeling being addressed — and then the comeback
    /// answers it.
    private var dayDiagram: some View {
        VStack(spacing: 8) {
            dayCard(
                day: "tuesday",
                status: "missed",
                icon: "xmark",
                tint: Theme.inkTertiary,
                isShown: missShown
            )

            Image(systemName: "arrow.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.accent)
                .opacity(comebackShown ? 1 : 0)
                .scaleEffect(comebackShown || reduceMotion ? 1 : 0.7)
                .animation(Theme.settle, value: comebackShown)

            dayCard(
                day: "wednesday",
                status: "comeback",
                icon: "arrow.uturn.left",
                tint: Theme.accent,
                isShown: comebackShown
            )
        }
    }

    private func dayCard(
        day: String,
        status: String,
        icon: String,
        tint: Color,
        isShown: Bool
    ) -> some View {
        let isComeback = tint == Theme.accent

        return HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isComeback ? .white : Theme.inkTertiary)
                .frame(width: 32, height: 32)
                .background(isComeback ? Theme.accent : Theme.surfaceMuted, in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(day)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(status)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            isComeback ? Theme.accent.opacity(0.07) : Theme.surface,
            in: .rect(cornerRadius: Theme.controlRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.controlRadius)
                .strokeBorder(isComeback ? Theme.accent.opacity(0.5) : Theme.border, lineWidth: 1)
        }
        .opacity(isShown ? 1 : 0)
        .offset(y: isShown || reduceMotion ? 0 : 10)
        .animation(Theme.settle, value: isShown)
        .accessibilityElement(children: .combine)
    }

    private func run() async {
        guard isActive else {
            contentShown = false
            missShown = false
            comebackShown = false
            return
        }

        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        withAnimation(Theme.settle) { contentShown = true }

        try? await Task.sleep(for: .milliseconds(380))
        guard !Task.isCancelled else { return }
        withAnimation(Theme.settle) { missShown = true }

        // The gap where the spiral would normally start.
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        withAnimation(Theme.settle) { comebackShown = true }
        Haptics.soft()
    }
}
