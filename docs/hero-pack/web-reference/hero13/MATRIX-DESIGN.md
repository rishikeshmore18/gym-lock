# Matrix Dynamic: design brief

You are redesigning scenes for **GymLock**, a native iOS app that locks distracting apps until you get to the gym (alarm in the morning, 20 minutes on the gym floor verifies the session, a 66-day habit). The home screen has one **hero card**. It has two visual styles: **Ridge** (painterly landscape; do not touch anything of it) and **Matrix** (a dot-matrix board). Each style has a Classic and a **Dynamic** mode. **Only Matrix Dynamic is in scope.**

The owner (Rishi) reviewed Matrix Dynamic on his iPhone and said: it still looks borrowed from Ridge, out of place and unpolished; breaking stones and pebbles make no sense in dots; random star fields look like noise. He liked: the **battery** (Wednesday bedtime), the **sand-timer countdown** (hourglass / draining tank), the **sunrise** (Sunday alarm dawn), and the **+1** (Friday done card). He wants every Matrix scene to be **remarkable, clear at a glance, premium, and fluid**, with **"fluid matrix motions and animations"** everywhere.

## Audience and brand
- People building a gym habit, mostly 20 to 40, iPhone users who like premium minimal design (Apple, Nothing Phone's Glyph Matrix, Teenage Engineering, Whoop, Oura, Apple Watch faces).
- Black and white about 99%. Coral `#E85D4E` is a single small accent: **one cell or a 2 x 2 at most per scene**, meaning "you / now / the last piece".
- Premium, calm, confident. **Never cartoonish. No characters, people, faces, animals.** English only. No em dashes in any copy.
- The board is an instrument (LED display), not an illustration. **No landscapes in dots** (no mountains, ridgelines, rocks, pebbles, trees, boats, lakes, sea), **no random star or noise fields**.

## Proven principles to design by
1. **Semantic distance** (McDougall, Isherwood): symbols read fastest when they sit close to their meaning. Use concrete, familiar objects of gym life and phone life: alarm clock, bell, battery, heartbeat line, stopwatch, barbell, dumbbell, padlock, calendar, week strip, progress ring, bars, arrows, hourglass, big LED digits. Abstract metaphors drawn in dots read as noise.
2. **Motion onset captures attention; ongoing motion does not** (Abrams & Christ 2003). Give each scene one clear beat (an onset), then settle into a calm idle. Do not keep everything moving.
3. **IKEA effect** (Norton, Mochon & Ariely 2012): effort turns into attachment only when it ends in something completed; building then destroying cancels it. Build things up; never smash what the user made.
4. **Goal gradient** (Kivetz, Urminsky & Zheng 2006) and **endowed progress** (Nunes & Dreze 2006): show the track and the progress on it; people speed up near the end.
5. **Peak-end** (Kahneman): the done moment and milestones deserve the peak.
6. **Variety slows hedonic adaptation** (Sheldon & Lyubomirsky 2012): the same moment must look different every day of the week.
7. **NN/g and Apple HIG motion**: UI motion 200 to 500 ms, big reveals up to about 1.2 s; motion must be purposeful; avoid slow full-screen 0.2 Hz oscillation and abrupt brightness jumps; haptics on the same frame as the visual hit.

## The hero card (home)
- Card is 1000 x 488 design units. The copy (eyebrow, big title, a support line) sits on the **left** (x 52 to 522). The board is **38 x 35 cells** at x = 492, pitch 12.5, on the **right**. Columns 0 to 6 fade out under the copy.
- **Art zone: columns 8 to 37, rows 2 to 33. Centre (CX, CY) = (22, 17).** Keep the composition balanced inside it.
- Night states (firstnight, bedtime) use a dark card even in light mode. Others follow the theme: **check both light and dark**.
- The copy for every moment and day is in `../hero12/copy12.ts` (`STATE12[state][day]`, `DONE12[pos][day]`). **Read it.** The scene must match what the card says.

## Day families (a day must feel like one flow across its moments)
| Day | Family | Done object (reserved) |
|---|---|---|
| Mon | radiant: rings, rays, dials | **Sunrise**: a sun rising over a horizon line, rays |
| Tue | tiles: blocks, grids, tiles | **The wall**: blocks laid into a wall, locked with an outline |
| Wed | signal and energy: waveforms, heartbeat, charge | **Battery**: cells fill, full with a bolt |
| Thu | levels and strength: bars, faders, plates | **Barbell**: plates loaded on both ends, then lifted |
| Fri | vectors: arrows, chevrons, upward push | **+1**: stacked chevrons climb, then burst into "+1" |
| Sat | loops: orbits, rings, laps, stopwatch | **Ring**: an activity-style ring closed arc by arc |
| Sun | time and the week: week strip, calendar, dial | **Hourglass**: sand runs through, turned over for a new week |

- The **done object** is shown in the full-screen done flow (taps build it) **and** on the home card's `verified` state (finished). Those two must match.
- **Every other moment of that day must not use its done object or its signature motion** (no battery on Wednesday's alarm, no hourglass or falling sand on Sunday's rest). Exception the owner asked for: Wednesday bedtime keeps its battery.
- **Across days, the same moment must never look alike**: seven different ideas per moment.

## Motion: what "fluid matrix" means here
The board is a field of particles (dots) on springs (`mdots.ts`). Every target has an identity:
- `g.on(x, y, b, c)` lights a **snapped cell**; identity = the cell. If a cell turns off and another turns on, the dots fade in and out in place (LED step). Use it for **static structure**.
- `g.fr(x, y, b, c)` is a **free particle**; identity = its push order in the frame. The same particle glides to its new position every frame. **Anything that moves must be free particles, pushed in the same order and the same count every frame.** To hide one, set `b = 0`; never skip it, or every later particle re-keys and jumps. `g.fs` is the same but snapped to a cell centre (steps cell to cell; less fluid).
- Return `{ph}` to change phase: the engine re-deals and **all dots fly to the next form** (`o: {stagger, scatter, burst}` shapes the flight). That is the signature move: assemble, disperse, reassemble. Use it for transformations.
- The scene's first deal happens when the card enters the state: dots fly in from the previous scene. Design the first 0.6 s.
- After the beat, a **calm idle**: a slow light sweep, a breath, a gentle flow. **No random flicker, no blinking many cells, no noise.**
- One bold beat when the moment calls for it (alarm, done, milestones): `flash` up to 0.3, `shake` up to 0.4, and matching `hap` (haptics) on the same time.
- Keep lit targets under about 400 for clarity (hard cap 720; snapped cells come first, free particles after).

## API (read `mxlib.ts`, `mdots.ts`, `mx/common.ts`; do not edit them)
- `MScn = {draw(g, c) => MOut | void, hap?: {t, kind}[]}`, `MOut = {ph?, o?, flash?, shake?}`.
- `c`: `t` (global seconds), `T` (seconds since the card entered this state), `d.setupDone` (bool[3]), `d.countdown` (seconds left before leaving), `d.atgym` (seconds on the gym floor; proof at `PROOF` = 1200 = 20 min), `d.stillLeft` (seconds left this evening), `day` (0 Mon to 6 Sun), `pos` (first, middle, last of week), `D` (day of 66, sessions, week).
- `G`: `on`, `fr`, `fs`, `line`, `ring` (angles: 0 = up, clockwise), `disc`, `rect`, `glyph`, `num` (LED digits 0-9, ':', and D O N E '.'), `out`.
- `icon(g, name, cx, cy, scale, b)`, `ICON` (bell, sun, moon, lock, dumbbell, check, pause, plane, flag, pin, house, bag, shoe, plus, power, flake, arrowR, arrowU, z, bolt), `iconPts`.
- Easing: `ez`, `eio`, `back`, `spr`, `pulse`, `cl`, `lerp`, `rnd` (deterministic hash). Alarm rhythm: `RINGS`, `ringBeat`, `lastRing`, `ringIndex`.
- Need a new helper or icon? Define it **in your own file**.

## How to work
1. For each scene you own: read the copy, render the current scene, and write down in one or two lines what it shows and what is wrong (meaning, polish, fluidity, uniqueness, composition).
2. Decide: refine, redo, or build from scratch. Then implement.
3. Render and look. `python3 test/sheet.py <moment> /tmp/<you>_<moment>.png --T 0.3,0.8,1.6,3.5 --theme dark` (rows = days, columns = times; full card with copy). Also `--theme light`, and a fine time strip to check fluidity (for example `--days 3 --T 0.1,0.2,0.3,0.4,0.5,0.6`). Relevant data: `--data '{"atgym":1195}'`, `'{"countdown":95}'`, `'{"setupDone":[true,false,false]}'`, `'{"stillLeft":3000}'`.
4. Iterate until every scene passes the checklist. Type-check: `bash test/tscheck.sh <moment>`.
5. Only edit the files you own. Do not run the app build. Do not edit shared files.

## Checklist (every scene)
1. Says the same thing as the card's copy; a gym-goer gets it in one second.
2. A familiar, concrete object or a clean instrument (dial, bar, ring, digits), not a metaphor.
3. Entrance (first 0.6 s), one beat if the moment needs it, calm idle after.
4. Fluid: moving parts are free particles with stable order; no flicker, no noise.
5. Unique among the 7 days of this moment; in its day's family; not the day's reserved done object (unless it is the done object).
6. Composition inside the art zone, balanced, crisp, not cluttered; reads well at phone size.
7. Coral: exactly one small accent.
8. Looks right in light and dark.
