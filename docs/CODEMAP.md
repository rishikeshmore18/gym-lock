# GymLock Codemap (read this first, ~1.5k tokens)
Repo: rishikeshmore18/gym-lock. All Swift is under `ios-gymlock/GymLock/` (408 files, ~119k lines). Paths below are relative to that folder unless they start with `docs/` or a target name.
Docs: `docs/FLOW.md` (behaviour rules), `docs/UI-RULES.md` (design rules), `CLAUDE.md`, `rork.json`, `docs/hero-pack/` (Matrix/Ridge hero reference), `docs/intro-reference/` (intro images).
Last mapped commit: f62b153 + trip-screen branch (2026-11-24).

## How to find anything (cheapest order)
1. Find the feature in the table below, then open only the named file(s).
2. Not listed? `grep -i "word" docs/CODEMAP-FILES.md` (one line per file: lines, types, purpose).
3. Need a symbol inside a file? `grep -n "name" <file>` then read that range with offset/limit. Never read big files whole (biggest: GymSessionCoordinator 2425 lines, WakeIntroView 2268, DayDial 1740, GymSessionCoordinator+Debug 1584, AlarmSettingsView 1322, SongTrimmerView 1118).
4. If a change adds, renames or deletes files, run the regenerate command at the top of CODEMAP-FILES.md and update the table here.

## Feature → where it lives
| Feature | Files |
|---|---|
| App entry, routing | GymLockApp, ContentView (routes onboarding / morning setup / home) |
| Onboarding story (31 scenes) | Views/Onboarding/OnboardingFlowView + *Page files; Views/Onboarding/System/* (setup pages); Views/Onboarding/Intro/*; Models/OnboardingProfile |
| Home tab (today card, calendar strip, streak) | Views/Home/TodayHomeView, CalendarStripView, StreakChip/StreakCard/StreakIntroController, StreakRiskBannerView; Views/HomeView (older home) |
| Tab bar and shell | Views/Home/RootTabView, RootTabBar (Liquid Glass bar), GlassSurface |
| Hero card (Matrix / Ridge art) | Views/Home/Hero/DynamicHeroCard; Hero/Matrix/* (engine, board, 20 scenes MX*.swift in Matrix/Scenes); Hero/Ridge/* (canvas, runtime, Gen/RW*); card style chosen in Views/Home/PreferencesView; copy Models/HeroCopy; state Models/HeroMomentResolver, HeroMoment, HomeStage |
| "Done" celebration flow | Views/Home/Hero/DoneFlow/*; ViewModels/CelebrationQueue |
| Progress tab (stats, period card, charts) | Views/Progress/ProgressTabView, ProgressPeriodCard, ProgressChartKit, ProgressStatCard; Models/ProgressPeriod; ViewModels/ProgressPeriodModel |
| Progress photos | Views/Progress/ProgressPhoto* files; Services/ProgressPhotoStore, ProgressPhotoCameraModel; Models/ProgressPhoto, PendingProgressPhoto |
| Hall of Fame (film reel) | Views/Progress/HallOfFame/* (HallOfFameView, FilmStripView, ReelCanvas, ReelScene, HallOfFameModel) |
| Badges | Views/Progress/Badges/*; Models/Badges/BadgeEngine; ViewModels/BadgeStore |
| Share / story editor | Views/Share/*; Views/Share/Frames/*; Models/Share/*; Services/Share/*; ViewModels/StoryEditorModel |
| Community, Profile, Preferences | Views/Home/CommunityView, ProfileView, PreferencesView |
| Alarm settings and rules | Views/Morning/AlarmSettingsView, AlarmSlotEditor, AlarmSound*, AlarmScreenPickerView, AlarmHapticsListView, DayDial, RhythmDial; Models/AlarmRules, AlarmScreenStyle, AlarmHaptic |
| Alarm scheduling / ringing | Services/AlarmKitAlarmScheduler, NotificationAlarmScheduler, AlarmScheduling, AlarmRinger, AlarmSoundPlayer, AlarmIntents, AlarmHandoff, MorningNotifier; ring screen Views/Morning/AlarmFiredView |
| Wake-up intro screen | Views/Morning/WakeIntro/Core (WakeIntroView, WakeStage); Matrix/ and Ridge/ variants; Integration/WakeIntroPresenter |
| Morning plan and schedule | Models/MorningPlan, GymSchedule; Views/Morning/MorningAlarmPlanView, SleepWakeRhythmView, MorningSetupFlowView, MorningFlowView, MorningKit |
| Session state machine (the brain) | Services/GymSessionCoordinator (+Debug); Models/GymSession, SessionResume, SessionEvent, SkipRules, SessionVoice |
| Missions (wake-up tasks) | Views/Morning/ActivationMissionView, MissionRunnerView; Views/Morning/Missions/* ; Models/ActivationMission; Services/MissionVerification, VisionMissionVerifier, SpeechMissionVerifier, MotionMissionMonitor, MissionCameraModel |
| Trip page (countdown, leaving home, live map, arrival check) | Views/Morning/Trip/* (TripView host, TripModel route+GPS, RidgeTripView, MatrixTripView, TripConfetti, TripSimulation debug); routed from Views/Morning/MorningFlowView |
| Gym location, arrival, departure | Models/GymLocation; Services/GymArrivalMonitor, SessionLocationMonitor, GymVisitTracker, GymSearchService; Views/Morning/GymPickerView, GymWindowView, ArrivalViews, DepartedView (fallbacks when no gym is set); Models/GymVisit |
| Screen Time lock (Family Controls) | Services/FamilyControlsShieldService, AppShielding, DemoShieldService; Views/Morning/BlockedAppsSetupView; targets GymLockShieldAction, GymLockShieldConfig, GymLockNightMonitor; shared code `ScreenTimeShared/` |
| Workout proof, "can't today" | Services/HealthWorkoutObserver, WorkoutVerification; Views/Morning/QuickWorkoutView, HomeWorkoutProofView, CantTodayView, StillGettingReadyView |
| Momentum and freezes | Models/MomentumLog, MomentumField, FreezeCalendar; Views/Morning/MomentumSavedView; Views/Home/Visuals/Momentum* |
| App-wide state, subscription | ViewModels/AppStore, LaunchCover; Services/SubscriptionStore, CrashSentinel; Models/NotificationRoute |
| Design tokens, haptics | Utilities/Theme, Haptics; reusable UI in Views/Components/* (GlassCircleButton, HoldToCommitButton, ValueWheel, VerticalPager, ...) |
| Debug-only screens | Views/Morning/DebugSimulator/*, DebugMorningPanel, Home/Hero/HeroCardLabView (skip in design work) |
| Tests | GymLockTests (39 files, named after what they test), GymLockUITests |

## Rules of thumb
- Models are plain data and rules; Services touch the system (alarms, location, Screen Time); Views draw; ViewModels hold app state.
- Matrix and Ridge each have a parity twin (`MatrixParity*`) used to check Swift against the web reference.
- Light mode only. Liquid Glass only on floating controls (see docs/UI-RULES.md).
