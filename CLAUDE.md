# Project rules

This is a native SwiftUI iOS app (deployment target iOS 18). Never apply web patterns (CSS, Tailwind, GSAP, Framer Motion, media queries).

## 1. Behavior: `docs/FLOW.md`

Before writing or changing ANY code that touches alarms, snooze, the night lock, the gym lock, sessions, gym arrival, Apple Health checks, skips, reschedules, home workouts, streaks, freezes, or the notifications for any of these, read `docs/FLOW.md` and follow it exactly. It is the source of truth for what the app does. If a request conflicts with it, stop and say so before writing code. Never edit the rules in it; only mark items as built, as that file explains.

## 2. Look and feel: `docs/UI-RULES.md`

Before writing or changing ANY view, control, animation, gesture, or user-facing copy in this repo, read `docs/UI-RULES.md` and follow it. It is a standing rule, not a suggestion. It overrides default styling and motion choices.

## 3. When they overlap

`docs/FLOW.md` decides what happens and the exact wording of quoted lines. `docs/UI-RULES.md` decides how it looks, moves and feels. A screen in the gym flow follows both.
