import SwiftUI
import UniformTypeIdentifiers

/// System screen 11 — the sound.
///
/// Four tracks ship with the app and play immediately; the fifth option imports
/// a file the user already owns. GymLock deliberately does not offer to play
/// from a streaming service, because it cannot: those libraries are
/// DRM-protected and unavailable to a third-party alarm. Promising it here would
/// be a lie the user discovers on their first real gym morning.
struct AlarmSoundPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(AlarmSoundPlayer.self) private var player: AlarmSoundPlayer?

    @State private var contentShown = false
    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        SystemScene(topAnchor: 0.08, contentSpacing: 18) {
            SceneHeading(
                title: "choose the sound that gets you off the couch.",
                highlighted: ["off the couch."],
                subtitle: "your gym alarm doesn't have to sound like everyone else's.",
                size: 28
            )
            .staggered(0, isShown: contentShown)
        } content: {
            VStack(spacing: 8) {
                ForEach(Array(AlarmSound.bundled.enumerated()), id: \.element.id) { index, sound in
                    soundRow(sound)
                        .staggered(index + 1, isShown: contentShown)
                }

                ownSongRow
                    .staggered(5, isShown: contentShown)

                if let importError {
                    Text(importError)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } footer: {
            SceneContinueButton(action: {
                player?.stop()
                onContinue()
            })
            .staggered(6, isShown: contentShown)
        }
        .task(id: isActive) { await reveal(isActive: isActive, into: $contentShown) }
        .onChange(of: isActive) { _, active in
            if !active { player?.stop() }
        }
        .onDisappear { player?.stop() }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    private func soundRow(_ sound: AlarmSound) -> some View {
        let isSelected = store.profile.alarmSound == sound
        let isPlaying = player?.playing == sound

        return Button {
            select(sound)
        } label: {
            HStack(spacing: 13) {
                // The play control is part of the row, not a separate button:
                // hearing a track and choosing it are the same decision.
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isPlaying ? .white : Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        isPlaying ? Theme.accent : Theme.accent.opacity(0.11),
                        in: .circle
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(sound.label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(sound.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isPlaying {
                    Waveform(level: player?.level ?? 0)
                        .frame(width: 26, height: 20)
                        .transition(.opacity)
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.border)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                isSelected ? Theme.accent.opacity(0.07) : Theme.surface,
                in: .rect(cornerRadius: Theme.controlRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .strokeBorder(
                        isSelected ? Theme.accent : Theme.border,
                        lineWidth: isSelected ? 1.6 : 1
                    )
            }
        }
        .buttonStyle(PressableRowStyle())
        .animation(Theme.stateChange, value: isSelected)
        .animation(Theme.stateChange, value: isPlaying)
        .accessibilityLabel("\(sound.label). \(sound.subtitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var ownSongRow: some View {
        let isSelected = store.profile.alarmSound == .ownSong

        return Button {
            Haptics.tap()
            player?.stop()
            isImporting = true
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.accent.opacity(0.11), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isSelected ? (store.profile.ownSongTitle ?? "my own song") : "choose my own song")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text("import an audio file from this iPhone")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .font(.system(size: isSelected ? 19 : 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.inkTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                isSelected ? Theme.accent.opacity(0.07) : Theme.surfaceMuted,
                in: .rect(cornerRadius: Theme.controlRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .strokeBorder(isSelected ? Theme.accent : Theme.border, lineWidth: isSelected ? 1.6 : 1)
            }
        }
        .buttonStyle(PressableRowStyle())
        .animation(Theme.stateChange, value: isSelected)
    }

    private func select(_ sound: AlarmSound) {
        Haptics.tap()
        store.profile.alarmSound = sound
        player?.toggle(sound)
    }

    /// Copies the picked file into the app's own storage, because the security
    /// scoped URL handed over by the picker will not survive a relaunch.
    private func handleImport(_ result: Result<[URL], Error>) {
        importError = nil

        guard case let .success(urls) = result, let source = urls.first else { return }

        let didAccess = source.startAccessingSecurityScopedResource()
        defer { if didAccess { source.stopAccessingSecurityScopedResource() } }

        guard let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            importError = "couldn't save that track."
            return
        }

        let name = "alarm-\(UUID().uuidString).\(source.pathExtension)"
        let destination = documents.appendingPathComponent(name)

        do {
            try FileManager.default.copyItem(at: source, to: destination)

            if let previous = store.profile.ownSongFileName {
                try? FileManager.default.removeItem(
                    at: documents.appendingPathComponent(previous)
                )
            }

            store.profile.ownSongFileName = name
            store.profile.ownSongTitle = source.deletingPathExtension().lastPathComponent
            store.profile.alarmSound = .ownSong
            Haptics.commit()
        } catch {
            importError = "couldn't read that file. try another one?"
        }
    }
}

/// Five bars responding to the live output level of the preview.
private struct Waveform: View {
    let level: Double

    /// Per-bar weighting, so the middle bars move most and the outer ones
    /// lag — an even response reads as a loading spinner.
    private static let weights: [Double] = [0.45, 0.8, 1.0, 0.7, 0.5]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(Self.weights.enumerated()), id: \.offset) { _, weight in
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 3, height: max(3, 20 * level * weight))
            }
        }
        .frame(height: 20)
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }
}
