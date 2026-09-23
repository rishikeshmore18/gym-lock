import SwiftUI

/// Which alarm screen do you want? Two previews side by side, after the Lock
/// Screen chooser, and nothing else.
///
/// Both are on screen at once rather than paged, because the choice is a
/// comparison: seeing them next to each other is what makes the difference
/// obvious. Tapping a preview is the whole control.
///
/// Browsing is reversible. Taps change a local draft only. Back, or the edge
/// swipe, drops it and the plan is untouched. The tick commits it, and like
/// the tick on the Alarm screen it only appears once there is something to
/// save, so the header uses the same two buttons the Alarm screen does and
/// no third navigation style is introduced.
struct AlarmScreenPickerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draft: AlarmScreenDraft

    init(stored: AlarmScreenStyle) {
        _draft = State(initialValue: AlarmScreenDraft(stored: stored))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                Color.clear.frame(height: AlarmPageHeader.band)

                HStack(alignment: .top, spacing: 14) {
                    ForEach(AlarmScreenStyle.allCases) { style in
                        choice(style)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }

            header
        }
        .toolbar(.hidden, for: .navigationBar)
        .background {
            InteractivePopEnabler()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onAppear { Haptics.prepareSelection() }
    }

    // MARK: Header

    /// The Alarm screen's header, not a lookalike: the same glass back
    /// circle, the same centred title, the same ink tick.
    private var header: some View {
        ZStack {
            CollapsingTitle(
                title: "alarm screen",
                collapse: 0,
                overscroll: 0,
                containerWidth: 0,
                start: .centred,
                expandedSize: 30
            )

            HStack(spacing: 0) {
                GlassCircleButton(symbol: "chevron.left", label: "Back") {
                    // The draft lives in this view's state and goes with it.
                    dismiss()
                }
                Spacer(minLength: 0)
                GlassCircleButton(symbol: "checkmark", label: "Done", role: .prominent) {
                    commit()
                }
                .scaleEffect(draft.hasChanges ? 1 : 0.35)
                .opacity(draft.hasChanges ? 1 : 0)
                .allowsHitTesting(draft.hasChanges)
                .accessibilityHidden(!draft.hasChanges)
                .accessibilityHint("Saves this alarm screen")
                .animation(
                    reduceMotion ? .easeOut(duration: 0.2) : .bouncy(duration: 0.42, extraBounce: 0.32),
                    value: draft.hasChanges
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    // MARK: Choices

    private func choice(_ style: AlarmScreenStyle) -> some View {
        let isSelected = draft.selection == style

        return Button {
            if draft.select(style) {
                Haptics.selection()
            }
        } label: {
            AlarmScreenPreviewCard(style: style, time: alarmTime, isSelected: isSelected)
        }
        .buttonStyle(PreviewPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style.accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The user's real alarm time, without the AM/PM, which a thumbnail has
    /// no room for.
    private var alarmTime: String {
        store.plan.rhythm.wakeTime.asDateToday
            .formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
    }

    private func commit() {
        draft.commit(to: &store.plan)
        Haptics.commit()
        dismiss()
    }
}

/// A preview gives slightly under the finger, at once, and settles back when
/// released. Reduce Motion swaps the shrink for a dim.
private struct PreviewPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed

        return configuration.label
            .contentShape(.rect)
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .opacity(pressed && reduceMotion ? 0.8 : 1)
            .animation(
                pressed
                    ? .spring(response: 0.16, dampingFraction: 0.9)
                    : .spring(response: 0.28, dampingFraction: 0.58),
                value: pressed
            )
    }
}
