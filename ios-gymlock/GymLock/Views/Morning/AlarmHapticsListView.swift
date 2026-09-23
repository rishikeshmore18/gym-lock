import SwiftUI

/// The Haptics page, after Apple's own: the default on its own at the top,
/// the standard patterns grouped under it, and None on its own at the foot.
///
/// Choosing a pattern plays one cycle of it, so the list is felt rather than
/// read, and while it plays the row draws its rhythm beside the name, lit
/// beat by beat in step with the vibration. Apple's "Create New Vibration" is
/// left out: it would need a recorder this app does not have, and a row that
/// leads nowhere is worse than no row.
struct AlarmHapticsListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The pattern currently being felt, and when it started, so its strip
    /// can be drawn in step with the engine.
    @State private var playing: Playing?
    @State private var clearPlaying: Task<Void, Never>?

    private struct Playing: Equatable {
        let haptic: AlarmHaptic
        let startedAt: Date
    }

    @Namespace private var checkSpace

    var body: some View {
        AlarmSubpage(title: "Haptics") {
            Button { choose(.synchronized) } label: {
                rowLabel(.synchronized, title: "Synchronized (Default)")
            }
            .buttonStyle(AlarmGlassCardButtonStyle())
            .modifier(RowAccessibility(title: "Synchronized, default", isSelected: isSelected(.synchronized)))

            VStack(alignment: .leading, spacing: 8) {
                AlarmSectionHeader(text: "standard")

                AlarmGroupCard {
                    ForEach(Array(AlarmHaptic.standard.enumerated()), id: \.element) { index, haptic in
                        if index > 0 { AlarmRowDivider() }
                        Button { choose(haptic) } label: {
                            rowLabel(haptic, glides: true)
                        }
                        .buttonStyle(AlarmRowButtonStyle())
                        .modifier(RowAccessibility(title: haptic.label, isSelected: isSelected(haptic)))
                    }
                }
            }
            .padding(.top, 6)

            Button { choose(.none) } label: {
                rowLabel(.none)
            }
            .buttonStyle(AlarmGlassCardButtonStyle())
            .modifier(RowAccessibility(title: AlarmHaptic.none.label, isSelected: isSelected(.none)))
            .padding(.top, 6)

            Text("plays with your track while the alarm rings in the app. the system alarm vibrates the way iOS decides.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
        }
        .onDisappear {
            clearPlaying?.cancel()
            Haptics.stopPreview()
        }
    }

    private var glide: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.34, dampingFraction: 0.78)
    }

    private func isSelected(_ haptic: AlarmHaptic) -> Bool {
        store.plan.alarmHaptic == haptic
    }

    /// `glides` is for rows inside the one grouped card, where the checkmark
    /// can travel between them. The single-row cards clip at their edges, so
    /// a mark flying in from another card would appear cut off mid-flight;
    /// there it pops in place instead.
    private func rowLabel(_ haptic: AlarmHaptic, title: String? = nil, glides: Bool = false) -> some View {
        let selected = isSelected(haptic)
        let strip = playing?.haptic == haptic ? playing : nil

        return HStack(spacing: 10) {
            Text(title ?? haptic.label)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)

            Spacer(minLength: 12)

            if let strip {
                HapticBeatStrip(haptic: strip.haptic, startedAt: strip.startedAt)
                    .id(strip.startedAt)
                    .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)))
            }

            ZStack {
                if selected {
                    checkmark(glides: glides)
                }
            }
            .frame(width: 20, alignment: .trailing)
        }
        .frame(minHeight: 50)
        .animation(glide, value: strip)
    }

    @ViewBuilder
    private func checkmark(glides: Bool) -> some View {
        let mark = Image(systemName: "checkmark")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Theme.accent)
            .transition(.scale(scale: 0.4).combined(with: .opacity))

        if glides {
            mark.matchedGeometryEffect(id: "check", in: checkSpace)
        } else {
            mark
        }
    }

    private func choose(_ haptic: AlarmHaptic) {
        if !isSelected(haptic) {
            withAnimation(glide) { store.plan.alarmHaptic = haptic }
        }

        clearPlaying?.cancel()

        // The preview is the feedback; a tick on top of it would blur it.
        guard haptic != .none else {
            Haptics.stopPreview()
            Haptics.selection()
            withAnimation(glide) { playing = nil }
            return
        }

        Haptics.preview(haptic)
        let started = Date()
        withAnimation(glide) { playing = Playing(haptic: haptic, startedAt: started) }

        // Held a beat past the last pulse, so the strip finishes lit before
        // it fades rather than vanishing on the final tap.
        let hold = (haptic.beats.map { $0.time + $0.duration }.max() ?? 0) + 0.6
        clearPlaying = Task {
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled else { return }
            withAnimation(glide) {
                if playing?.startedAt == started { playing = nil }
            }
        }
    }
}

private struct RowAccessibility: ViewModifier {
    let title: String
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityLabel(title)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityHint("Plays the vibration")
    }
}
