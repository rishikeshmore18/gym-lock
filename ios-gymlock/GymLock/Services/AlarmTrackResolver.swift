import Foundation

/// Finds the audio file that should actually ring, and never returns nothing.
///
/// There are three ways the user's chosen track can be unavailable at 6:30 in
/// the morning: they picked their own song and the exported file was deleted,
/// a restore from backup brought the profile across without the audio, or an
/// export failed and left a dangling name. In every one of those cases the
/// correct behaviour is to ring with something, because an alarm that resolves
/// to silence is indistinguishable from an alarm that did not fire.
///
/// So this walks a chain: the user's own trimmed song, then the bundled track
/// they had selected before, then `energyUp`, which ships with the app and is
/// therefore always present.
enum AlarmTrackResolver {
    /// What ended up being chosen, so the UI and the debug panel can say so.
    struct Resolution: Equatable {
        var url: URL
        var sound: AlarmSound
        /// True when the requested track was missing and this is a substitute.
        var isFallback: Bool
    }

    /// The last resort. Bundled, so it cannot go missing without the app
    /// itself being broken.
    static let guaranteed: AlarmSound = .energyUp

    /// The file the ringer should play for this profile.
    ///
    /// `previousBundled` is the track the user had selected before importing a
    /// song, which is a better fallback than a generic default because it is
    /// still a sound they chose.
    static func resolve(
        sound: AlarmSound,
        customFileName: String?,
        previousBundled: AlarmSound?
    ) -> Resolution? {
        if sound == .ownSong {
            if let customFileName, let url = customSongURL(named: customFileName) {
                return Resolution(url: url, sound: .ownSong, isFallback: false)
            }

            // The song is gone. Fall back to a real track rather than silence.
            if let previousBundled, previousBundled != .ownSong,
               let url = bundledURL(for: previousBundled) {
                return Resolution(url: url, sound: previousBundled, isFallback: true)
            }

            if let url = bundledURL(for: guaranteed) {
                return Resolution(url: url, sound: guaranteed, isFallback: true)
            }

            return nil
        }

        if let url = bundledURL(for: sound) {
            return Resolution(url: url, sound: sound, isFallback: false)
        }

        if let url = bundledURL(for: guaranteed) {
            return Resolution(url: url, sound: guaranteed, isFallback: true)
        }

        return nil
    }

    /// What the in-app preview plays. Same chain, so previewing a broken
    /// custom song demonstrates exactly what will ring.
    static func previewURL(for sound: AlarmSound, profile: OnboardingProfile? = nil) -> URL? {
        resolve(
            sound: sound,
            customFileName: profile?.customAlarmSoundFile ?? profile?.ownSongFileName,
            previousBundled: profile?.previousBundledSound
        )?.url
    }

    /// A bundled track, as `AVAudioPlayer` wants it.
    static func bundledURL(for sound: AlarmSound) -> URL? {
        guard let name = sound.resourceName else { return nil }
        return Bundle.main.url(forResource: name, withExtension: "mp3")
    }

    // MARK: - The user's own song

    /// Where a trimmed song lives.
    ///
    /// `Library/Sounds` rather than Documents, because that is the one place
    /// the notification system will also look. One file then serves both the
    /// ringer and `UNNotificationSound`, instead of the app keeping two copies
    /// that can drift apart.
    static var soundsDirectory: URL? {
        guard let library = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first else { return nil }
        return library.appendingPathComponent("Sounds", isDirectory: true)
    }

    /// Creates `Library/Sounds` if it is not there yet. It does not exist in a
    /// fresh container.
    @discardableResult
    static func ensureSoundsDirectory() -> URL? {
        guard let directory = soundsDirectory else { return nil }
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        return directory
    }

    /// Resolves a stored file name to a URL, checking both the current home
    /// for trimmed songs and the old Documents location used by the importer
    /// on the onboarding screen.
    static func customSongURL(named fileName: String) -> URL? {
        if let sounds = soundsDirectory?.appendingPathComponent(fileName),
           FileManager.default.fileExists(atPath: sounds.path) {
            return sounds
        }

        if let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first {
            let legacy = documents.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: legacy.path) {
                return legacy
            }
        }

        return nil
    }

    /// Whether a stored custom song is actually on disk right now.
    static func customSongExists(named fileName: String?) -> Bool {
        guard let fileName else { return false }
        return customSongURL(named: fileName) != nil
    }
}
