# GYMLOCK — UI, UX & MOTION RULES

**This file is a standing rule, not a suggestion. Read it before writing or changing any view, control, animation, gesture, or piece of user-facing copy. It overrides your defaults.**

GymLock is a **native SwiftUI iOS app** (deployment target iOS 18). Every rule here is written for SwiftUI. If you find yourself reaching for a web pattern — CSS transitions, Tailwind classes, `prefers-reduced-motion` media queries, GSAP, Framer Motion — you are in the wrong framework. Translate to the SwiftUI equivalent given below.

Craft principles in the Motion, Gesture and Anti-slop sections are adapted from Emil Kowalski's animation skills, Apple's *Designing Fluid Interfaces* (WWDC 2018), the taste-skill anti-slop rules, and Impeccable's design modes — all re-written for native SwiftUI.

---

## 0. The three questions before any UI work

1. **What mode is this screen in?**
   - **Operate** — the user is completing a task (Home, the morning flow, Progress). Scanability and consistency outrank expression. Most of GymLock is this.
   - **Experience** — the user is absorbed in content (the Story editor, the photo album). The artifact leads; the interface recedes.
   - GymLock has no *Persuade* or *Read* screens except onboarding. Do not design an Operate screen like a landing page.

2. **What is the one thing this screen is for?** If you cannot say it in one sentence, do not start.

3. **Does this change help the user, or does it just look busy?** Cards, borders, badges, eyebrows and animations all cost attention. Spend them deliberately.

---

## 1. Identity and voice

- **Semi-premium, editorial, quiet.** Warm off-white canvas, white cards with hairline borders, one coral accent, near-black ink. Nothing shouts.
- **One accent per screen, and it is coral.** Never two coral elements competing for the same glance.
- **Copy is lowercase and terse.** `you're here. 🔥` · `apps unlocked. go train.` · `stored only on this iPhone. never uploaded.` Short sentences, full stops, no exclamation marks in chrome. Public artifacts (share frames) may use uppercase statements; app chrome never does.
- **Honesty over fullness.** An empty state says what is true (`no plan yet`, `nothing due yet`). Never a placeholder number, never a fabricated stat, never a fake date.

---

## 2. Tokens — `Utilities/Theme.swift`

| Token | Value | Use |
|---|---|---|
| `Theme.canvas` | `rgb(0.980, 0.976, 0.965)` | App background, warm off-white |
| `Theme.surface` | white | Cards |
| `Theme.surfaceMuted` | `rgb(0.961, 0.953, 0.937)` | Inset rows, opaque fallbacks |
| `Theme.accent` | `rgb(0.910, 0.365, 0.306)` coral `#E85D4E` | **The** accent |
| `Theme.accentWarm` / `accentDeep` / `accentWash` | gradient ends, haloes | Never as a flat fill behind text |
| `Theme.ink` | `rgb(0.102, 0.102, 0.102)` | Primary text |
| `Theme.inkSecondary` | `0.42` grey | Supporting text |
| `Theme.inkTertiary` | `0.60` grey | Fine print, axis labels |
| `Theme.border` | `0.91` grey | 1 pt hairlines |
| `Theme.logoBackdrop` | `rgb(0.071, 0.071, 0.075)` | Dark surface behind the mark |
| `Theme.cardRadius` / `controlRadius` | 24 / 16 | Cards / controls |
| `Theme.pageMargin` | 28 | Horizontal page margin |

**Dark surfaces** (camera, Story editor, share frames): `#000` for viewfinders and the editor, `#0B0B0C` for photo-less canvases. Text white at 100% / 80% / 55%. Coral unchanged.

**Never invent a colour.** If a screen seems to need one, that is a design decision to raise, not a hex to add.

**Never pure `#000000` or `#FFFFFF` as a content colour** — they flatten depth. Use `Theme.ink` and `Theme.surface`. (Full black is correct only as a camera/editor backdrop.)

**One corner-radius system.** Cards 24, controls 16, stat tiles 20, mini cards 18. Do not introduce a fourth value because something "looks better at 14".

---

## 3. Type roles

System faces only — SF Pro, SF Rounded, SF Mono, New York — via `Font.system(size:weight:design:)` plus `.fontWidth(...)`. **No bundled fonts anywhere.**

| Role | Face | Notes |
|---|---|---|
| Screen title | SF Pro, 26 bold | |
| Card title | SF Pro, 17–21 bold | |
| Body | SF Pro, 15 medium, `inkSecondary` | |
| Fine print | SF Pro, 12–13 medium, `inkTertiary` | |
| Eyebrow label | SF Pro Text, 11–13 semibold, uppercase, tracking +8–14% | `LEAVE`, `NEXT`, `GYM BY` |
| Numbers that tick | SF Pro **Rounded**, bold/heavy, `.monospacedDigit()` | Countdown, streak, stat tiles |
| Statement (share frames) | SF Pro Display, black, `.fontWidth(.condensed)`, tracking −2% | Athletic without brush-script |
| Receipt / timeline | SF Mono (`design: .monospaced`), tabular | |
| Editorial annotation | New York (`design: .serif`), italic | Sparingly |

**Rules**
- Any text carrying data gets `lineLimit` + `minimumScaleFactor` (0.6–0.85) and a bounded width.
- Test every number with `7`, `127`, and `0`. Test every string with a long localisation (`Donnerstag`, `Mittwoch`).
- **Headlines max 2 lines.** If it wraps to 3, shorten the copy or drop the size.
- **Eyebrow restraint:** at most one eyebrow label per three sections on a screen. A screen of uppercase micro-labels reads as a dashboard, not a product.
- Emphasis inside a headline uses italic or a heavier weight of the *same* face. Never mix two typefaces for emphasis.

---

## 4. Surfaces and depth

- **Warm card:** `Theme.surface` fill, `cardRadius`, 1 pt `Theme.border` stroke, shadow `black 0.045–0.06, radius 10–18, y 4–8`. Use the `warmCard()` modifier.
- **Depth is shadow + hairline, never blur.** Blur and material are reserved for floating glass chrome (§8).
- **Prefer spacing over cards.** If two groups can be separated by whitespace, do not wrap each in a bordered card. Nested cards (a card inside a card) are banned.
- **No glow, no neon, no outer shadow used decoratively.** Depth comes from a hairline and a soft lift, nothing else.

---

## 5. Motion — when to animate at all

Most bad UI motion exists because nobody asked whether it should. Ask.

### 5.1 The frequency gate (run first)

| How often the user does this | Motion allowed |
|---|---|
| 100+ times a day | **None.** Ever. |
| Tens of times a day (tab switch, row tap) | Near-imperceptible only |
| Occasional (sheet, modal, editor open) | Standard animation |
| Rare / first-time (onboarding, arrival success, milestone) | Delight budget available |

### 5.2 The purpose test

Every animation must be one of: **feedback**, **spatial consistency**, **state indication**, **preventing a jarring change**, **explanation** (onboarding only), or **delight** (rare tier only).

**If you cannot name which one in a single sentence, delete the animation.**

### 5.3 Duration

| Element | Range |
|---|---|
| Button press feedback | 100–160 ms |
| Small popover, tooltip, toast | 125–200 ms |
| Menu, picker, chip selection | 150–250 ms |
| Sheet, cover, editor, modal | 200–500 ms |

**Hard ceiling: 300 ms for anything in the Operate layer.** Longer needs a stated reason. The morning flow's celebratory moments are the exception.

### 5.4 Curves and springs

Use the project tokens first:

| Token | Curve | Use |
|---|---|---|
| `Theme.settle` | `timingCurve(0.22, 0.9, 0.24, 1) · 0.55s` | Page-level content landing |
| `Theme.stateChange` | `easeInOut 0.18s` | Colour/state flips — **never scale** |
| `Theme.pageTurn` | `timingCurve(0.2, 0.85, 0.2, 1) · 0.42s` | Vertical paging, no bounce |
| `Theme.celestial` | `0.95s` | Night→morning illustration only |

Springs, by job (Apple's own parameters):

```swift
// Default UI — no momentum behind it. Critically damped, no overshoot.
.spring(response: 0.30...0.40, dampingFraction: 1.0)

// Press / release of a soft control
.spring(response: 0.28, dampingFraction: 0.58)

// Momentum-driven — the user flicked, threw or dragged it
.spring(response: 0.30...0.40, dampingFraction: 0.80)

// Commit / snap after a gesture
.spring(response: 0.30...0.34, dampingFraction: 0.85...0.90)
```

**Bounce must be earned.** Overshoot on a menu that simply faded in feels wrong. Overshoot on a card the user flicked feels right, because the gesture supplied the energy. Never put bounce on a state change the user did not physically push.

**Never use `easeIn` on UI.** It delays the response at exactly the moment the user is watching for it. Entrances and exits use `easeOut` or a strong custom curve.

### 5.5 What to animate

- Prefer `opacity`, `scaleEffect`, `offset`, `rotationEffect` — these are cheap.
- **Avoid animating `frame(width:height:)`, padding, or anything that forces a layout pass** on every frame. If a size must change, animate `scaleEffect` where possible.
- Entrances start from `scaleEffect(0.94...0.97)` + `opacity(0)`. **Never from `scale(0)`** — it reads as a cartoon pop.
- Scale from the element's origin, not its centre, when it belongs to a trigger: `.scaleEffect(x, anchor: .topLeading)` for a menu growing out of a button. Sheets and modals are exempt and scale from centre.

### 5.6 Stagger and asymmetry

- Entrance cascades: **30–80 ms** between siblings. Never animate ten things simultaneously; never stagger more than ~6 items (the tail becomes a wait).
- **Asymmetric timing:** the user's deliberate action animates slowly, the system's response snaps. A press-and-release that uses identical timing in both directions feels dead.
- **Exit the way you entered.** A sheet that rose from the bottom dismisses to the bottom. A card that zoomed from a grid cell returns to that cell.

### 5.7 One entry animation, once

Elements may animate in once. **Nothing loops.** No pulsing buttons, no breathing glows, no perpetual shimmer. Anything rendered to an image (share frames) must render its **settled end state** — pass an `isAnimated: false` flag through the same view rather than building a second one.

### 5.8 Reduce Motion

Honour `@Environment(\.accessibilityReduceMotion)` everywhere.

**Reduce Motion means gentler, not absent.** Swap springs and offsets for a 180–220 ms opacity crossfade. The *outcome* must be identical — the same screens, the same states, the same reachability. Never disable a feature because motion is reduced.

---

## 6. Gestures — where the quality actually lives

This is the section that separates a native-feeling app from a web page in a wrapper. Get this right and everything else is forgiven.

### 6.1 Direct manipulation: 1:1 tracking

**Touch and content move together.** When the user drags something, it stays glued to their finger and preserves the offset from where they grabbed it. Snapping the element's centre to the finger destroys the illusion instantly.

```swift
// Preserve the grab offset — captured on the first change, not recomputed.
@State private var grabOffset: CGSize?
// On first .onChanged: grabOffset = value.startLocation - elementOrigin
```

### 6.2 Interruptibility — the single most important rule

**The thought and the gesture happen in parallel.** Every animation must be grabbable and redirectable mid-flight.

1. **Never lock input during a transition.** No "wait for the animation to finish" states.
2. **Always animate from the current presented value, never from the logical target.** Starting from the target causes a visible jump when the user interrupts.
3. **Use springs for anything gesture-driven.** SwiftUI springs retarget from the current value natively; a fixed-duration `timingCurve` restarts and feels broken under interruption.
4. **Blend velocity at reversals, never hard-cut it.** When a drag reverses, carry the velocity into the new spring. A discontinuity reads as hitting a wall.
5. **Decompose 2D motion into independent X and Y springs.** One spring on 2D distance desynchronises when the axes move at different speeds.

### 6.3 Velocity handoff

When the finger lifts, the animation continues at the speed the finger was moving. There must be **no visible seam** between dragging and animating.

SwiftUI gives you `DragGesture.Value.velocity` (iOS 17+). Pass it into the spring rather than starting from rest.

### 6.4 Momentum projection — animate where the gesture is going

Do not snap to the nearest point from where the finger lifted. Project where the flick was *heading*, then snap to the target nearest that projection.

**SwiftUI hands you this for free:** `DragGesture.Value.predictedEndTranslation` is the native equivalent of Apple's projection formula. Use it for every paging, snapping and dismissal decision.

Apple's underlying formula, if you ever need it manually:

```swift
func project(initialVelocity: CGFloat, decelerationRate: CGFloat = 0.998) -> CGFloat {
    (initialVelocity / 1000) * decelerationRate / (1 - decelerationRate)
}
// 0.998 ≈ normal scroll feel. 0.99 feels snappier.
```

### 6.5 Rubber-banding at boundaries

At an edge, resist progressively. A hard stop reads as frozen; continuous resistance reads as "responsive, but there's nothing more here."

```swift
func rubberband(_ overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
    (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
}
```

`0.55` is Apple's value. Simplified alternative already used in this codebase: `overshoot * 0.35`.

### 6.6 Commit thresholds

Resolve a gesture on release with **distance OR velocity**, never distance alone:

> Commit when `|predictedEndTranslation| > 35% of the travel distance` **or** `|velocity| > 500 pt/s`. Otherwise spring back.

A slow long drag and a fast short flick must both work.

### 6.7 Gesture arbitration

- Resolve intent in the **first ~10–12 pt** of travel (axis lock), then commit to one interpretation. Two gestures must never fight over the same touch.
- Default disambiguation in this app: **two fingers = transform content; one finger horizontal = page; one finger vertical = scroll/pan.** Document any exception in a comment.
- Where an element must be individually draggable inside a paging surface, require a **tap to select it first** (Instagram/Snapchat text-tool model). Selection changes which gesture owns the touch.

### 6.8 Taps

- **Highlight on touch-down, commit on touch-up.** Feedback must not wait for the lift.
- Allow **cancel-by-dragging-away**: sliding off the control before release aborts the action.
- Minimum 44 pt hit target, with ~10 pt of hysteresis padding beyond the visible bounds.
- Avoid double-tap wherever single-tap feedback matters — double-tap detection unavoidably delays the single tap.

### 6.9 Spatial consistency

- **Anchor to the source.** A sheet, menu or detail view originates from the element that triggered it. Use `matchedTransitionSource(id:in:)` + `.navigationTransition(.zoom(sourceID:in:))` (iOS 18) rather than hand-rolling a morph.
- **Enter and exit along the same path**, always.
- Presenting a sheet in the same runloop turn as dismissing another is **silently dropped**. Defer ~120 ms (the `present {}` pattern in `ProgressPhotoImporter`).

---

## 7. Interactive state completeness

Every interactive surface must define **all four**. A screen that only has its happy path is unfinished.

| State | Requirement |
|---|---|
| **Loading** | A shape matching the final layout, not a spinner over blank space. Never block the whole screen for a local load. |
| **Empty** | Says what is true and what to do next. Never a zero dressed up as data. |
| **Error** | Inline and specific. Offers a retry. Never a dead end, never a silent failure. |
| **Pressed** | Visible tactile feedback — `scaleEffect(0.94...0.98)` or a fill change, with a haptic. |

**Zeros are not an empty state.** A row of `0`s on a first-run screen tells a new user they have nothing. Omit the figure entirely, or say the true thing (`your first week starts now`).

---

## 8. Liquid Glass (iOS 26) and its fallbacks

Glass belongs to the **navigation and controls layer floating above content**: tab bars, floating capsules, close buttons, format toggles, frame pickers, share bars. **Never** on cards, lists, photos, chart bars, or anything that is itself content. **Never glass on glass.**

Copy this chain exactly — the project already implements it in `GlassSurface.swift` and `StoryEditorChrome.swift`'s `EditorGlass`:

```swift
if reduceTransparency {
    content.background(Theme.surface, in: .capsule)
           .overlay { Capsule().strokeBorder(Theme.border, lineWidth: 1) }
} else if #available(iOS 26.0, *) {
    content.glassEffect(.regular.interactive(), in: .capsule)   // .clear over photos/video
} else {
    content.background(.ultraThinMaterial, in: .capsule)
           .overlay { Capsule().strokeBorder(.white.opacity(0.55), lineWidth: 1) }
           .shadow(color: .black.opacity(0.07), radius: 10, y: 4)
}
```

- Prefer system-provided glass over hand-applied: `.buttonStyle(.glass)` / `.glassProminent`, and `Menu` with `.glass` so the system performs the bubble-to-panel morph.
- Group neighbouring glass controls in one `GlassEffectContainer(spacing:)`; use `glassEffectID(_, in:)` for a selection that morphs between items.
- Tint glass only for the primary action (`.tint(Theme.accent)`), never decoratively.
- **Glass and materials never appear inside anything rendered by `ImageRenderer`** — it has no backdrop to sample and exports them flat or transparent.

---

## 9. Haptics — `Utilities/Haptics.swift`

| Call | When |
|---|---|
| `Haptics.selection()` | A selection actually **changed** (tab, chip, frame index). Once per change. **Never during a drag.** |
| `Haptics.tap()` | A small deliberate action (retake, extend, flip) |
| `Haptics.soft()` | Press-down on a bubble; copy to clipboard; a tap that explains rather than selects |
| `Haptics.medium()` | Shutter; starting something |
| `Haptics.commit()` | **The** success moment (saved, arrived, mission complete). Never twice for one event. |
| `Haptics.glassBreak()` | The unlock moment only |

Call `prepareSelection()` before a surface where the first tick's latency would be felt.

---

## 10. SwiftUI conventions in this codebase

- `@Observable` `@MainActor final class` for stores and models. `nonisolated` on decoding, file IO and static maths. `Task.detached` for image work, results hopping back to the main actor.
- **One source of truth per concept.** Views derive; they never store a second copy. Derived models (`HomeCardDeriver`, `ProgressAnalytics`, `StreakEngine`) are pure functions taking `now:` and `calendar:` so they are testable.
- **Never compute a derived model inside `body`.** Cache it in `@State` and recompute on a real trigger (the pattern `ProgressTabView` uses with `refreshKey`).
- **Weeks are Monday-first everywhere:** `ProgressAnalytics.displayCalendar()`. Training days come only from `plan.effectiveTrainingDays(fallback:)`. Never `Calendar.current` week maths, never `schedule.trainingDays` directly.
- Persistence: small metadata in `UserDefaults`, bytes on disk, **file names stored, never absolute paths**.
- Accessibility on every custom control: label, hint where the action is not obvious, `accessibilityElement(children: .combine)` on composite rows, `.isButton` / `.isSelected` traits, adjustable traits on carousels. A control that is tappable is never marked `.isNotEnabled`.
- Dynamic Type scales chrome. Fixed-size canvases (export surfaces) do not scale, but their surrounding chrome does.
- Comments explain **why** (the failure being avoided), not what. Match the existing density.
- Swift Testing (`import Testing`, `@Test`, `#expect`) for pure logic. Fixtures live behind `#if DEBUG` and never leak into runtime paths.

---

## 11. Copy and content

- Lowercase, terse, declarative in chrome. No marketing voice, no taglines in a working surface.
- **Banned words:** elevate, seamless, unleash, revolutionise, next-gen, supercharge, effortless, journey (as a verb), crush, beast mode, grind.
- **No em-dashes (`—`) in UI strings.** It is the single most recognisable machine-written tell. Use a full stop, a comma, a line break, or restructure. A regular hyphen for compounds and ranges is fine.
- **No emoji in chrome.** The arrival screen's single 🔥 is the deliberate exception.
- **Never fabricate:** no `John Doe`, no `Acme`, no invented precise figures (`92%`, `4.1×`), no fake dates, no placeholder streaks. If the data is missing, the element is absent.
- **Forward-looking, never a verdict.** `unlocks when you keep your first week`, not `you haven't earned this`.
- One intent per screen. `Get started` + `Begin` + `Let's go` on one screen is three labels for one action — pick one.

---

## 12. Anti-slop checklist — run before calling any visual work done

- [ ] One accent per screen, and it is coral
- [ ] No gradients except a flat dark canvas; no glows, textures, metal, grunge
- [ ] No pure `#000` / `#FFF` as content colours
- [ ] One corner-radius system, no fourth value
- [ ] No nested cards; spacing used instead of borders where possible
- [ ] No brush/script/handwriting fonts; no bundled fonts
- [ ] No em-dash anywhere in UI copy
- [ ] No emoji in chrome; no banned marketing words
- [ ] Headlines ≤ 2 lines; eyebrows ≤ one per three sections
- [ ] No three identical cards in a row; layout varies across a long screen
- [ ] Every number traceable to a model field; nothing hard-coded
- [ ] No zeros presented as an empty state
- [ ] Every animation nameable in one sentence; none loop; all have an end
- [ ] Frequency gate applied (no motion on high-frequency actions)
- [ ] Duration within the table; nothing over 300 ms in Operate without a reason
- [ ] No `easeIn` on UI; no `scale(0)` entrances
- [ ] Bounce only where a gesture supplied the energy
- [ ] Gestures track 1:1, are interruptible, and commit on distance **or** velocity
- [ ] Rubber-banding at every boundary; nothing hard-stops
- [ ] Enter and exit along the same path
- [ ] Reduce Motion path exists and reaches the same outcome
- [ ] Glass only on floating controls, with both fallbacks
- [ ] Loading, empty, error and pressed states all defined
- [ ] 44 pt minimum hit targets; VoiceOver labels on every custom control
- [ ] Type tested with `7`, `127`, `0`, and a long localised word
- [ ] Nothing outside the requested scope was changed

---

## 13. How to work

- **Build it fully, then inspect once.** Do a single batched review pass (small phone and large phone together), fix everything found in one batch, confirm with at most one more pass, then stop. Do not burn effort on open-ended self-QA.
- **The brief wins.** If this file and an explicit instruction in the task conflict, the task wins — but say so out loud rather than silently ignoring the rule.
- **Refinement preserves; redesign replaces.** If asked to refine, keep the existing identity, behaviour, copy and scope. Do not quietly redesign a screen you were asked to adjust.
- **Do not widen scope.** Touching a screen you were not asked to touch is a defect, however tempting.
