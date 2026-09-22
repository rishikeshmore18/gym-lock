import SwiftUI

/// The Haptics page, after Apple's own: the default on its own at the top,
/// the standard patterns grouped under it, and None on its own at the foot.
///
/// Choosing a pattern plays one cycle of it, so the list is felt rather than
/// read. Apple's "Create New Vibration" is left out: it would need a
/// recorder this app does not have, and a row that leads nowhere is worse
/// than no row.
struct AlarmHapticsListView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AlarmGroupCard {
                    row(.synchronized, title: "Synchronized (Default)")
                }

                VStack(alignment: .leading, spacing: 8) {
                    AlarmSectionHeader(text: "standard")

                    AlarmGroupCard {
                        ForEach(Array(AlarmHaptic.standard.enumerated()), id: \.element) { index, haptic in
                            if index > 0 { AlarmRowDivider() }
                            row(haptic)
                        }
                    }
                }
                .padding(.top, 6)

                AlarmGroupCard {
                    row(.none)
                }
                .padding(.top, 6)

                Text("plays with your track while the alarm rings in the app. the system alarm vibrates the way iOS decides.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Haptics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .tint(Theme.ink)
        .onDisappear { Haptics.stopPreview() }
    }

    private func row(_ haptic: AlarmHaptic, title: String? = nil) -> some View {
        let isSelected = store.plan.alarmHaptic == haptic

        return Button {
            if !isSelected { store.plan.alarmHaptic = haptic }
            // The preview is the feedback; a tick on top of it would blur it.
            if haptic == .none { Haptics.selection() } else { Haptics.preview(haptic) }
        } label: {
            HStack(spacing: 8) {
                Text(title ?? haptic.label)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                Spacer(minLength: 12)

                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .opacity(isSelected ? 1 : 0)
                    .scaleEffect(isSelected ? 1 : 0.5)
            }
            .frame(minHeight: 50)
            .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isSelected)
        }
        .buttonStyle(AlarmRowButtonStyle())
        .accessibilityLabel(title ?? haptic.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
