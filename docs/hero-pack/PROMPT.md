# GymLock: native Dynamic hero card (Ridge + Matrix), done flow, haptics, style selector

You are working in the GymLock repo (native SwiftUI, iOS 18). Read `CLAUDE.md`, `docs/FLOW.md` and `docs/UI-RULES.md` first, then this pack in order:

1. `docs/01-current-app-map.md`: how the app works today, which files to touch, and the 19-moment resolver.
2. `docs/02-experience-spec.md`: theme rotation, moment exposure, celebration queue with badges, done-flow timing, card motion, haptics map, style selector, acceptance checklist.
3. `swift/`: the native engine reference (Matrix particle engine, board API, scene protocol, card view, done-flow view, haptic scheduler), plus `swift/PORTING-GUIDE.md` and `swift/RIDGE-PORT.md`.
4. `web-reference/`: the approved prototype, as source code and a working build. Open `web-reference/GymLock-HeroCard-Worlds-Dynamic.html` in Safari to see every moment, day, style and the done flow. Use the panel to switch them. **Dynamic mode is the only mode to ship.** Ignore "Classic".

## Goal

Replace the home hero card with the approved **Dynamic** hero card in two user-selectable styles, **Ridge** (painterly landscape) and **Matrix** (dot-matrix board). Add the full-screen **done flow** after a verified workout. Port everything natively so it renders **identically on every iPhone**: fixed design space, uniform scale, deterministic maths, and time-based motion at 60, 120 or 30 Hz. Wire it to real app state, haptics and badges.

## Owner-approved rule changes (Rishi, the owner, approved these; apply them)

Update `docs/UI-RULES.md` and `docs/FLOW.md` with a short "Approved exception" note for each, then build to them:

1. **Hero card, done flow and style preview are never static.** Each has an entrance, one beat and a calm idle loop, as in `02-experience-spec.md` §5. This is an exception to "Nothing loops", for these surfaces only. Under Reduce Motion, keep a slow opacity breathe and drop positional motion.
2. **The done flow plays after a verified workout.** It runs before the Progress spotlight when the workout-done notification is tapped, and lands on the spotlight afterwards (spec §4, C2).
3. **Ridge's painterly gradients, washes and glow are allowed inside the hero card and Ridge done flow only.**
4. **Done-flow and celebration durations may exceed the 300 ms cap**, under the existing celebratory exception.
5. **Week position** (first/middle/last) and **taps** (5, or 7) come from real sessions against the user's weekly goal (3 to 7), never from the weekday.

Keep all other FLOW.md behavior exactly. If something else conflicts, stop and ask.

## What to build (in this order; commit after each step and keep the app building)

1. **Engine (Matrix).** Add `swift/MatrixEngine.swift`, `MatrixBoard.swift`, `MatrixScene.swift`, `MatrixCardView.swift` and `HeroHaptics.swift` under `Views/Home/Hero/Matrix/`. Keep the maths identical to the TS: same hash, same push order, same ids, fixed 1/120 s physics substeps. Add a debug screen that renders any moment, theme and time, so it can be compared with the web build.
2. **Port all 133 Matrix scenes**: 19 moments × 7 themes, from `web-reference/hero13/mx/*.ts`, one Swift file per moment, mechanically, following `PORTING-GUIDE.md`. Do not redesign them. Compare each against the web build at T = 0.5, 1.5 and 4 s in light and dark.
3. **Matrix done flow.** Port `web-reference/hero13/mxstory.ts` and `story13m.tsx` into `MatrixStoryView`: the screens verified, today, week, month, far, climax and count, the taps and the seal timing.
4. **Ridge.** Follow `RIDGE-PORT.md`. Port the painter stack, props, camera and done flow (`hero13/card13.tsx`, `stage13.ts`, `props13.ts`, `hero10/wash*.ts`, `hero12/wash3.ts`, `hero12/story12.tsx` with `dyn`). Cache static layers per size, and keep the same per-moment, per-theme scenes.
5. **State wiring.** Replace `HeroStage`/`HomeCardDeriver.cardSection` with the 19-moment resolver from `01-current-app-map.md`, fed by real data. Add the small data additions it lists, such as evening time left, session minutes and the shown-once keys. Port the copy from `web-reference/hero12/copy12.ts` and `hero11/copy11.ts`, but:
   - strip placeholder data (gym name, times, "5 of 5", "Week 8") and use real values
   - remove invented statistics
   - use no em dashes, sentence case and Monday-first weeks
   - make weekday-specific lines follow the real weekday, and object lines follow the theme (spec §1).

   Keep `HeroMetrics`, `MiniCardsRow` and `MomentumSection`.
6. **Theme rotation** (spec §1). One theme per calendar day, with the day turning over at 04:00, persisted. Training days cycle through all 7 done objects across the user's real sessions, so a 3-day-a-week user still meets every theme. Rest days take the theme seen least recently. Include the unit test that reproduces the spec's §1.6 table.
7. **Done flow presentation** (spec §4). Present it as a full-screen cover from `RootTabView`:
   - 1300 ms after the 20:00 proof when the card is visible
   - 700 ms after Home appears otherwise
   - 300 ms after a notification tap.

   Never interrupt another tab, sheet or the camera. Screens never auto-advance. Close is an X or a swipe down. The flow expires at the end of the day and resumes at the climax after backgrounding. The hero card must show the **same finished object** as the flow's climax for that theme.
8. **Celebration queue** (spec §3). One persisted queue for the done flow, badge rank-ups, the streak-card weekly celebration, week kept, and the halfway and day-66 milestones. At most one full-screen sequence per app open. Up to 2 rank-ups earned by this session play as the last steps of the done flow; the rest go quiet. Suspend `StreakIntroController`, and the success haptics in `MomentumFlameProgress` and `TodayHomeView`, while a celebration is up, so nothing double-fires off the same `store.log` write.
9. **Haptics** (spec §6). Use one `HeroHaptics` scheduler that fires each scene's `hap` list on the same frame as the visual, with `prepare()` ahead of time. Cover the alarm rings, the last 10 s of the countdown, the 20:00 proof, every done-flow beat, each climax tap, the seal, the count and rank-ups. Respect the in-app Haptics toggle, avoid firing during the alarm's own vibration, and rate-limit. Merge `BadgeHaptics` and the other engines onto it where the spec says.
10. **Style selector** (spec §7). In Profile → Preferences add a "Card style" section with a live full-width preview of today's real card and a Ridge / Matrix segmented picker. Follow the `AlarmScreenStyle` pattern and save to the `UserDefaults` key `gymlock.home.cardStyle`. Ridge is the default. Switching cross-fades the card, and a running done flow never changes style.
11. **Motion and performance** (spec §5).
    - Drive everything with `TimelineView(.animation)` and elapsed time.
    - Pause when off-screen or inactive.
    - Run at 120 Hz on ProMotion, cap at 30 Hz in Low Power Mode or thermal pressure, and keep the same timing at every rate.
    - Draw the static grid and Ridge layers once and cache them.
    - Use no bundled fonts: use the system font (SF Pro Rounded for Matrix headlines and SF Mono-style digits for clocks, as in the prototype).

## Technical notes from the engine port

- **120 Hz:** add `CADisableMinimumFrameDurationOnPhone = YES` to Info.plist, or ProMotion iPhones run at 60 Hz.
- **Card aspect:** use the exact design ratio 1000:488 for the hero card, not 2.05, so nothing letterboxes.
- **Self-tests:** run the DEBUG self-tests `MatrixParity.run()` and `MatrixParity.runStory()` first. The golden values come from the TS. Fix any mismatch before porting scenes. Add golden values as you port, using `swift/tools/matrix-golden.ts`.
- **Ridge note:** it uses a handwriting web font. Replace it with a system font (no bundled fonts). Paper grain, glow and mist loops are allowed under approved exceptions 1 and 3.
- **Haptics fallback:** if a Matrix scene has no `hap` list, use the per-moment default in `web-reference/hero13/props13.ts` (`HAP_DEF`/`hapFor`). Port that table into `HeroHaptics`.
- **Finger drag:** dragging on the Matrix dots stays off; scrolling has priority.
- **Copy style:** sentence case and straight apostrophes, matching UI-RULES.

## Acceptance

- Every item in `02-experience-spec.md` §8 passes.
- For each moment and theme, the native card matches the web build side by side at T = 0.5, 1.5 and 4 s, on iPhone SE, 15 and 16 Pro Max (same composition, scaled), in light and dark.
- A Mon/Wed/Fri test user sees all 7 done objects within 7 sessions.
- No celebration overlaps another, and no haptic fires twice for one event.
- The build is clean, existing tests pass, and the new tests cover the resolver, the rotation and the queue.

Work in small steps, report what you changed after each step, and ask before deviating from FLOW.md beyond the approved exceptions above.
