# Wake page ("I'm up") integration

The native port of the approved `web/morning2` prototype. Drop the folder in, make the 2 required edits below and add 1 Info.plist key. Nothing else in the app changes.

## 1. Files

The app target uses synchronized folders, so copying the folder into `ios-gymlock/GymLock/Views/Morning/WakeIntro/` adds every file to the target. You do not need to touch the project file.

| File | What it is |
| --- | --- |
| `Core/WakeStage.swift` | The contract with the two renderers, the plan (port of `plan.ts buildPlan`), easing, facts normalisation and copy (port of `model.ts`), `WakeLayout`, the optional `WakeStageAnchoring`, and `WakeStageFactory` |
| `Core/WakeFactsProvider.swift` | Builds `WakeFacts` from the live app state, picks the concept |
| `Core/WakeHaptics.swift` | Plays the plan's haptics on the same clock as the visuals |
| `Core/WakeIntroView.swift` | The page: the stage, chapter words, the condense into the card, the settled page, the idle loop |
| `Integration/WakeIntroPresenter.swift` | Decides when the page plays (once per session) and wires its buttons |
| `Matrix/…` `MatrixWakeStage` and `Ridge/…` `RidgeWakeStage` | The renderers, from the other two engineers |
| `GymLock/Assets.xcassets/WakeRidge/` | The baked Ridge layers (`ridgeWorld*`, `ridgeCard*`). Copy the `WakeRidge` folder into the app's existing `GymLock/Assets.xcassets/`; the group is not namespaced, so `UIImage(named:)` finds them by plain name |
| `GymLock/Resources/WakeRidgeWorld.json` | The Ridge world geometry, read with `Bundle.main.url(forResource:)`. Copy it into `GymLock/Resources/` (synchronized folder, so it joins the Copy Bundle Resources phase on its own) |
| `tools/` | Bake and golden-test scripts for the two renderers. Not part of the app target; leave outside `GymLock/` |

## 2. Required edit: the mission screen

File: `ios-gymlock/GymLock/Views/Morning/ActivationMissionView.swift`, in `body`, between `.task { … }` and `.fullScreenCover(isPresented: $isRunning)`.

Before:

```swift
        .task {
            camera.refreshAvailability()
            motion.refreshAvailability()
            await speech.refreshAvailability()
        }
        .fullScreenCover(isPresented: $isRunning) {
            MissionRunnerView(
```

After:

```swift
        .task {
            camera.refreshAvailability()
            motion.refreshAvailability()
            await speech.refreshAvailability()
        }
        // The "I'm up" wake page: once per session, over this screen's first frame.
        // Its mission capsule starts the mission exactly as the card's "start" does.
        .overlay {
            WakeIntroPresenter(session: session, route: .mission) {
                isRunning = true
            }
        }
        .fullScreenCover(isPresented: $isRunning) {
            MissionRunnerView(
```

## 3. Required edit: the countdown screen (missions turned off)

File: `ios-gymlock/GymLock/Views/Morning/GymWindowView.swift`, at the end of `body`.

Before:

```swift
    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                MorningHeader(trailingTitle: "End", trailingAction: onEnd)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    content(at: context.date)
                }
            }
        }
    }
```

After:

```swift
    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                MorningHeader(trailingTitle: "End", trailingAction: onEnd)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    content(at: context.date)
                }
            }
        }
        // The "I'm up" wake page when missions are off: once per session, over the countdown's
        // first frame. Its capsule ("Shoes on") closes it onto the countdown.
        .overlay {
            WakeIntroPresenter(session: session, route: .countdown)
        }
    }
```

This screen also opens after a mission. The page does not play again there: the session is already marked as played.

## 4. Required: 120 Hz

ProMotion iPhones cap `TimelineView` at 60 Hz unless the app opts in. The hero card needs the same key, so it may already be there.

The GymLock target generates its Info.plist (`GENERATE_INFOPLIST_FILE = YES`; only the three extensions have a plist file), and the project has no `CADisableMinimumFrameDurationOnPhone` entry today. Add it on the target's **Info** tab:

| Key | Type | Value |
| --- | --- | --- |
| `CADisableMinimumFrameDurationOnPhone` | Boolean | YES |

If Xcode does not take the key from the Info tab, add the build setting `INFOPLIST_KEY_CADisableMinimumFrameDurationOnPhone = YES` to the GymLock target (Xcode confirms that this generated-plist key is merged; not checked here, no Xcode available). Without the key the page still works, at 60 Hz.

## 5. Optional edit: the grace note on "Plans changed"

`PlansChangedView` ends with "choosing "still going" gives you 10 more minutes". That is true after the window has run out. From the wake page the window is still open, and "still going" only closes the sheet. Make the note optional so this page can hide it.

File: `ios-gymlock/GymLock/Views/Morning/PlansChangedView.swift`.

Before:

```swift
    let voice: SessionVoice
    let onStillGoing: () -> Void
    let onQuickWorkout: () -> Void
    let onCantToday: () -> Void
```

After:

```swift
    let voice: SessionVoice
    let onStillGoing: () -> Void
    let onQuickWorkout: () -> Void
    let onCantToday: () -> Void
    /// False when the window is still open (the wake page): "still going" spends no grace there.
    var showsGraceNote = true
```

Before:

```swift
                        Text("choosing \"still going\" gives you \(GymSession.graceMinutes) more minutes — not a new window.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.inkTertiary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
```

After:

```swift
                        if showsGraceNote {
                            Text("choosing \"still going\" gives you \(GymSession.graceMinutes) more minutes — not a new window.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.inkTertiary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
```

Then in `Integration/WakeIntroPresenter.swift`, pass the new argument:

```swift
                    onCantToday: {
                        isShowingPlansChanged = false
                        coordinator.beginCantToday()
                    },
                    showsGraceNote: false
                )
```

The existing call in `MorningFlowView` keeps the default, so nothing else changes.

## 6. When it plays

- **After "I'm up" commits.** `AlarmFiredView` calls `coordinator.commitToGoing()`. The session then goes to `.activationMission` (route `.mission`), or to `.preparing` (route `.countdown`) when `plan.missionsEnabled` is false. The page covers the first frame of that screen.
- **Once per session.** The page is marked played when it appears, under the UserDefaults key `gymlock.morning.wakeIntroPlayedSession` (the session's id). A kill or relaunch mid-intro never replays it. This uses a key instead of a new `GymSession.wakeIntroPlayedAt` field because `GymSessionCoordinator.session` is `private(set)`, and a new field would need a coordinator method too.
- **Only fresh.** It plays only within 5 minutes of `committedAt`, before the user has left (`departedAt == nil`). It never plays on the make-up skip offer (`isMakeUpOffer`).
- **Never on Go Later days.** It requires `session.resolvedFlowMode == .wakeAndGo`. On a Go Later day the morning has a plain wake alarm and the evening alarm says "I'm going".
- **Never a second "I'm up".** The page never calls `commitToGoing()`. Its actions are the mission, which is the same action as the mission card's "start", and "Plans changed".
- **The buttons.**
  - Mission capsule: fades the page away, then runs the screen's own action. On the mission screen that starts `MissionRunnerView`. On the countdown it closes the page onto the countdown.
  - "Plans changed": opens the existing `PlansChangedView` in a sheet. "quick workout instead" calls `coordinator.offerQuickWorkout()` and "can't today" calls `coordinator.beginCantToday()`. Both are the same calls `MorningFlowView` wires. "still going" closes the sheet.
- **Tap anywhere** during the intro settles the page at once. With VoiceOver on, the page starts settled.

## 7. Which concept

- **Ridge or Matrix**: follows the user's hero card style (`@AppStorage("gymlock.home.cardStyle")`, `HeroCardStyle`). Ridge is the default.
- **A (plan) or B (progress)**: A by default. B only for users past day 8 of their habit run (`HeroDayFacts.habitDay`), on alternate mornings: B when the habit day is even. That keeps the choice fixed for the whole day and makes it flip each day. First-time users always get A.

## 8. Where each fact comes from

| Fact | Source |
| --- | --- |
| name | `AppStore.userName`, only when `AppStore.hasName` |
| gym name | `AppStore.primaryGym?.name` |
| gym time | `session.deadline ?? session.arrivalTarget`, then `plan.rhythm(at:).gymByTime` |
| leave by | none (see 9.1). The copy says "Gym by 7:05." |
| mission | `session.mission` (assigned by `assignMission()` in `commitToGoing()`). Falls back to `.universalFallback` when missions are on, as `ActivationMissionView` does. When missions are off: "Shoes on" (RESEARCH §2.5) |
| steps | `ActivationMissionType.stepTarget` |
| week done / goal | `HeroDayFacts.weekCount` / `weekGoal` (`store.streak.thisWeekSessionDays` / `weeklyGoal`) |
| habit day | `HeroDayFacts.habitDay(_:)` (the hero card's day 1 to 66) |
| streak | `HeroDayFacts.streakWeeks` (`store.streak.weeks`) |
| first time | `HeroDayFacts.neverCounted` |
| comeback | `HeroMomentResolver.comebackLapse(_:cal:) != nil` (the hero card's rule) |
| snoozed | `session.hasSnoozed` |
| lock line | shown only when `coordinator.shield.hasSelection` |

All of these are read through `HeroMomentResolver.gather`, which only reads (`resolve` is the one that commits).

## 9. Known gaps and decisions to confirm

1. **No leave-by.** `MorningRhythm` keeps one Time to Gym, which covers getting ready and travel together. The session's old `travelMinutes` is private and nil on new sessions. So A concepts say "Gym by {time}." and the settled timeline drops its "Leave" row. Add a travel field or a MapKit ETA later and pass it as `WakeFacts.leaveBy`. The copy and the timeline pick it up with no other change.
2. **Mirror mission visual.** `mirrorBoost` has no matching visual, so it uses the shoe. The prototype's default does the same.
3. **Rules that need Rishi's sign-off** (RESEARCH §4.2, items 2, 3 and 5):
   - an intro of about 8 s, which exceeds the 300 ms limit in UI-RULES §5.3
   - an idle loop, which UI-RULES §5.7 forbids. §14 allows it only for the hero card.
   - sentence case on this page, where UI-RULES §1 and §11 ask for lowercase
   - an ink primary capsule instead of `MorningPrimaryButton`'s coral, so that coral appears only once on the page

   The brief asks for all four. Extending the §14 and FLOW "Approved exceptions" lists to cover "the wake page" would make them official.
4. **Dark appearance.** `ContentView` forces `.preferredColorScheme(.light)`, so the settled page is always the light look today. The dark look (`WakeLook.dark`) is built, but nothing reaches it until the app allows dark mode. One problem when it does: the real `StreakChip` draws its number in `Theme.ink`, which would be dark on dark.

## 10. Notes for the renderer engineers

- `draw` gets the full-screen Canvas context and size. `frame.stageRect` is already clipped (rounded), and the stage colour is filled behind it. Draw the visual only.
- Shared fit: `WakeLayout.fit(size)` returns `(scale, originX)` with `scale = min(width/390, height/844, 1.25)` and `originX = (width - 390 * scale) / 2`. Everything the owner wants identical on every device uses it: the words, the progress ticks, the card slot and buttons (the settled page is laid out in a 390-wide design column and scaled uniformly), the Matrix board (scale, top-aligned, x origin; the faint grid still fills the screen) and the labels. `designScale(size)` still exists and returns the same scale. Ridge's painting is aspect-fill and full-bleed; its anchors are Canvas coordinates of objects on the art, and its overlays use the fit. Renderers that map design points should use `fit.scale` and `fit.originX` at k = 0 (see `MatrixWakeStage.mapping`). Safe-area insets are screen points: divide by the scale inside the design column.
- `frame.dark` is the look to draw. The page passes `true` for the main pass, always, because the intro is dark. In light appearance it adds a second pass inside the card with `dark: false` (the day look: ink on `Theme.surface`) while the card wipes. A renderer can therefore be called twice in one frame with the same `t`, so stepping must be idempotent per `t`. After the wipe only the day pass is drawn.
- The page fills the stage background (`#0A0A0B` mixing to `#151517` / `#161618` as it condenses) and the card's hairline. It also handles the light card's surface, border and shadow.
- Labels that sit beside objects are drawn by the page. Matrix labels fall back to the prototype's board geometry (mx2.ts `NODES`, `TRACK`, `STEP_COUNTER` and so on, at 7.5 design units per cell). Ridge tags need positions only the renderer knows: the leave point, the gym, the summit. Conform `RidgeWakeStage` (and `MatrixWakeStage` if its camera moves the board) to `WakeStageAnchoring` to provide them. Without it, those three Ridge tags are left out rather than guessed.
- Do not read `WakeFacts.gymClock` / `leaveClock` per frame: each call asks the locale for its 12/24 hour format. Derive from `frame.facts` once and cache (the page itself formats them once, in `WakeClocks`).
- The renderer is created and called on the main actor (`WakeStageFactory` is `@MainActor`, the Canvas closure runs there). A renderer class may stay non-isolated, but it is never called from another thread.
- Easing helpers are namespaced, `WakeEase.cl/lerp/ez/ez5/eio/settle/spr/back/ramp`, to avoid colliding with `MX` and `RW`.

## 11. Test checklist

- Ridge A, Ridge B, Matrix A and Matrix B. Switch with `gymlock.home.cardStyle`. For B, use a habit day above 8 and even.
- A snoozed session: no greeting, shorter chapters, eyebrow "Same plan".
- Reduce Motion on: crossfades only, a single heavy haptic about 0.07 s in, about 3 s.
- Profile > Preferences > Card haptics off: no tap from the intro and none from the two buttons.
- VoiceOver on: starts settled, and every element is labelled.
- Tap during the intro: moves to the next chapter, like a story. A tap on the last chapter starts the page-into-card condense early, which then plays in full (taps during it are ignored). Jumped-over haptics do not fire.
- The app is light today, so every run exercises the wipe: the card goes from night to day once, with no flicker on the renderer's second pass.
- Background the app mid-intro and return: the page is settled.
- Missions off: the page plays over the countdown, and the capsule reads "Shoes on".
- Relaunch after it played: it does not replay.
- Go Later day: it never appears.
- iPhone SE (375x667), iPhone 15 (393x852), iPhone 16 Pro Max (440x956) and iPad (820x1180), plus the largest capped Dynamic Type: the settled page scrolls only if it must. On each, check that the words, the card slot, the mission capsule and "Plans changed" are inside the screen; that the page looks identical (SE and iPad letterbox the same 390 x 844 page in a centred column, iPad at 1.25x, background and stage full-bleed); that the Matrix dots and labels line up with the words; and that the Ridge tags sit on their objects.
