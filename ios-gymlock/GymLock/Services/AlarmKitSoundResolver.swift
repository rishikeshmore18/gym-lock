import Foundation

/// Which sound the system alarm is handed.
///
/// Pure and `nonisolated` so the rule can be tested without AlarmKit: the
/// scheduler maps the answer to `AlertConfiguration.AlertSound` inside its own
/// `#if canImport(AlarmKit)` file.
///
/// Priority, top to bottom:
/// 1. The file named by `soundFileName` (the trimmed song's caf, or the caf of
///    whichever bundled track the coordinator already fell back to).
/// 2. The caf of the selected bundled track (`soundResource`).
/// 3. The system alarm sound.
///
/// It never answers with silence: anything missing ends at `.systemDefault`.
nonisolated enum AlarmKitSoundResolver {
    enum Choice: Equatable {
        /// The full file name, extension included, exactly as AlarmKit wants it.
        case named(String)
        case systemDefault
    }

    /// iOS 26.0 plays an error tone instead of a `.named` sound; 26.1 fixed it.
    static var osHonoursNamedSounds: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)
        )
    }

    static func resolve(
        soundFileName: String?,
        soundResource: String?,
        osHonoursNamedSounds: Bool = osHonoursNamedSounds,
        fileExists: (String) -> Bool = soundFileExists(named:)
    ) -> Choice {
        guard osHonoursNamedSounds else { return .systemDefault }

        // The bundled track always as its caf, never the mp3.
        let candidates = [soundFileName, soundResource.map { "\($0).caf" }]
        for case let fileName? in candidates where !fileName.isEmpty && fileExists(fileName) {
            return .named(fileName)
        }
        return .systemDefault
    }

    /// Looks where the system looks: the main bundle, then `Library/Sounds`.
    static func soundFileExists(named fileName: String) -> Bool {
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension

        if Bundle.main.url(forResource: name, withExtension: ext.isEmpty ? nil : ext) != nil {
            return true
        }

        guard let library = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first else { return false }

        let path = library
            .appendingPathComponent("Sounds", isDirectory: true)
            .appendingPathComponent(fileName)
            .path
        return FileManager.default.fileExists(atPath: path)
    }
}
