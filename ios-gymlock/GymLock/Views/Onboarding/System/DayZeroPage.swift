import SwiftUI

/// System screen 2 — Day 0.
///
/// The one thing that cannot be recreated later is what today looked like. The
/// screen asks for it once, makes the privacy promise plainly, and then gets out
/// of the way — skipping carries no penalty and no guilt copy, because a user
/// who feels judged here will not come back tomorrow.
struct DayZeroPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @Environment(AppStore.self) private var store

    @State private var kind: Day0Media.Kind = .photo
    @State private var isCapturing = false
    @State private var contentShown = false

    private var media: Day0Media? { store.profile.day0Media }

    var body: some View {
        SystemScene(topAnchor: 0.09) {
            SceneHeading(
                title: "mark where you're starting.",
                highlighted: ["where you're starting."],
                subtitle: "take one photo today so your future self gets the comparison."
            )
            .staggered(0, isShown: contentShown)
        } content: {
            VStack(spacing: 14) {
                if media == nil {
                    kindPicker
                        .staggered(1, isShown: contentShown)
                }

                captureArea
                    .staggered(2, isShown: contentShown)
            }
        } footer: {
            VStack(spacing: 12) {
                if media == nil {
                    Button {
                        Haptics.tap()
                        isCapturing = true
                    } label: {
                        Text(kind == .photo ? "take my day 0 photo" : "record my day 0 video")
                    }
                    .buttonStyle(PrimaryCTAStyle(isEnabled: true))

                    Button {
                        Haptics.tap()
                        onContinue()
                    } label: {
                        Text("maybe later")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                } else {
                    Button {
                        Haptics.tap()
                        onContinue()
                    } label: {
                        Text("continue")
                    }
                    .buttonStyle(PrimaryCTAStyle(isEnabled: true))

                    Button {
                        Haptics.tap()
                        store.profile.day0Media = nil
                    } label: {
                        Text("retake")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }

                Label("stored only on this iPhone. never uploaded.", systemImage: "lock.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .labelStyle(.titleAndIcon)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .staggered(3, isShown: contentShown)
        }
        .fullScreenCover(isPresented: $isCapturing) {
            Day0CaptureSheet(
                kind: kind,
                onCaptured: { captured in
                    store.profile.day0Media = captured
                    isCapturing = false
                },
                onCancel: { isCapturing = false }
            )
        }
        .task(id: isActive) {
            guard isActive else {
                contentShown = false
                return
            }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.settle) { contentShown = true }
        }
    }

    /// Photo or a five-second clip. Photo is the default because it is the one
    /// people will actually take.
    private var kindPicker: some View {
        HStack(spacing: 8) {
            segment(.photo, label: "photo", icon: "camera.fill")
            segment(.video, label: "5-sec video", icon: "video.fill")
        }
        .padding(5)
        .background(Theme.surfaceMuted, in: .rect(cornerRadius: 15))
    }

    private func segment(_ value: Day0Media.Kind, label: String, icon: String) -> some View {
        let isOn = kind == value

        return Button {
            Haptics.tap()
            kind = value
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(isOn ? .white : Theme.inkSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(isOn ? Theme.accent : Color.clear, in: .rect(cornerRadius: 11))
        }
        .buttonStyle(PressableRowStyle())
        .animation(Theme.stateChange, value: isOn)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    @ViewBuilder
    private var captureArea: some View {
        if let media {
            Day0Thumbnail(media: media, height: 230)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .animation(Theme.settle, value: media.fileName)
        } else {
            emptyState
        }
    }

    /// A dashed frame rather than a filled card: it reads as a space waiting to
    /// be filled instead of a component that failed to load.
    private var emptyState: some View {
        RoundedRectangle(cornerRadius: Theme.cardRadius)
            .strokeBorder(
                Theme.accent.opacity(0.35),
                style: StrokeStyle(lineWidth: 1.6, dash: [7, 6])
            )
            .frame(height: 230)
            .background(Theme.accent.opacity(0.04), in: .rect(cornerRadius: Theme.cardRadius))
            .overlay {
                VStack(spacing: 11) {
                    Image(systemName: kind == .photo ? "camera.fill" : "video.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.symbolEffect(.replace))

                    Text("day 0")
                        .font(.system(size: 14, weight: .bold))
                        .textCase(.uppercase)
                        .kerning(1.1)
                        .foregroundStyle(Theme.accent)

                    Text("one shot. today.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .animation(Theme.stateChange, value: kind)
    }
}
