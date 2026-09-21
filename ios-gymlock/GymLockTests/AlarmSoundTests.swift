import Foundation
import Testing
@testable import GymLock

/// The sound rules: which file each player gets, and what rings when the
/// chosen track is not there.
///
/// The format split is the subtle one. `AVAudioPlayer` decodes mp3 and the
/// system sound facility does not — it accepts only Linear PCM, IMA4, µLaw or
/// aLaw in aiff, wav or caf, and silently substitutes its own default for
/// anything else. A test is the only thing that stops that regressing back to
/// "custom" alarm tones nobody ever actually hears.
@Suite("Alarm sound")
@MainActor
struct AlarmSoundTests {
    // MARK: - Which file goes to which player

    @Test func everyBundledTrackOffersBothFormats() {
        for sound in AlarmSound.bundled {
            #expect(sound.ringerFileName?.hasSuffix(".mp3") == true)
            #expect(sound.notificationFileName?.hasSuffix(".caf") == true)
        }
    }

    /// The whole point of the split: a notification must never be handed an
    /// mp3, because it will play the default system sound instead.
    @Test func noNotificationFileIsAnMP3() {
        for sound in AlarmSound.allCases {
            #expect(sound.notificationFileName?.hasSuffix(".mp3") != true)
        }
    }

    @Test func theUsersOwnSongHasNoBundledFile() {
        #expect(AlarmSound.ownSong.resourceName == nil)
        #expect(AlarmSound.ownSong.ringerFileName == nil)
        #expect(AlarmSound.ownSong.notificationFileName == nil)
    }

    // MARK: - The fallback chain

    private func makeProfile(
        sound: AlarmSound,
        customFile: String? = nil,
        previous: AlarmSound? = nil
    ) -> OnboardingProfile {
        var profile = OnboardingProfile.default
        profile.alarmSound = sound
        profile.customAlarmSoundFile = customFile
        profile.previousBundledSound = previous
        return profile
    }

    /// A custom song that is gone must fall back to a track the user actually
    /// chose, not to silence.
    @Test func aMissingCustomSongFallsBackToThePreviousChoice() {
        let resolution = AlarmTrackResolver.resolve(
            sound: .ownSong,
            customFileName: "does-not-exist-\(UUID().uuidString).m4a",
            previousBundled: .beastMode
        )

        #expect(resolution?.sound == .beastMode)
        #expect(resolution?.isFallback == true)
    }

    /// With nothing to fall back to, the guaranteed bundled track rings.
    @Test func aMissingCustomSongWithNoHistoryFallsBackToTheGuaranteedTrack() {
        let resolution = AlarmTrackResolver.resolve(
            sound: .ownSong,
            customFileName: nil,
            previousBundled: nil
        )

        #expect(resolution?.sound == AlarmTrackResolver.guaranteed)
        #expect(resolution?.isFallback == true)
    }

    /// The end of the chain is bundled, so it can only be missing if the app
    /// itself is broken. This is the test that says "never silence".
    @Test func theChainAlwaysProducesSomething() {
        let resolution = AlarmTrackResolver.resolve(
            sound: .ownSong,
            customFileName: "gone.m4a",
            previousBundled: nil
        )
        #expect(resolution != nil)
    }

    /// A custom song that is present wins, and is not reported as a fallback.
    @Test func anExistingCustomSongIsUsedAsIs() throws {
        let directory = try #require(AlarmTrackResolver.ensureSoundsDirectory())
        let fileName = "test-clip-\(UUID().uuidString).m4a"
        let url = directory.appendingPathComponent(fileName)

        try Data([0x00, 0x01, 0x02]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let resolution = AlarmTrackResolver.resolve(
            sound: .ownSong,
            customFileName: fileName,
            previousBundled: .focusTime
        )

        #expect(resolution?.sound == .ownSong)
        #expect(resolution?.isFallback == false)
        #expect(resolution?.url == url)
    }

    @Test func aMissingNameIsNotMistakenForAFile() {
        #expect(!AlarmTrackResolver.customSongExists(named: nil))
        #expect(!AlarmTrackResolver.customSongExists(named: "nothing-here.m4a"))
    }

    // MARK: - The profile

    /// The trimmer writes one field and the older importer wrote another.
    /// Both have to keep working for anyone mid-upgrade.
    @Test func theTrimmedClipWinsOverAnOlderImport() {
        var profile = OnboardingProfile.default
        profile.ownSongFileName = "old-import.m4a"
        profile.customAlarmSoundFile = "gymlock-custom-alarm.m4a"

        #expect(profile.effectiveCustomSoundFile == "gymlock-custom-alarm.m4a")

        profile.customAlarmSoundFile = nil
        #expect(profile.effectiveCustomSoundFile == "old-import.m4a")
    }

    @Test func theLabelPrefersTheTrimmedTitle() {
        var profile = OnboardingProfile.default
        profile.alarmSound = .ownSong
        profile.ownSongTitle = "Old Title"
        profile.customAlarmSoundTitle = "New Title"

        #expect(profile.alarmSoundLabel == "New Title")
    }

    /// A profile stored before the trimmer existed must decode cleanly, or
    /// everyone who updates gets sent back through onboarding.
    @Test func anOlderProfileDecodesWithoutTheNewFields() throws {
        let legacy = """
        {
          "targetWorkoutsPerWeek": 4,
          "currentWorkoutsPerWeek": 1,
          "failureWindowOther": "",
          "failureTime": { "hour": 17, "minute": 30 },
          "failureReasons": [],
          "selectedDistractingApps": [],
          "distractingAppOther": "",
          "bedtime": { "hour": 23, "minute": 0 },
          "alarmSound": "beastMode",
          "comebackModeEnabled": true,
          "hasActivated": true
        }
        """

        let profile = try JSONDecoder().decode(
            OnboardingProfile.self,
            from: Data(legacy.utf8)
        )

        #expect(profile.alarmSound == .beastMode)
        #expect(profile.customAlarmSoundFile == nil)
        #expect(profile.customAlarmTrimStart == nil)
        #expect(profile.previousBundledSound == nil)
        #expect(profile.targetWorkoutsPerWeek == 4)
    }

    // MARK: - Lengths and limits

    /// Over thirty seconds the system throws the file away and plays its own
    /// default, so the clip length has to stay under the cap with headroom.
    @Test func theTrimmedClipFitsUnderThePlatformCap() {
        #expect(SongTrimService.clipDuration < 30)
        #expect(SongTrimService.clipDuration > 20)
    }

    /// The clip is written to a fixed name so a re-trim replaces rather than
    /// filling the container with abandoned exports.
    @Test func theClipFileNamesAreStableAndPaired() {
        #expect(SongTrimService.clipFileName.hasSuffix(".m4a"))
        #expect(SongTrimService.notificationClipFileName.hasSuffix(".caf"))

        let clipBase = (SongTrimService.clipFileName as NSString).deletingPathExtension
        let notificationBase = (SongTrimService.notificationClipFileName as NSString)
            .deletingPathExtension
        #expect(clipBase == notificationBase)
    }

    // MARK: - The ringer's shape

    /// Nobody should be detonated awake at full volume by an app whose whole
    /// voice is quiet.
    @Test func theRingerStartsQuietAndClimbs() {
        #expect(AlarmRinger.startVolume > 0)
        #expect(AlarmRinger.startVolume <= 0.3)
        #expect(AlarmRinger.escalationDuration >= 30)
        #expect(AlarmRinger.escalationStep < AlarmRinger.escalationDuration)
    }

    /// A phone ringing into an empty flat stops eventually.
    @Test func theRingerHasACeiling() {
        #expect(AlarmRinger.maximumRingDuration == 10 * 60)
        #expect(AlarmRinger.maximumRingDuration > AlarmRinger.escalationDuration)
    }

    @Test func aFreshRingerIsSilent() {
        let ringer = AlarmRinger()
        #expect(!ringer.isRinging)
        #expect(ringer.intensity == 0)
        #expect(ringer.playingSound == nil)
    }

    // MARK: - Copy

    /// The standing rule for this codebase, enforced the same way
    /// `SessionVoiceTests` enforces it for the session copy.
    @Test func noSoundErrorUsesAnEmDash() {
        let messages: [String] = [
            SongTrimService.TrimError.protectedTrack.errorDescription ?? "",
            SongTrimService.TrimError.unreadable.errorDescription ?? "",
            SongTrimService.TrimError.exportFailed.errorDescription ?? "",
            SongTrimService.TrimError.noSoundsDirectory.errorDescription ?? "",
        ]

        for message in messages {
            #expect(!message.contains("—"))
            #expect(!message.isEmpty)
        }
    }
}
