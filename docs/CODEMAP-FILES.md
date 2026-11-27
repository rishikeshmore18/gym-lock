GymLock/Config.swift [15] Config — Virtual read-only view of public environment variables available to Swift code.
GymLock/ContentView.swift [110] ContentView — Routes between the onboarding journey, the morning setup, and home.
GymLock/GymLockApp.swift [86] GymLockApp — GymLock
GymLock/Models/ActivationMission.swift [232] MissionCapability,ActivationMissionType,VisionSubject,+ActivationMissionType,MissionVerificationStatus — What a mission needs from the device before it can honestly be offered.
GymLock/Models/AlarmDialContext.swift [64] AlarmDialContext — Which half of the dial the Alarm screen is talking about.
GymLock/Models/AlarmHaptic.swift [123] AlarmHaptic,Beat — The vibration that plays alongside the alarm track while it rings in the
GymLock/Models/AlarmRules.swift [655] +MorningRhythm,PausedWeekAlarmID,OneOffAlarm,CodingKeys,PlannedAlarm,AlarmPlan… — Which flow a gym day runs (`docs/FLOW.md`, "Step 0").
GymLock/Models/AlarmScreenStyle.swift [78] AlarmScreenStyle,AlarmScreenDraft — Which screen the user wants to wake up to when the alarm rings.
GymLock/Models/Badges/BadgeEngine.swift [370] BadgeProgress,Unit,BadgeState,BadgeFacts,Week,BadgeEngine… — How far a locked badge has come, in the unit its rule counts.
GymLock/Models/FreezeCalendar.swift [90] Grant — When freezes arrive and when they expire (FLOW, Flow 5).
GymLock/Models/GymLocation.swift [117] GymLocation,ArrivalTuning — The gym the user actually goes to.
GymLock/Models/GymSchedule.swift [92] Weekday,TimeOfDay,GymSchedule — A day of the week, ordered Monday-first to match the schedule selector.
GymLock/Models/GymSession.swift [444] GymSessionState,SessionAnchor,CantTodayResolution,SnoozeRealertDelivery,GymSession,+GymSession — Every position a morning can be in, as one value.
GymLock/Models/GymVisit.swift [312] CodingKeys — Why a gym visit counts (FLOW, Flow 3). `unproven` is a gym visit that has
GymLock/Models/HeroCopy.swift [535] HeroCopy,Row,HeroCopyFacts — The words on the Dynamic hero card, from the prototype's copy tables (copy12.ts STATE12 an
GymLock/Models/HeroMoment.swift [301] HeroRotationStore — Which Dynamic hero card draws Home. Only Dynamic ships; there is no Classic.
GymLock/Models/HeroMomentResolver.swift [530] HeroMomentRules,HeroMomentState,HeroDayFacts,HeroMomentResolver — Moments a user meets once in their life (spec §2.2).
GymLock/Models/HomeStage.swift [697] HomeCardModel,HeroStage,ChecklistItem,ProtectionCard,Mood,NextCard… — One rendered frame of home's card section, derived entirely from real state.
GymLock/Models/Illustration.swift [158] Illustration,LoopState — The user-supplied illustration library.
GymLock/Models/MomentumField.swift [208] MomentumMark,MomentumDay,MomentumField — What one day contributed to the week.
GymLock/Models/MomentumLog.swift [266] SessionOutcomeKind,SessionOutcome,CodingKeys,MomentumLog,DepartureMessage — What actually happened on a planned session.
GymLock/Models/MorningPlan.swift [748] SessionDaypart,MorningRhythm,+MorningRhythm,CodingKeys,LegacyKeys,NightLockWindow… — Which part of the day a session sits in.
GymLock/Models/NotificationRoute.swift [176] NotificationRoute,SessionKind,ID — What a notification the user touched actually is, and so what the tap may do.
GymLock/Models/OnboardingProfile.swift [405] FailureWindow,FailureReason,DistractingApp,NightScrollingFrequency,AlarmSound,Day0Media… — When the user's plan usually falls apart.
GymLock/Models/PendingProgressPhoto.swift [37]  — A photo waiting on the user's decision because its day is already taken.
GymLock/Models/ProgressPeriod.swift [616] ProgressDayStatus,ProgressDay,ProgressTally,ProgressPeriodPresentation,+ProgressPeriodPresentation,ProgressWeekSummary… — What one day inside a displayed period turned out to be.
GymLock/Models/ProgressPhoto.swift [298] +ProgressPhoto,CodingKeys,ProgressPhotoSlide,Marker,Content — Where a progress photo came from. Recorded for diagnostics only — the card
GymLock/Models/SessionEvent.swift [157] SessionEventKind,SessionEvent,SessionEventLog,DetectedWorkout,CodingKeys — A behavioural event worth remembering.
GymLock/Models/SessionResume.swift [223] Decision,Resolution — Decides whether a morning should be running right now.
GymLock/Models/SessionVoice.swift [223]  — Every line the session flow says, chosen by when the user actually trains.
GymLock/Models/Share/FrameAvailability.swift [78]  — Where one frame stands for one share.
GymLock/Models/Share/Milestone.swift [135] Milestone,Kind — A threshold crossed on a specific day.
GymLock/Models/Share/PhotoTransform.swift [124]  — How the photograph is cropped into the canvas.
GymLock/Models/Share/ShareContext.swift [184] ShareOrigin,StoryAssets,ShareContext,+ShareContext — Where a share was started from.
GymLock/Models/Share/ShareContextBuilder.swift [276] ShareContextBuilder — Assembles a `ShareContext` from the records the app already keeps.
GymLock/Models/Share/ShareFrame.swift [79]  — The compositions a progress photo can be shared as.
GymLock/Models/Share/ShareFrameAvailability.swift [194] ShareFrameAvailability — Which frames a context can honestly support.
GymLock/Models/Share/StoryFormat.swift [68]  — Where the text may safely sit, as fractions of the canvas.
GymLock/Models/Share/StoryLayout.swift [292] StoryLayout,TypeScale,StoryElementLayout,StoryElementLayouts — The movable pieces of a frame.
GymLock/Models/SkipRules.swift [278] Choice — One of the three doors on the skip screen (FLOW, Flow 4).
GymLock/Models/SleepSchedule.swift [472] +Weekday,SleepSchedule,Toggle,SleepRules,Night,+MorningPlan… — The day before, wrapping Monday back to Sunday.
GymLock/Models/StreakEngine.swift [263] StreakEngine — Turns the ledger into the streak, one week at a time.
GymLock/Models/StreakRisk.swift [303] NoticeTime,StreakRiskBanner,StreakRisk,Notice,FreezeNotice,Planned… — The time of day the streak-at-risk and freeze notifications use: 10:00,
GymLock/Models/StreakVault.swift [212] CodingKeys,+StreakVault — The rules of the streak, in one place.
GymLock/Models/WeeklyGoals.swift [71] WeeklyGoals — The weekly goal of any week, past, live or future (FLOW, item 19a).
GymLock/Models/WindDownLock.swift [92] WindDownLock — Pure clock maths for the wind-down lock.
GymLock/Models/WorkoutDayStatus.swift [150] WorkoutDayStatus,TrainingDay,DayStatusIndex — What a single day on the home calendar is allowed to say.
GymLock/Services/AlarmHandoff.swift [132] +Notification.Name,Pending — Posted the moment something outside the app's object graph leaves a note
GymLock/Services/AlarmIntents.swift [87] StartGymSessionIntent,SnoozeGymSessionIntent — Runs when the user taps "I'm up" (or "I'm going") on the system alarm.
GymLock/Services/AlarmKitAlarmScheduler.swift [313] GymAlarmMetadata,AlarmKitAlarmScheduler,+Weekday — AlarmKit builds its alert presentation on ActivityKit's data models, so the
GymLock/Services/AlarmKitSoundResolver.swift [67] Choice — Which sound the system alarm is handed.
GymLock/Services/AlarmNotificationDelegate.swift [135] AlarmNotificationDelegate,Category,Action — Turns a notification the user touched into a session that actually starts.
GymLock/Services/AlarmObserverBag.swift [55] AlarmObserverBag — Holds the coordinator's two long-lived observers and tears them down when it
GymLock/Services/AlarmRinger.swift [322] AlarmRinger — The sound the user actually wakes up to.
GymLock/Services/AlarmScheduling.swift [189] GymAlarmRequest,AlarmDeliveryCapability,AlarmAuthorization,AlarmScheduling,SnoozeRealertTemplate,AlarmSchedulerFactory… — A recurring gym alarm, described in terms GymLock cares about rather than in
GymLock/Services/AlarmSoundPlayer.swift [100] AlarmSoundPlayer — Previews the bundled alarm tracks.
GymLock/Services/AlarmTrackResolver.swift [141] AlarmTrackResolver,Resolution — Finds the audio file that should actually ring, and never returns nothing.
GymLock/Services/AppShielding.swift [155] ShieldCapability,ShieldAuthorization,AppShielding,+AppShielding,ShieldPolicy,AppShieldingFactory — Which blocking backend is actually in play.
GymLock/Services/CrashSentinel.swift [213]  — GymLock
GymLock/Services/Day0CameraModel.swift [285] Day0CameraModel,Availability,CaptureSetupError,+Day0CameraModel — Drives the Day 0 capture session.
GymLock/Services/DemoShieldService.swift [122] DemoShieldService — Shielding that runs the whole flow without blocking anything.
GymLock/Services/FamilyControlsShieldService.swift [390] FamilyControlsShieldService — Real OS-level app blocking through Apple's Screen Time stack.
GymLock/Services/GymArrivalMonitor.swift [427] GymArrivalMonitor,Availability,Phase,+GymArrivalMonitor — Watches for the user actually arriving at their gym.
GymLock/Services/GymSearchService.swift [151] GymSearchService,GymSearchResult — Finds the user's gym on the map so they never type a coordinate.
GymLock/Services/GymSessionCoordinator+Debug.swift [1751] +GymSessionCoordinator,DebugStep,DebugDay0 — Jumps the morning to any state without waiting for a real 6:30 AM, a real
GymLock/Services/GymSessionCoordinator.swift [2504] MorningRoute,CantTodayOrigin,GymSessionCoordinator,Key — Which screen the morning flow should be showing.
GymLock/Services/GymVisitTracker.swift [242] GymVisitTracker,Key — Follows every gym visit from arrival until it is settled (FLOW, Flow 3).
GymLock/Services/HealthWorkoutObserver.swift [320] HealthWorkoutObserver,Availability,+HKWorkoutActivityType — Notices workouts that Apple Health already recorded.
GymLock/Services/MissionCameraModel.swift [172] MissionCameraModel,Availability,+MissionCameraModel — The camera behind the photo missions.
GymLock/Services/MissionVerification.swift [55] MissionVerificationResult,MissionVerificationProviding,MissionVerificationBackend — The result of looking at one mission photo.
GymLock/Services/MorningNotifier.swift [315] MorningNotifier,ID — The only place morning notifications are sent from.
GymLock/Services/MotionMissionMonitor.swift [82] MotionMissionMonitor,Availability — Counts steps for the movement missions.
GymLock/Services/NotificationAlarmScheduler.swift [144] NotificationAlarmScheduler — The alarm backend that works everywhere.
GymLock/Services/PendingNotificationRoute.swift [40] PendingNotificationRoute,Entry — The last non-alarm notification the user opened the app from.
GymLock/Services/ProgressPhotoCameraModel.swift [416] LensOption,ProgressPhotoCameraModel,Availability,+ProgressPhotoCameraModel — One lens the user can jump to, as the Camera app's chips offer them.
GymLock/Services/ProgressPhotoImageLoader.swift [106] ProgressPhotoImageLoader,ProgressPhotoDemoArtwork — Loads and caches progress-photo thumbnails.
GymLock/Services/ProgressPhotoStore.swift [598] ProgressPhotoStore,AddResult,+UIImage — Owns the user's progress photos: the files on disk and the metadata index.
GymLock/Services/SessionLocationMonitor.swift [156] SessionLocationMonitor,Availability,+SessionLocationMonitor — Watches whether the user has actually left where they started this morning.
GymLock/Services/Share/ShareConfiguration.swift [16] ShareConfiguration — Third-party integration switches.
GymLock/Services/Share/ShareService.swift [68] ShareService — The rendered Story, ready for the share sheet.
GymLock/Services/Share/StoryLayoutStore.swift [108] StoryLayoutStore — Remembers how the user framed and arranged a share.
GymLock/Services/Share/StoryRenderer.swift [168] StoryRenderer,RenderError — Turns the canvas view into pixels.
GymLock/Services/SongTrimService.swift [549] SongTrimService,Settle — Reads a track's shape and cuts the thirty seconds that will wake the user.
GymLock/Services/SpeechMissionVerifier.swift [206] SpeechMissionVerifier,Availability — Listens for the mirror phrase being read out loud.
GymLock/Services/SubscriptionStore.swift [164] SubscriptionStore,LoadState,+Product — Loads the real subscription products from the App Store.
GymLock/Services/VisionMissionVerifier.swift [100] VisionMissionVerifier — On-device mission verification using Apple's Vision framework.
GymLock/Services/WindDownController.swift [73] WindDownController — Owns the wind-down lock: applies and releases a `.windDown` shield for the
GymLock/Services/WorkoutVerification.swift [67] WorkoutVerificationOutcome,WorkoutVerificationProviding,UnverifiedWorkoutProvider,DebugWorkoutProvider,WorkoutVerificationFactory — What a workout check concluded.
GymLock/Utilities/AppInstallDate.swift [39]  — The day GymLock was first installed on this iPhone.
GymLock/Utilities/Haptics.swift [234] Haptics — Small wrapper around the feedback engines so views stay declarative.
GymLock/Utilities/Theme.swift [137] Theme,+View,PrimaryCTAStyle — GymLock's warm, Airbnb-inspired design system.
GymLock/ViewModels/AppStore.swift [589] AppStage,AppStore,Key — Where the user currently is in the app's lifecycle.
GymLock/ViewModels/BadgeStore.swift [135] BadgeStore,Record — The badges as the screens see them.
GymLock/ViewModels/CalendarWindow.swift [89] CalendarWindow — The bounded set of days the calendar strip currently has in memory.
GymLock/ViewModels/CelebrationQueue.swift [607] Kind,CelebrationQueue,FlowProgress,Persisted,Presentation — One celebration waiting for its turn (02-experience-spec §3.2).
GymLock/ViewModels/LaunchCover.swift [152] LaunchCover,Phase,Timing — The branded cover every open of the app starts on, while the real app
GymLock/ViewModels/ProgressPeriodModel.swift [179] ProgressPeriodModel — Holds what the Progress period card is currently showing.
GymLock/ViewModels/ProgressSpotlightModel.swift [109] ProgressSpotlightModel,Phase — The Progress spotlight's presentation state (FLOW, Flow 3, "The Progress
GymLock/ViewModels/StoryEditorModel.swift [336] StoryEditorModel — Everything the Story editor knows, in one place.
GymLock/Views/Components/AccentedText.swift [35] AccentedText — Builds a headline where selected substrings are tinted with the accent
GymLock/Views/Components/AppGlyph.swift [109] AppGlyph,+DistractingApp — A recognisable stand-in for one of the apps that usually wins.
GymLock/Views/Components/ChoiceRow.swift [154] ChoiceRow,PressableRowStyle,OtherDetailField — The single option control used by every question in the system-building part
GymLock/Views/Components/CollapsingTitle.swift [185] CollapsingTitleMetrics,CollapsingTitle,Start — The numbers behind the collapsing page title, in one place so every screen
GymLock/Views/Components/CountingNumber.swift [43] CountingNumber — A number that counts up to its value instead of appearing at it.
GymLock/Views/Components/Day0CaptureSheet.swift [231] CameraPreview,PreviewView,Day0CaptureSheet — Live camera preview for the Day 0 capture.
GymLock/Views/Components/Day0Thumbnail.swift [80] Day0Thumbnail — Shows a captured Day 0 photo or the first frame of a Day 0 clip.
GymLock/Views/Components/FloatingTitleScreen.swift [108] HeaderMetrics,FloatingTitleScreen — Spacing this screen owns. The title's own numbers live in
GymLock/Views/Components/GlassCircleButton.swift [173] GlassCircleButton,Role,LegacyGlassButtonStyle — The round Liquid Glass buttons Apple puts in the corners of its full-screen
GymLock/Views/Components/GlassShatterView.swift [345] ScreenSnapshot,SeededRandom,GlassShard,GlassShatterView — Grabs the pixels currently on screen as a single image.
GymLock/Views/Components/HoldToCommitButton.swift [175] HoldToCommitButton — A button you have to mean.
GymLock/Views/Components/IllustrationView.swift [36] IllustrationView — Presents one of the supplied illustrations cropped to its drawing.
GymLock/Views/Components/InteractivePopEnabler.swift [69] InteractivePopEnabler,Probe,PopGestureDelegate — Keeps the edge swipe back working on pages that hide the navigation bar
GymLock/Views/Components/LaunchReportView.swift [57] LaunchReportView — Temporary: shown instead of the app when the previous launch did not finish (see CrashSent
GymLock/Views/Components/LockDemoStrip.swift [109] LockDemoStrip,VerificationRow,+OnboardingProfile — The row of app icons shared by the lock and unlock demonstrations.
GymLock/Views/Components/LoopFilmView.swift [53] LoopFilmView — The loop artwork played back as a fixed shot.
GymLock/Views/Components/MiniWaveform.swift [30] MiniWaveform — Three bars that move with the preview's actual output level.
GymLock/Views/Components/OnboardingScene.swift [84] OnboardingScene,QuietScene — The shared scene scaffold that keeps every onboarding page anchored the same
GymLock/Views/Components/PagerInteractionLock.swift [44] PagerInteractionLock,+View — Lets an interactive control temporarily take the vertical drag away from the
GymLock/Views/Components/RetentionChart.swift [175] RetentionChart — The two-curve retention chart. Both series leave the same point in week 1 —
GymLock/Views/Components/SceneMotion.swift [162] SceneRevealKey,+EnvironmentValues,SceneRole,SceneElementModifier,+View,BreathingModifier… — How arrived the surrounding scene is: `0` when it sits a full page away
GymLock/Views/Components/SwipeUpHint.swift [34] SwipeUpHint — The recurring bottom-edge affordance that teaches the vertical page gesture.
GymLock/Views/Components/SystemScene.swift [141] SystemScene,SceneHeading,SceneContinueButton,StaggeredAppearance,+View — The scaffold for the system-building half of onboarding.
GymLock/Views/Components/ValueWheel.swift [293] ValueWheel,WheelRows,TimeWheel — A drag-driven picker wheel in the manner of the iOS date picker, styled in
GymLock/Views/Components/VerticalPager.swift [169] VerticalPager — A full-screen vertical pager driving one continuous onboarding story.
GymLock/Views/Components/WordWheel.swift [96] WordWheel — An endlessly rotating vertical word wheel, in the manner of a slot-machine
GymLock/Views/Home/AddGymDaySheet.swift [113] AddGymDaySheet — PLACEHOLDER UI: designed in Step 3
GymLock/Views/Home/CalendarStripView.swift [247] CalendarStripView,DayMarkerCell — The horizontally endless date strip.
GymLock/Views/Home/CommunityView.swift [108] CommunityView — The Community tab.
GymLock/Views/Home/FlameAnimationView.swift [172] FlameAnimationView,FlameArtwork,FlameFigure,FlameGlow,FlameAsset — The supplied dotLottie flame.
GymLock/Views/Home/GlassSurface.swift [40] GlassCapsuleBackground,+View — Liquid Glass where the OS supports it, an honest fallback where it doesn't.
GymLock/Views/Home/GymLockLaunchIntroView.swift [80] GymLockLaunchIntroView — What a cold launch opens on: the canvas and the real logo, nothing else.
GymLock/Views/Home/Hero/DoneFlow/DoneFlowBuilder.swift [451] DoneFlowBuilder,Resume,Built,SessionWindow,Record — Builds the done flow from the user's own record (02-experience-spec §4). Every figure on e
GymLock/Views/Home/Hero/DoneFlow/DoneFlowHost.swift [140] DoneFlowHost,DoneFlowStage,DoneFlowGlassCircle — The done flow on screen (02-experience-spec §4.2–4.3).
GymLock/Views/Home/Hero/DynamicHeroCard.swift [160] DynamicHeroCard,DynamicHeroFace — The Dynamic hero card on Home (02-experience-spec §2, §5, §6).
GymLock/Views/Home/Hero/HeroCardLabView.swift [270] HeroCardLabView,Mode,Scheme,ParityState — Debug-only lab for the Dynamic hero card.
GymLock/Views/Home/Hero/HeroHapticBlocker.swift [11] +View — Silences every hero haptic (the card and the done flow) while this view is on screen
GymLock/Views/Home/Hero/HeroHaptics.swift [208] HeroHapticPlayer,HeroHapticPolicy,HeroHapticScheduler — GymLock · Matrix / Ridge hero (native port)
GymLock/Views/Home/Hero/Matrix/JSRuntime.swift [372] JSMap,JSSet,MXTgt,MXJS,+MatrixBoard — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/MatrixBoard.swift [437] PixelRows,MatrixBoard,MX,Icon,MatrixLED,Pixel… — GymLock · Matrix hero (native port)
GymLock/Views/Home/Hero/Matrix/MatrixCardView.swift [897] MatrixCardGeometry,MatrixRGB,MatrixLook,MatrixLiveClock,MatrixKineticStyle,MatrixCardCopy… — GymLock · Matrix hero card (native port)
GymLock/Views/Home/Hero/Matrix/MatrixEngine.swift [433] MatrixHash,MatrixTarget,MatrixDealOptions,MatrixEngine,BrightnessMode — GymLock · Matrix hero (native port)
GymLock/Views/Home/Hero/Matrix/MatrixParityAll.swift [558] +MatrixParity — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/MatrixParityStory.swift [164] +MatrixParity — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/MatrixScene.swift [387] MatrixWeekPos,MatrixDayData,MatrixContext,SceneOut,MatrixScene,MatrixMoment… — GymLock · Matrix hero (native port)
GymLock/Views/Home/Hero/Matrix/MatrixStoryView.swift [1486] MatrixStoryScreen,MatrixMonthPos,MatrixStoryConfig,Screen,MatrixClimaxCopy,EndFacts… — GymLock · Matrix done flow (native port)
GymLock/Views/Home/Hero/Matrix/Scenes/MXAtgym.swift [513] +MX,Atgym — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/Scenes/MXAutomatic.swift [379] +MX,Automatic — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/Scenes/MXBedtime.swift [449] +MX,Bedtime — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/Scenes/MXComeback.swift [446] +MX,Comeback — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/Scenes/MXCommute.swift [398] +MX,Commute — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/Scenes/MXCountdown.swift [498] +MX,Countdown — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/Scenes/MXDrift.swift [455] +MX,Drift — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/Scenes/MXFirstnight.swift [443] +MX,Firstnight — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/Scenes/MXFreshstart.swift [459] +MX,Freshstart — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/Scenes/MXHalfway.swift [462] +MX,Halfway — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/Scenes/MXMissed.swift [344] +MX,Missed — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/Scenes/MXPaused.swift [359] +MX,Paused — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/Scenes/MXReady.swift [456] +MX,Ready — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/Scenes/MXRest.swift [355] +MX,Rest — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/Scenes/MXSetup.swift [676] +MX,Setup — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/Scenes/MXStilltime.swift [465] +MX,Stilltime — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/Scenes/MXStory.swift [2262] +MX,Story — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/Scenes/MXVerified.swift [820] +MX,Verified — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/Scenes/MXWake.swift [546] +MX,Wake — GymLock · Matrix hero
GymLock/Views/Home/Hero/Matrix/Scenes/MXWeekkept.swift [363] +MX,Weekkept — GymLock · Matrix hero
GymLock/Views/Home/Hero/Ridge/Gen/RWProps13.swift [3056]  — RWProps13.swift
GymLock/Views/Home/Hero/Ridge/Gen/RWStage13.swift [266]  — RWStage13.swift
GymLock/Views/Home/Hero/Ridge/Gen/RWTypes.swift [268]  — GymLock · Ridge hero
GymLock/Views/Home/Hero/Ridge/Gen/RWWash.swift [934]  — GymLock · Ridge hero
GymLock/Views/Home/Hero/Ridge/Gen/RWWash2.swift [1869]  — RWWash2.swift
GymLock/Views/Home/Hero/Ridge/Gen/RWWash3.swift [1040]  — RWWash3.swift
GymLock/Views/Home/Hero/Ridge/RidgeCanvas.swift [613] Kind,State — GymLock · Ridge hero
GymLock/Views/Home/Hero/Ridge/RidgeCardView.swift [294] +MatrixLook,RidgeFrameSink,RidgeCardRuntime,Clock,RidgeCardView,RidgePaintingLayer… — GymLock · Ridge hero card (native port)
GymLock/Views/Home/Hero/Ridge/RidgeRenderThread.swift [73]  — GymLock · Ridge hero card
GymLock/Views/Home/Hero/Ridge/RidgeRuntime.swift [633] Built,Frame — GymLock · Ridge hero
GymLock/Views/Home/Hero/Ridge/RidgeStoryView.swift [1084] RidgeClimaxCopy,RidgeStoryRuntime,RidgeStoryLook,RidgeStoryView,RidgeStoryCopyLayer,RidgeTitle… — GymLock · Ridge done flow (native port)
GymLock/Views/Home/PreferencesView.swift [559] PreferencesView,PreferencesHome,CardStyleSection,TimeToGymEditor,PresetGlassRow,PresetPressStyle… — Preferences, reached from Profile.
GymLock/Views/Home/ProfileView.swift [221] ProfileView — The Profile tab.
GymLock/Views/Home/RootTabBar.swift [572] RootTab,TabMotion,TabItemLabel,TabTrack,LiquidGlassBar,MaterialTabBar… — The four destinations of the main app.
GymLock/Views/Home/RootTabView.swift [387] RootTabView — The top-level navigation shell.
GymLock/Views/Home/StreakCard.swift [239] StreakCardMetrics,StreakCardContent — How big the expanded streak card and its contents are on this device.
GymLock/Views/Home/StreakChip.swift [116] StreakChip,PressableChipStyle — The compact streak control that lives in the top-right of home.
GymLock/Views/Home/StreakIntroController.swift [342] StreakPresentation,StreakIntroController,Timing — The states the streak can be in.
GymLock/Views/Home/StreakRiskBannerView.swift [48] StreakRiskBannerView — The streak-at-risk banner on Home (FLOW, Flow 6).
GymLock/Views/Home/TodayHomeView.swift [548] TodayHomeView — The primary home screen.
GymLock/Views/Home/Visuals/GymLockVisuals.swift [539] GymLockProgressRing,GymLockStepDots,GymLockSegmentedProgress,GymLockLinearProgress,GymLockMiniBarChart,GymLockChecklist… — The circular progress treatment: thick elegant track, round caps, progress
GymLock/Views/Home/Visuals/HeroCard.swift [684] HeroMetrics,HeroCardView,ImageHero,RingHero,CountdownHero,SetupHero… — Sizing for the hero, derived from the width actually available.
GymLock/Views/Home/Visuals/HeroPreviewMatrix.swift [209] StageCanvas — Every hero state rendered side by side with the mini-card row, so the whole
GymLock/Views/Home/Visuals/MiniCardsRow.swift [301] MiniCardRole,MiniCardsRow,MiniMetrics,+View,MiniSurface,ProtectionMini… — Which mini card was tapped.
GymLock/Views/Home/Visuals/MomentumFlameProgress.swift [330] MomentumFlameProgress,Snapshot,Metrics,MomentumFlameStage,SheenPhase,NextTaskBreathe… — The right half of the Momentum card: the week's gym commitment as a row of
GymLock/Views/Home/Visuals/MomentumSection.swift [193] MomentumSection — The proof layer under the action cards.
GymLock/Views/Home/WakeTimeSheet.swift [53] WakeTimeSheet — PLACEHOLDER UI: designed in Step 3
GymLock/Views/HomeView.swift [699] HomeView,ScheduleEditSheet — The post-onboarding home. Shows the two locks the user committed to and
GymLock/Views/Morning/ActivationMissionView.swift [297] ActivationMissionView — The mission screen: one tiny physical action between "I'm going" and the countdown.
GymLock/Views/Morning/AlarmFiredView.swift [262] AlarmFiredView — The screen the user meets the instant the alarm is silenced.
GymLock/Views/Morning/AlarmGlassCapsuleButtonStyle.swift [65] AlarmGlassCapsuleButtonStyle,Role,AlarmGlassCapsuleBody — A full-width capsule action in Liquid Glass, for "hear it" and "use this".
GymLock/Views/Morning/AlarmGlassCardButtonStyle.swift [79] AlarmGlassCardButtonStyle,AlarmGlassCardBody — A single-row card that is itself the button: the Sound page's Haptics
GymLock/Views/Morning/AlarmGroupCard.swift [90] AlarmGroupCard,AlarmRowDivider,AlarmSectionHeader,AlarmValueRow — The grouped card the Alarm screen's controls live in: the repeat card's
GymLock/Views/Morning/AlarmHapticsListView.swift [170] AlarmHapticsListView,Playing,RowAccessibility — The Haptics page, after Apple's own: the default on its own at the top,
GymLock/Views/Morning/AlarmOptionRoute.swift [11] AlarmOptionRoute — The pages the Alarm screen pushes, after Apple's Edit Alarm: Sound, with
GymLock/Views/Morning/AlarmPageHeader.swift [49] AlarmPageHeader — The Alarm screen's header, for the pages pushed from it: the round glass
GymLock/Views/Morning/AlarmRowButtonStyle.swift [27] AlarmRowButtonStyle — The press state of a row inside a grouped alarm card, after Apple's lists:
GymLock/Views/Morning/AlarmScreenPickerView.swift [146] AlarmScreenPickerView,PreviewPressStyle — Which alarm screen do you want? Two previews side by side, after the Lock
GymLock/Views/Morning/AlarmScreenPreviewCard.swift [206] AlarmScreenPreview,AlarmScreenPreviewCard — A small, static picture of an alarm screen style, for the picker only.
GymLock/Views/Morning/AlarmSettingsView.swift [1322] AlarmSettingsView,HeaderSlot,CommitScope,BlockedAppsPush — The Alarm screen: the day dial, the alarm, the sound, the wind-down lock,
GymLock/Views/Morning/AlarmSlotEditor.swift [126] AlarmSlotEditor — Edits one recurring alarm.
GymLock/Views/Morning/AlarmSoundListView.swift [172] AlarmSoundListView — The Sound page, after Apple's own in Edit Alarm: Haptics at the top, the
GymLock/Views/Morning/AlarmSoundPickerSheet.swift [151] AlarmSoundPickerSheet — Reuses the tracks and the import path already built in onboarding.
GymLock/Views/Morning/AlarmSubpage.swift [48] AlarmSubpage — A page pushed from the Alarm screen, built the way the Alarm screen is:
GymLock/Views/Morning/ArrivalViews.swift [428] ConfirmingArrivalView,ArrivalTroubleView,GymArrivedView — The brief moment between "the phone thinks you're at the gym" and "you are".
GymLock/Views/Morning/AudioFilePicker.swift [50] AudioFilePicker,Coordinator — The system Files picker for one audio file, wrapped for SwiftUI.
GymLock/Views/Morning/BlockedAppsSetupView.swift [292] BlockedAppsSetupView — Choosing what GymLock actually blocks. Asked once, then never again.
GymLock/Views/Morning/CantToday/CantTodayDrum.swift [523] CantTodayDrumEngine,Phase,Event,CantTodayDrum — GymLock · the "can't today" screen (three looks)
GymLock/Views/Morning/CantToday/CantTodayHold.swift [131] +View,CantTodayHoldModifier — GymLock · the "can't today" screen (three looks)
GymLock/Views/Morning/CantToday/CantTodayModel.swift [285] CantTodayDoor,CantTodayTarget,CantTodayAllowance,CantTodayCost,Kind,CantTodayData… — GymLock · the "can't today" screen (three looks)
GymLock/Views/Morning/CantToday/CantTodayNudger.swift [134] CantTodayNudger — GymLock · the "can't today" screen (three looks)
GymLock/Views/Morning/CantToday/Day0CantTodayB.swift [1715] D0B,D0BFrameKey,D0BMetrics,D0BReel,D0BBeat,D0BResched… — Day0CantTodayB.swift
GymLock/Views/Morning/CantToday/MatrixPrinterCantTodayB.swift [2953] MatrixPrinterCantTodayB,MPBPressTarget,MPBPressStyle,MPBDrumCell,Target,Cost… — GymLock · the "can't today" screen · Matrix printer look (b)
GymLock/Views/Morning/CantToday/RidgeCantTodayB.swift [2405] RCBM,RCBTime,RCBSky,RCBCam,RCBGeo,RCBShapes… — GymLock · the "can't today" screen · Ridge look (b)
GymLock/Views/Morning/CantTodayView.swift [121] CantTodayView,CantTodayModel — The one skip screen (FLOW, Flow 4), the "can't today" page.
GymLock/Views/Morning/CelestialRhythmView.swift [192] CelestialRhythmView,+CelestialRhythmView — The moon-to-sun illustration used wherever time of day is the actual subject.
GymLock/Views/Morning/DayDial.swift [1740] DayDialModel,Grab,Zone,Bar,DragTracker,GymPush… — The maths behind the Day Dial, kept out of the view so every rule is
GymLock/Views/Morning/DebugMorningPanel.swift [686] DebugMorningPanel,SimRoute — The Day Flow Simulator: pick a scenario, see what it sets, run it once.
GymLock/Views/Morning/DebugSimulator/DaySimulatorDiagnosticsView.swift [411] SimReadingSource,SimReadingRow,DaySimulatorDiagnosticsView,SimTool — Live readings shared by Diagnostics and the Test Result view. Everything
GymLock/Views/Morning/DebugSimulator/DaySimulatorDials.swift [169] SimDialShell,SimTimeDial,SimDistanceRing,SimGymDialView — The shared shell of the three dials: a ring, a value in the middle and a
GymLock/Views/Morning/DebugSimulator/DaySimulatorLibraryView.swift [133] DaySimulatorLibraryView — All 91 scenarios in their 15 original sections, each exactly once. One tap
GymLock/Views/Morning/DebugSimulator/DaySimulatorModel.swift [167] SimRunner,SimRunDisposition,DaySimulatorModel — What the simulator needs from the app to run a scenario. Real runs pass
GymLock/Views/Morning/DebugSimulator/DaySimulatorResultView.swift [135] DaySimulatorResultView — What one run did, read-only. There is no automatic verdict: the scenarios
GymLock/Views/Morning/DebugSimulator/DebugScenarioCatalog.swift [849] SimStage,SimDayRule,SimTimeReading,SimJourney,SimJourneyReading,SimGymTime… — Every simulator scenario is still one `GymSessionCoordinator.DebugStep`.
GymLock/Views/Morning/DepartedView.swift [151] DepartedView — The moment the user actually leaves.
GymLock/Views/Morning/GymPickerView.swift [261] GymPickerView — Choosing the gym — the one extra thing the user ever configures.
GymLock/Views/Morning/GymWindowView.swift [203] GymWindowView — The live window: how long is left to be standing in the gym.
GymLock/Views/Morning/HapticBeatStrip.swift [70] HapticBeatStrip — The rhythm of a vibration, drawn as it plays: one mark per tap, a wider
GymLock/Views/Morning/HomeWorkout/HomeWorkoutModel.swift [229] HomeWorkoutLook,HomeWorkoutFacts,HomeWorkoutCopy,HomeWorkoutClock,Beat,HomeWorkoutFrame… — GymLock · the home workout (setup + count-up timer), four looks
GymLock/Views/Morning/HomeWorkout/HomeWorkoutRidge.swift [58] HomeWorkoutRidge,Fit — GymLock · shared geometry for the two Ridge home workout looks
GymLock/Views/Morning/HomeWorkout/HomeWorkoutView.swift [285] HomeWorkoutView,HomeWorkoutPressStyle — GymLock · the home workout host (setup + count-up timer)
GymLock/Views/Morning/HomeWorkout/MatrixStackLook.swift [544] MSTG,MSTArt,MSTSlot,MatrixStackLook — GymLock · home workout look "Matrix B, the stack"
GymLock/Views/Morning/HomeWorkout/MatrixSwarmLook.swift [789] MSW,MSWFont,MSWFlame,MSWCell,MSWForm,MSWCells… — GymLock · home workout, Matrix A "swarm"
GymLock/Views/Morning/HomeWorkout/RidgeAscentLook.swift [669] RHAGeo,RHATrail,Seg,Dot,RHAStar,RHACam… — GymLock · home workout look "Ridge A, ascent"
GymLock/Views/Morning/HomeWorkout/RidgeSunriseLook.swift [466] RidgeSunriseLook,RSUStar,RSUDraw,RSUSetupLayer — GymLock · home workout look "Ridge B, first light"
GymLock/Views/Morning/HomeWorkoutProofView.swift [77] HomeWorkoutProofView — The check that decides whether a home workout counts (FLOW, Flow 4).
GymLock/Views/Morning/MediaPicker.swift [113] Decision,MediaPicker,Picked,Coordinator — Whether the music library can be shown, and how to ask.
GymLock/Views/Morning/MissionRunnerView.swift [618] MissionRunnerView,Stage,RunKey,AimKey,MissionCameraPreview,PreviewView — Runs one mission to completion.
GymLock/Views/Morning/MissionToggleCard.swift [33] MissionToggleCard — Whether gym-bag missions are on, as a card.
GymLock/Views/Morning/Missions/Core/MissionContract.swift [125] MissionIcon,MissionHaptic — GymLock
GymLock/Views/Morning/Missions/Matrix/MissionDotIcon.swift [51] MissionDotIcon — GymLock
GymLock/Views/Morning/Missions/Matrix/MissionMatrixArt.swift [535]  — GymLock
GymLock/Views/Morning/Missions/Matrix/MissionMatrixEngine.swift [529] MissionMatrixEngine,+MissionMatrixEngine — GymLock
GymLock/Views/Morning/Missions/Matrix/MissionMatrixFigureView.swift [173] MissionMatrixFigureView — GymLock
GymLock/Views/Morning/Missions/Ridge/MissionRidgeBandView.swift [194] MissionRidgeBandView — GymLock
GymLock/Views/Morning/Missions/Ridge/MissionRidgeCardView.swift [357] MissionRidgeBadgeSymbol,MissionRidgeCardView — GymLock
GymLock/Views/Morning/Missions/Ridge/MissionRidgeIcon.swift [264] MissionRidgeIconShape,MissionRidgeIconKnob,MissionRidgeIcon — GymLock
GymLock/Views/Morning/Missions/Ridge/MissionRidgeWorld.swift [554]  — GymLock
GymLock/Views/Morning/Missions/Screens/MissionAttemptLedger.swift [64] MissionAttemptLedger — GymLock · mission screens
GymLock/Views/Morning/Missions/Screens/MissionCameraStage.swift [518] MissionCameraNotice,MissionCameraStage,MissionCameraDotGrid,MissionCameraHorizon,MissionCameraRings,MissionGhostRings — GymLock · mission screens
GymLock/Views/Morning/Missions/Screens/MissionChrome.swift [335] MissionMetrics,MissionPalette,MissionPressStyle,MissionPressBody,MissionShutterStyle,+View… — GymLock · mission screens
GymLock/Views/Morning/Missions/Screens/MissionCopy.swift [89] MissionCopy — GymLock · mission screens
GymLock/Views/Morning/Missions/Screens/MissionHeroCard.swift [78] MissionHeroCard — GymLock · mission screens
GymLock/Views/Morning/Missions/Screens/MissionLightStages.swift [281] MissionBackRow,MissionNoticeBlock,MissionStepsStage,MissionSpeechStage — GymLock · mission screens
GymLock/Views/Morning/Missions/Screens/MissionSwapSheet.swift [117] MissionSwapSheet — GymLock · mission screens
GymLock/Views/Morning/MomentumSavedView.swift [266] MomentumSavedView,MomentumSparkline — The result screen after a home fallback.
GymLock/Views/Morning/MorningAlarmPlanView.swift [388] MorningAlarmPlanView — One overview of the next morning: when the alarm rings, what happens after
GymLock/Views/Morning/MorningFlowView.swift [283] MorningFlowView — The router for a live morning.
GymLock/Views/Morning/MorningKit.swift [397] MorningHeader,HaloedGlyph,SparkMark,StatusPill,MorningPrimaryButton,MorningPrimaryStyle… — The small wordmark that sits at the top of every morning screen, with an
GymLock/Views/Morning/MorningSetupFlowView.swift [123] MorningSetupFlowView,Step — The one-time setup that runs after activation.
GymLock/Views/Morning/PlansChanged/Day0PauseStage.swift [1544] Day0PauseStage,Day0PauseWave,Day0PauseChipSpec,Day0PauseLowerThird,Day0PauseBeat,Kind… — Day0PauseStage.swift
GymLock/Views/Morning/PlansChanged/MatrixPrinterPauseStage.swift [1539] MatrixPrinterPauseStage,Day,Row,Door,Part,MPPCache… — GymLock · the "plans changed" pause · Matrix printer look
GymLock/Views/Morning/PlansChanged/PauseFacts.swift [174] PauseWeekDay,State,PauseFacts,Context,PauseFactsProvider — GymLock · the "plans changed" pause
GymLock/Views/Morning/PlansChanged/PauseHaptics.swift [85] PauseHaptics,Kind — GymLock · the "plans changed" pause
GymLock/Views/Morning/PlansChanged/PauseScript.swift [247] PauseLine,Kind,PauseChoice,Key,PauseReceiptRow,PauseScript… — GymLock · the "plans changed" pause
GymLock/Views/Morning/PlansChanged/PrinterDotFont.swift [176]  — GymLock · the "plans changed" pause · Matrix printer look
GymLock/Views/Morning/PlansChanged/RidgePauseStage.swift [898] RidgePauseMath,RidgeCamState,RidgePauseGeo,RidgePausePath,RidgePauseShapes,RidgePauseFrame… — GymLock · the "plans changed" pause · Ridge look
GymLock/Views/Morning/PlansChangedView.swift [472] PauseSeenLedger,PlansChangedView,PauseLook,PauseModel,PausePhase,PauseLayout… — Whether this morning's session has already sat through the full 30-second pause, so a late
GymLock/Views/Morning/RhythmDial.swift [505] RhythmDial,Handle,MinuteDial,CountdownRing — The 24-hour sleep dial: a moon at bedtime, a sun at wake time, and a coral
GymLock/Views/Morning/SleepWakeRhythmView.swift [412] SleepWakeRhythmView,TimeField,PresetChips,TimePickerSheet — Sets the window that gets the user from bed to moving.
GymLock/Views/Morning/SongTrimmerView.swift [1118] SongTrimmerView,Presentation,PreviewSweep,TrimmerGlass,+View,TrimmerPressStyle… — Picks a track and chooses the 28 seconds of it that will wake the user.
GymLock/Views/Morning/StillGettingReadyView.swift [147] StillGettingReadyView — The one nudge, shown at roughly three-quarters of the preparation window.
GymLock/Views/Morning/Trip/MatrixTripView.swift [1748] MatrixTripView,MatrixTripStyle,MatrixTripReveal,MatrixTripMeter,MatrixTripVerifyPanel,MatrixStreetField… — The Matrix style of the trip screen: a tilted 3D board of dots built from the
GymLock/Views/Morning/Trip/RidgeTripView.swift [1589] RidgeTripMath,RidgeTripLayout,RidgeTripSample,RidgeTripEffort,RidgeTripPose,RidgeTripTrail… — A live black and white map on top, an ink-wash Ridge band straddling the
GymLock/Views/Morning/Trip/TripConfetti.swift [142] TripConfetti,Look,Burst,Piece — The arrival confetti, shared by both trip styles.
GymLock/Views/Morning/Trip/TripModel.swift [291] TripModel,+TripModel — The live geometry of one trip to the gym: where the user is, the route Apple
GymLock/Views/Morning/Trip/TripSimulation.swift [148] TripSimulation — Drives the trip screen without anyone moving, for the Day Flow Simulator's
GymLock/Views/Morning/Trip/TripTypes.swift [167] TripPhase,TripFrame,TripActions,TripCopy,TripFormat,TripPrimaryButton… — Where the trip stands. Derived by `TripView` from the session's route, never stored.
GymLock/Views/Morning/Trip/TripView.swift [164] TripView — The trip to the gym, as one page.
GymLock/Views/Morning/WakeIntro/Core/WakeFactsProvider.swift [158] WakeFactsProvider,WakeShoeRotation — GymLock · the "I'm up" wake page
GymLock/Views/Morning/WakeIntro/Core/WakeHaptics.swift [139] WakeHaptics — GymLock · the "I'm up" wake page
GymLock/Views/Morning/WakeIntro/Core/WakeIntroView.swift [2270] WakeIntroView,WakeNow,WakeIntroEngine,WakeClock,WakeClocks,WakeMoment… — GymLock · the "I'm up" wake page (native port of web/morning2 stage.tsx, ui.tsx, settled.t
GymLock/Views/Morning/WakeIntro/Core/WakeStage.swift [513] WakeConcept,WakeBeatID,WakeBeat,WakeShoeArt,WakeMissionKind,WakeHapticKind… — GymLock · the "I'm up" wake page (native port of web/morning2)
GymLock/Views/Morning/WakeIntro/Integration/WakeIntroPresenter.swift [190] WakeIntroLedger,WakeIntroPresenter,Snapshot — GymLock · the "I'm up" wake page
GymLock/Views/Morning/WakeIntro/Matrix/MatrixWakeBoard.swift [280] MatrixWakePixels,MatrixWakeBoard,MXW,Icon,MatrixWakeLED,Pixel — GymLock · Wake intro, Matrix concepts (native port)
GymLock/Views/Morning/WakeIntro/Matrix/MatrixWakeChapters.swift [802] MatrixWakeGeo,MatrixWakeFacts,Mission,ShoeArt,MatrixWakeBeat,MatrixWakeTimeline… — GymLock · Wake intro, Matrix concepts (native port)
GymLock/Views/Morning/WakeIntro/Matrix/MatrixWakeEngine.swift [373] MatrixWakeJS,MatrixWakeHash,MatrixWakeTarget,MatrixWakeDealOptions,MatrixWakeParticle,MatrixWakeEngine… — GymLock · Wake intro, Matrix concepts (native port)
GymLock/Views/Morning/WakeIntro/Matrix/MatrixWakeStage.swift [824] MatrixWakeSim,MatrixWakeInk,MatrixWakeGrid,RGB,MatrixWakeStage,GridKey… — GymLock · Wake intro, Matrix concepts (native port)
GymLock/Views/Morning/WakeIntro/Ridge/RidgeWakeStage.swift [790] RidgeWakeStage,Metrics,RouteGeometry,StageGeometry,CardGeometry,Footsteps… — GymLock
GymLock/Views/Morning/WakeIntro/Ridge/RidgeWorld.swift [506] RidgeWorld — GymLock
GymLock/Views/Onboarding/CautionPage.swift [168] CautionPage,Force,SignImpact — Scene 8 — the gate. A quiet, honest filter before the commitment, and the one
GymLock/Views/Onboarding/ChartPage.swift [84] ChartPage — Scene 7 — the argument. Both curves leave the same point in week one, so the
GymLock/Views/Onboarding/ExcusesPage.swift [183] ExcusesPage — Scene 7 — the reasons. The artwork carries the scene; the page's one moving
GymLock/Views/Onboarding/GreetingPage.swift [47] GreetingPage — Scene 3 — the app proves it remembered the name, then names the real pattern.
GymLock/Views/Onboarding/GuiltPage.swift [50] GuiltPage — Scene 5 — the emotional cost. The artwork already carries the thoughts, so
GymLock/Views/Onboarding/Intro/GymLockIntroView.swift [179] GymLockIntroVariant,GymLockIntroView,GymLockIntroWebView,Coordinator,WeakScriptMessageHandler — GymLock
GymLock/Views/Onboarding/Intro/IntroHaptics.swift [186] IntroHaptics — GymLock
GymLock/Views/Onboarding/Intro/IntroTestPages.swift [66] IntroTestPages — GymLock
GymLock/Views/Onboarding/LogoSplashPage.swift [59] LogoSplashPage — Scene 1 — the logo introduction. The mark settles in first, the wordmark
GymLock/Views/Onboarding/LoopPage.swift [186] LoopPage — Scene 6 — the loop, and the centrepiece of the story.
GymLock/Views/Onboarding/NamePage.swift [135] NamePage — Scene 2 — "hi." lands alone, then the name question arrives beneath it.
GymLock/Views/Onboarding/OnboardingFlowView.swift [358] OnboardingFlowView,Scene — The onboarding story: thirty-one scenes on one continuous vertical scroll.
GymLock/Views/Onboarding/ProblemReelPage.swift [334] ProblemReelPage,ProblemWordWheel — Scene 4 — "Problem". The only scene in the story with no illustration: the
GymLock/Views/Onboarding/System/ActivationPage.swift [269] ActivationPage — System screen 22 — activation.
GymLock/Views/Onboarding/System/AlarmSoundPage.swift [241] AlarmSoundPage,Waveform — System screen 11 — the sound.
GymLock/Views/Onboarding/System/BuildingSystemPage.swift [204] BuildingSystemPage,Step — System screen 14 — assembling what the user just described.
GymLock/Views/Onboarding/System/ComebackModePage.swift [166] ComebackModePage — System screen 13 — what happens after a miss.
GymLock/Views/Onboarding/System/CommitmentPage.swift [77] CommitmentPage — System screen 1 — the handshake.
GymLock/Views/Onboarding/System/DayZeroPage.swift [183] DayZeroPage — System screen 2 — Day 0.
GymLock/Views/Onboarding/System/DistractingAppsPage.swift [118] DistractingAppsPage — System screen 8 — what takes the time instead.
GymLock/Views/Onboarding/System/FailureReasonsPage.swift [61] FailureReasonsPage — System screen 7 — what actually wins.
GymLock/Views/Onboarding/System/FailureTimePage.swift [48] FailureTimePage — System screen 6 — the exact moment.
GymLock/Views/Onboarding/System/FailureWindowPage.swift [68] FailureWindowPage — System screen 5 — where the plan breaks.
GymLock/Views/Onboarding/System/FinalCommitmentPage.swift [138] FinalCommitmentPage — System screen 21 — the last look before switching it on.
GymLock/Views/Onboarding/System/FirstWeekPage.swift [150] FirstWeekPage,Beat — System screen 20 — what the first week actually looks like.
GymLock/Views/Onboarding/System/FrequencyPages.swift [136] TargetFrequencyPage,CurrentFrequencyPage,+Comparable — System screen 3 — the target.
GymLock/Views/Onboarding/System/GravityPage.swift [248] GravityPage — System screen 15 — what the gap actually costs.
GymLock/Views/Onboarding/System/InterventionTimelinePage.swift [164] InterventionTimelinePage,Moment — System screen 16 — where GymLock steps in.
GymLock/Views/Onboarding/System/LockedStatePage.swift [156] LockedStatePage — System screen 18 — the lock, demonstrated.
GymLock/Views/Onboarding/System/MechanismsPage.swift [111] MechanismsPage,Mechanism — System screen 12 — how the loop actually gets broken.
GymLock/Views/Onboarding/System/NightLoopPage.swift [123] NightLoopPage — System screen 9, the night half of the loop.
GymLock/Views/Onboarding/System/PersistentAlarmPage.swift [191] PersistentAlarmPage — System screen 10 — the alarm, framed as a mechanism rather than a setting.
GymLock/Views/Onboarding/System/SystemSummaryPage.swift [183] SystemSummaryPage,Line — System screen 17 — the whole thing, on one card.
GymLock/Views/Onboarding/System/UnlockedStatePage.swift [129] UnlockedStatePage — System screen 19 — the unlock, demonstrated.
GymLock/Views/Progress/BadgeEmblem.swift [156] BadgeEmblem,SheenPhase,LatestBadgeEmblem — The badges emblem: the GymLock mark cast as brushed metal.
GymLock/Views/Progress/Badges/BadgeArt.swift [90] BadgeImages,BadgeLockedFilter,BadgeArtView,GymLockFonts — GymLock — Badges
GymLock/Views/Progress/Badges/BadgeCardView.swift [234] BadgePalette,+Color,BadgeSlotFramesKey,BadgeCardView,BadgePressStyle,LockGlyph… — GymLock — Badges
GymLock/Views/Progress/Badges/BadgeCatalog.swift [134] BadgeTier,BadgeGroup,BadgeDefinition,BadgeCatalog — GymLock — Badges
GymLock/Views/Progress/Badges/BadgeCopy.swift [100] BadgeCopy — Every string the badges screens show or speak, in one place. Only words:
GymLock/Views/Progress/Badges/BadgeGalleryView.swift [145] BadgeGalleryView,+BadgeGalleryView — GymLock — Badges
GymLock/Views/Progress/Badges/BadgeHaptics.swift [129] BadgeHaptics — GymLock — Badges
GymLock/Views/Progress/Badges/BadgeRankUpPresenter.swift [133] BadgeRankUpRequest,+View,BadgeRankUpPresenter,Flight,BadgeFlightView — GymLock — Badges
GymLock/Views/Progress/Badges/BadgesScreen.swift [250] BadgesScreen,BadgeDetailSheet — The Badges screen, opened from the Progress tile.
GymLock/Views/Progress/Badges/RankUpView.swift [591] RankUpTiming,RemotionRandom,RankUpLayout,RankUpView,RankUpRenderer,RankUpSymbol… — GymLock — Badges
GymLock/Views/Progress/CardPressTracker.swift [61] CardPressTracker,Coordinator — Reports a finger resting on a card, without taking the touch from
GymLock/Views/Progress/FlameEmblem.swift [72] FlameEmblem,+View — The streak emblem: a flame with a few sparks around it, as it appears on the
GymLock/Views/Progress/HallOfFame/FilmStripView.swift [995] HallOfFameStyle,FilmStripView,StripLayout,Kind,Item,FilmSnapBehavior… — Fixed film constants shared by the strip (and the reel, via the contract).
GymLock/Views/Progress/HallOfFame/HallOfFameDismiss.swift [141] HallOfFameDismissModel,HallOfFameZoomStage,HallOfFamePageZoom,Pose — Live state of a drag-to-close and the zoom into the card. Kept outside
GymLock/Views/Progress/HallOfFame/HallOfFameHaptics.swift [106] HallOfFameHaptics — The Hall of Fame's haptic cues, one call per event.
GymLock/Views/Progress/HallOfFame/HallOfFameModel.swift [523] Content,Marker — How closely the Hall of Fame is zoomed in, from one photo to a month grid.
GymLock/Views/Progress/HallOfFame/HallOfFameTitle.swift [230] HallOfFameTitle,TitleGeometry,WipeMask,TitleDot,TitleDots,TitleDotsCanvas — "Hall of Fame": 40 pt heavy big, then a glide to the small top-middle title.
GymLock/Views/Progress/HallOfFame/HallOfFameView.swift [737] HallOfFameView,Phase,HallOfFameSettings — The Hall of Fame: a full-screen film strip of every progress photo, with a
GymLock/Views/Progress/HallOfFame/ReelCanvas.swift [728] ReelCanvas — Draws the reel (2D roll-in reel, its trailing tail, the 3D reel, the floor shadow) for a t
GymLock/Views/Progress/HallOfFame/ReelScene.swift [282]  — Intro timeline in seconds from open. Values copied from src.html
GymLock/Views/Progress/ProgressChartColumns.swift [195] ProgressMonthWeekColumn,ProgressWeekDayColumn — One week of the month, drawn as a stack of physical cards.
GymLock/Views/Progress/ProgressChartKit.swift [434] ProgressPalette,ProgressLayerKind,ProgressLayer,+ProgressTally,ProgressLayeredBar,BackCard… — The four marks the progress charts are allowed to draw.
GymLock/Views/Progress/ProgressCompletionRing.swift [97] ProgressCompletionRing — The completion dial: one continuous orange arc for what was completed, one
GymLock/Views/Progress/ProgressPeriodCard.swift [431] ProgressCardMetrics,ProgressPeriodCard,CardArrow,CardArrowStyle — Shared geometry for the period card.
GymLock/Views/Progress/ProgressPeriodPreviews.swift [321] ProgressPreviewData,ProgressPreviewStage — Fixtures for the period card.
GymLock/Views/Progress/ProgressPhotoAddButton.swift [178] ProgressPhotoSourceChoice,ProgressPhotoAddButton,RootTabBarMinYKey,+EnvironmentValues,+View,BubbleButtonStyle — Which source the user picked from the Add Photo menu.
GymLock/Views/Progress/ProgressPhotoCaptureSheet.swift [366] ProgressPhotoCaptureSheet,Phase — Full-screen viewfinder for a progress photo, with the system camera's own
GymLock/Views/Progress/ProgressPhotoCard.swift [167] ProgressPhotoMetrics,ProgressPhotoCard,MarkerChip — Shared geometry for the photo stack, so the card and the stack cannot drift
GymLock/Views/Progress/ProgressPhotoPicker.swift [328] PendingReview,ProgressPhotoImporter,+View,ProgressPhotoCameraAvailability — An imported image waiting on the review screen.
GymLock/Views/Progress/ProgressPhotoPreviews.swift [347] PhotoFixture,StackStage,RevealStage — Previews for the Progress Photos card.
GymLock/Views/Progress/ProgressPhotoReplaceSheet.swift [354] ProgressPhotoReplaceSheet,PaneState,+View — The side-by-side comparison shown before a photo is replaced.
GymLock/Views/Progress/ProgressPhotoReviewView.swift [199] ProgressPhotoIntent,ProgressPhotoReviewView,ViewfinderCloseButton,ViewfinderGlass,+View — What the user wants done with a photo they have just approved.
GymLock/Views/Progress/ProgressPhotoStack.swift [778] ProgressPhotoStack,ProgressPhotoLayout,CardGeometry,+View,PhotoAccessibilityActions,+CGFloat… — The overlapping stack of progress photographs.
GymLock/Views/Progress/ProgressPhotosCard.swift [408] ProgressPhotosCard — The Progress Photos card.
GymLock/Views/Progress/ProgressSpotlightHeadline.swift [186] ProgressSpotlightHeadline,Pose — "Share your progress 🔥", the spotlight's one line.
GymLock/Views/Progress/ProgressStatCard.swift [150] ProgressStatCard,DigitStyle,PressableTileStyle — One stat tile at the top of Progress: an emblem with the count stamped onto
GymLock/Views/Progress/ProgressTabView.swift [316] ProgressTabView,SpotlightTravel — The Progress tab.
GymLock/Views/Progress/SpotlightDim.swift [35] SpotlightDim,+View — The Progress spotlight's dimming, applied by each surface to itself.
GymLock/Views/ScheduleSetupView.swift [189] ScheduleSetupView — The commitment screen reached from "let's lock it in": the user sets the two
GymLock/Views/Share/AllFramesSheet.swift [206] AllFramesSheet,Filter,ConditionalLock — The full frame gallery, over the editor.
GymLock/Views/Share/Frames/CleanFrame.swift [21] CleanFrame — The photo and the mark. Nothing else.
GymLock/Views/Share/Frames/ComebackFrame.swift [43] ComebackFrame — `CAME BACK.` — matter-of-fact, no pep talk.
GymLock/Views/Share/Frames/JourneyFrame.swift [89] JourneyFrame — `DAY 30`, with what the days added up to.
GymLock/Views/Share/Frames/MilestoneFrame.swift [71] MilestoneFrame — A threshold, on the day it was crossed.
GymLock/Views/Share/Frames/MomentumFrame.swift [95] MomentumFrame,StoryCountingText — The streak, as one large number.
GymLock/Views/Share/Frames/QuickSaveFrame.swift [41] QuickSaveFrame — The home fallback, said plainly.
GymLock/Views/Share/Frames/ReceiptFrame.swift [113] ReceiptFrame,Row — The morning as a ticket.
GymLock/Views/Share/Frames/ShowedUpFrame.swift [78] ShowedUpFrame — `SHOWED UP.` — the coral full stop is the frame's one accent.
GymLock/Views/Share/StoryCanvasView.swift [128] StoryCanvasView,Layers — The frame, drawn. One view for the preview and for the export.
GymLock/Views/Share/StoryEditableCanvas.swift [457] StoryEditableCanvas — The canvas as the editor shows it: the photo, the current frame's
GymLock/Views/Share/StoryEditorChrome.swift [477] EditorGlass,+View,EditorCloseButton,GlassSegmentedControl,FormatToggle,FramePreviewRail… — The controls that float over the editor: close, the format toggle, the
GymLock/Views/Share/StoryEditorView.swift [288] StoryEditorView,ShareFile,ActivityShareSheet,StoryEditorPresenter,ZoomFromCard,+View — The Story editor.
GymLock/Views/Share/StoryFixtures.swift [234] StoryFixtures,FixtureEditor,FixtureCanvas — Preview fixtures for every frame state.
GymLock/Views/Share/StoryMarkView.swift [26] StoryMarkView — The one piece of branding on a frame.
GymLock/Views/Share/StoryPhotoLayer.swift [73] StoryPhotoLayer,StoryLegibilityBand — The photograph, aspect-filled and cropped by the transform — or, with no
GymLock/Views/Share/StoryTypography.swift [133] StoryTypography,StoryStatementText,StoryFactsText,StoryEyebrowText — The type roles a frame may use, and nothing else.
GymLockNightMonitor/GymLockNightMonitorExtension.swift [110] GymLockNightMonitorExtension
GymLockShieldAction/GymLockShieldActionExtension.swift [28] GymLockShieldActionExtension
GymLockShieldConfig/GymLockShieldConfigExtension.swift [56] GymLockShieldConfigExtension
GymLockTests/AlarmDeliveryTests.swift [261] AlarmDeliveryTests,RecordingAlarmScheduler — The custom song reaching the system alarm, and the app never ringing it
GymLockTests/AlarmHandoffTests.swift [81] AlarmHandoffTests — The note the alarm leaves for the app.
GymLockTests/AlarmOptionsTests.swift [106] AlarmOptionsTests — The Alarm screen's options card: snooze on/off, snooze length, haptics,
GymLockTests/AlarmRulesTests.swift [616] AlarmRulesTests — `docs/FLOW.md`, "Everything to Change" items 5 to 9: the flow is chosen by
GymLockTests/AlarmScreenStyleTests.swift [97] AlarmScreenStyleTests — The alarm screen choice: its default, the migration of older plans, and
GymLockTests/AlarmSoundTests.swift [234] AlarmSoundTests — The sound rules: which file each player gets, and what rings when the
GymLockTests/BadgeEngineTests.swift [222] BadgeEngineTests — The badges, pinned: every unlock is derived from the ledger and
GymLockTests/DayDialTests.swift [1035] DayDialTests — The Day Dial's maths.
GymLockTests/DebugScenarioLibraryTests.swift [289] DebugScenarioLibraryTests,Recorder — Parity between the Day Flow Simulator and every `DebugStep`. If a new step
GymLockTests/FrameAvailabilityTests.swift [194] FrameAvailabilityTests — Locked versus not-today, for every frame.
GymLockTests/FreezeAndRiskTests.swift [509] FreezeAndRiskTests — `docs/FLOW.md`, "Everything to Change" items 21 and 22: freezes on a
GymLockTests/GymLockTests.swift [18] GymLockTests — GymLockTests
GymLockTests/GymVisitTests.swift [452] GymVisitTests — `docs/FLOW.md`, Flow 3 and "Goes to the gym in sleep hours anyway": when a
GymLockTests/HallOfFameModelTests.swift [304] HallOfFameModelTests — Fixed calendar (Gregorian, UTC, weeks start Monday) so no result depends on
GymLockTests/LaunchCoverTests.swift [108] LaunchCoverTests
GymLockTests/MatrixParityTests.swift [32] MatrixParityTests — The Matrix port against the TypeScript golden values.
GymLockTests/MatrixWakeParityTests.swift [12] MatrixWakeParityTests — The wake page's Matrix renderer against the web prototype's golden values
GymLockTests/MomentumFieldTests.swift [188] MomentumFieldTests — The Momentum card counts what the streak counts (FLOW, item 19a): distinct
GymLockTests/NotificationRouteTests.swift [235] NotificationRouteTests — `docs/FLOW.md`, item 12: only alarm notifications may start a session.
GymLockTests/PauseScriptTests.swift [95] PauseScriptTests — The "plans changed" pause: the copy, its timing, the doors, and when the day 0 page plays.
GymLockTests/ProgressPhotoSelectionTests.swift [212] ProgressPhotoSelectionTests — Tests for the two pieces of the Progress Photos card that are pure logic and
GymLockTests/ProgressSpotlightTests.swift [233] ProgressSpotlightTests — `docs/FLOW.md`, Flow 3, "The Progress spotlight": only the workout-done
GymLockTests/ReelSceneTests.swift [61] ReelSceneTests
GymLockTests/SessionResumeTests.swift [329] SessionResumeTests — The matrix that decides whether people get ambushed.
GymLockTests/SessionVoiceTests.swift [200] SessionVoiceTests,SnoozeStateTests — The daypart voice and the single-snooze rule, pinned.
GymLockTests/ShareContextBuilderTests.swift [197] ShareContextBuilderTests — How the context's fields are derived from the record.
GymLockTests/ShareFrameAvailabilityTests.swift [139] ShareFrameAvailabilityTests — Which frames are offered for which situation.
GymLockTests/SkipRulesTests.swift [594] SkipRulesTests — `docs/FLOW.md`, Flow 4 and its edge cases: the one skip screen, real
GymLockTests/SleepRulesTests.swift [380] SleepRulesTests — `docs/FLOW.md` items 1 (without the background extension), 2 and the
GymLockTests/SleepScheduleTests.swift [339] SleepScheduleTests — The Alarm screen's dial context and the contextual day card: which arc
GymLockTests/SongTrimFlowTests.swift [343] SongTrimFlowTests,ScopeLog — The "your song" flow: importing a file reliably, the fixed 28-second
GymLockTests/StoryLayoutTests.swift [139] StoryLayoutTests — The canvas arithmetic: normalized → actual, safe insets, element clamps,
GymLockTests/StoryRendererTests.swift [141] StoryRendererTests — The export: exact pixels, no metadata, settled state, a real sticker.
GymLockTests/StreakCelebrationTests.swift [264] StreakCelebrationTests — When the streak card is allowed to open on its own.
GymLockTests/StreakEngineTests.swift [404] StreakEngineTests — The streak rules, pinned.
GymLockTests/SystemAlarmHandoffTests.swift [302] SystemAlarmHandoffTests,Harness — `docs/FLOW.md`, Flow 1: the system alarm's "I'm up" is the commitment,
GymLockTests/ThemeRotationTests.swift [188] ThemeRotationTests — The pure theme rotation and position rules (02-experience-spec §1.4–§1.6).
GymLockTests/TimeToGymTests.swift [298] TimeToGymTests — The unified Time to Gym: one duration from the alarm to the gym, the
GymLockTests/WeekRulesTests.swift [431] WeekRulesTests — `docs/FLOW.md` items 18, 19, 19a, the first half of 20 and the 3-day half
GymLockTests/WindDownWindowTests.swift [220] WindDownWindowTests — The wind-down lock's clock maths and its ownership rules.
GymLockUITests/GymLockUITests.swift [42] GymLockUITests — GymLockUITests
GymLockUITests/GymLockUITestsLaunchTests.swift [34] GymLockUITestsLaunchTests — GymLockUITests
ScreenTimeShared/GymLockFamilySelection.swift [42] GymLockFamilySelection
ScreenTimeShared/GymLockScreenTimeShared.swift [92] GymLockScreenTime,ShieldOwner,ShieldLedger,CodingKeys,ShieldLedgerStore
