# Porting guide: Matrix scenes, TypeScript to Swift

How to translate every remaining scene file in `web/hero13/mx/*.ts` (and the screens in
`web/hero13/mxstory.ts`) to Swift mechanically, so the native board matches the web frame for frame.
Read this before porting anything. The three worked examples are in `MatrixScene.swift`
(verified Wed `battery`, wake Mon `bell`, countdown Wed `waterClock`) and `MatrixStoryView.swift`
(`finWed`, `count`, `mini`).

## 1. The files

| File | Ports | Notes |
|---|---|---|
| `MatrixEngine.swift` | `hero13/mdots.ts` | `JSMath` (JS numeric semantics), `MatrixHash`, `MatrixTarget`, `MatrixDealOptions`, `MatrixEngine` |
| `MatrixBoard.swift` | `hero13/mxlib.ts`, LED font from `hero4/dots.ts` | `MatrixBoard` (= `G`), `MX` namespace (easing, rings, icons), `MatrixLED` |
| `MatrixScene.swift` | `mxlib.ts` types, `mx/common.ts`, `mx13.ts`, 3 scenes | `MatrixContext`, `SceneOut`, `MatrixScene`, registry, `MatrixParity` (DEBUG) |
| `MatrixCardView.swift` | `hero13/card13m.tsx`, `kin13.tsx` | the card, grid cache, copy layer, `MatrixHarnessFrame` (DEBUG) |
| `MatrixStoryView.swift` | `story13m.tsx`, `mxstory.ts`, `app13.tsx` overlay, `screens12.ts` CFG_M | flow model, board, copy, collapse |
| `HeroHaptics.swift` | haptic timing from `app13.tsx` | player + scheduler |

Dependency order: Engine, Board, Haptics, Scene, CardView, StoryView. No file touches app code; the
app supplies copy (`MatrixCardCopy`, `MatrixStoryCopy`) and state (`MatrixCardInput`).

If the project uses Xcode 26 "default actor isolation = MainActor", the scene tables and `MX`
helpers become main-actor isolated. That still compiles, because every caller is on the main
actor, but if a test target complains, mark the helpers `nonisolated`.

## 2. One scene file, mechanically

A TS scene file:

```ts
import {CX, CY, G, MC, MScn, cl, ez} from '../mxlib';
const K = 0.35;                                  // module constant
const helper = (T: number) => ez(T / K);          // module helper
export const SCENES: MScn[] = [
  { draw: (g, c) => { ...; return {o: {stagger: 0.3}, flash: x}; }, hap: [{t: 0.5, kind: 'heavy'}] },
  ...7 entries, Monday first
];
```

becomes:

```swift
extension MX {
    public enum Bedtime {                          // one enum per TS file
        static let K = 0.35                        // module constants: static let
        static func helper(_ T: Double) -> Double { ez(T / K) }

        public static let mon = MatrixScene(haptics: [HapticCue(t: 0.5, kind: .heavy)]) { g, c in
            ...                                    // the draw body, statement for statement
            return SceneOut(opts: MatrixDealOptions(stagger: 0.3), flash: x)
        }
        ...
    }
}
```

Then add the seven entries to `MatrixSceneRegistry.table` (index 0 = Monday).

Rules:

1. **Keep every statement in the same order.** `g.on`, `g.fr`, `g.fs`, `g.line`, ... must be called in
   the same order, the same number of times, with the same arguments. Identity depends on it
   (section 5).
2. **Keep the TS names.** `T`, `c`, `g`, `lv`, `fx`. Rename only what collides with Swift
   (`floor` became `flr` in the water clock, because `floor` is the libm function).
3. **Module tables are computed once** (`static let`). IIFEs `(() => {...})()` become
   `static let X: [..] = { ... }()`.
4. **`draw` returning nothing** (`void`, `{}`) returns `.none`. `o: undefined` is `opts: nil`.
   `ph` becomes `phase: String`. The web key prints a number phase with `${}`; use the same text
   (`"1"`, `"plus"`), or the parity key differs.
5. **Haptic arrays** become `[HapticCue]`. Spread-and-map (`[...ringHap, ...Array.from(...)]`) becomes
   `ringHap + (0..<24).map { ... }`.
6. **Never introduce randomness** (`Double.random`, `Date()`). Use `rnd(i)`, which equals the web.

## 3. Type and API mappings

| TypeScript | Swift | Pitfall |
|---|---|---|
| `number` | `Double` | Always Double in scene code. Use `Int` only for loop counters and indices, converting at use. |
| `k / N` with integer values | `Double(k) / Double(N)` | **`Int / Int` truncates in Swift.** The single most common porting bug. |
| `c` flag `0 / 1` (or `cond ? 1 : 0`) | `Int` param `0 / 1` | The board API takes `Int` for `c`, like the TS. |
| `[x, y]` tuple | `(Double, Double)` | Destructure with `let (x, y) = ...`. |
| `Record<string, T>` | `[Key: T]` with an enum key, or a `switch` | Prefer enums (`MX.Icon`). |
| `rows: string[]` bitmaps | `PixelRows([...])` (decoded once) | Never iterate `String` per frame. |
| `[...s]` (code points) | `s.unicodeScalars` | Not `Character`s. |
| `s.padStart(n, ' ')` | prepend `" "` scalars | See `led()` in `MatrixStoryView.swift`. |
| `arr.reduce((a, b) => a + b, 0)` | a `for` loop summing left to right | Same order, same rounding. |
| `x ?? y`, `x?.y` | same | |
| `a \|\| 5` on a number | `a != 0 ? a : 5` | JS `\|\|` treats `0` and `NaN` as false. |
| `if (o.scatter)` | `if scatter != 0` | Same falsy rule. |
| `Array.from({length: n}, (_, k) => f(k))` | `(0..<n).map { f($0) }` | Guard `n >= 0`. |
| `for (let k = 1; k < N; k++)` | `for k in stride(from: 1, to: N, by: 1)` | `1..<N` **traps** when `N < 1`; `stride` is empty. |
| `for (let y = a; y <= b; y++)` with non-integer `a` | `var y = a; while y <= b { ...; y += 1 }` | Keep the Double counter: TS loops often start at `floor(...)` or `x + 0.5`. |
| `new Set<number>()` / `new Map()` | `Set<Int>` / `[Int: V]` | If iteration order matters (`G.out`), use an array plus an index dictionary, as `MatrixBoard` does. |
| `.sort((a, b) => f(a) - f(b))` | sort by `(f, originalIndex)` | JS sort is **stable**; Swift's is not guaranteed. Always add the index tie-break. |

### Math

| TS | Swift |
|---|---|
| `Math.floor(x)` | `x.rounded(.down)` |
| `Math.ceil(x)` | `x.rounded(.up)` |
| `Math.round(x)` | **`JSMath.round(x)`**. Never `x.rounded()`: JS rounds halves up (`Math.round(-2.5) == -2`), Swift away from zero (`-3`). |
| `Math.trunc(x)`, `x \| 0` (small values) | `x.rounded(.towardZero)`, or `JSMath.toInt32(x)` when it is hashing |
| `a % b` (numbers) | `JSMath.rem(a, b)` (= `truncatingRemainder`, sign of the dividend). `((a % b) + b) % b` stays as written, with `rem`. |
| `k % 2` on integer counters | `k % 2` on `Int` (same sign rule as JS) |
| `x ** 2` | `x * x` (also what V8 computes) |
| `x ** p`, `Math.pow` | `pow(x, p)` |
| `Math.min/max` | `min/max` (NaN differs: JS propagates NaN, Swift does not; never feed NaN) |
| `Math.hypot`, `atan2`, `sin`, `cos`, `exp`, `log`, `sqrt` | same names (Foundation). Results may differ from V8 in the last bit; harmless (section 6 tolerances). |
| `Math.PI` | `Double.pi`; `TAU` is `MX.TAU` |
| `Math.imul(a, b)` | `a &* b` on `UInt32` |
| `x >>> n` | `UInt32 >> n` (convert with `JSMath.toUint32` first) |
| `(... ) >>> 0` | `JSMath.toUint32(...)` |
| `x ^ y`, `x \| 1` on int32 | the same operators on `UInt32` bit patterns |

### Board API (identical signatures, positional arguments)

`g.on(x, y, b, c)`, `g.fr`, `g.fs`, `g.line(x0, y0, x1, y1, b, c, dash)`,
`g.ring(cx, cy, r, b, c, a0, a1, ry, step)` (pass `nil` for `ry` to mean `r`),
`g.disc`, `g.rect(x, y, w, h, b, fill, c)`, `g.glyph(rows, x, y, s, b, free)`,
`g.num(s, cx, y, scale, b, dim:, coral:)`, `MX.icon(&g, .bell, cx, cy, s, b, free)`, `MX.iconPts`.
Helpers that receive the board take it `inout`: `twinkle(&g, ...)`, `weekRow(&g, ...)`,
`ripple(&g, ...)`, `led(&g, ...)`.

## 4. Integer and float pitfalls that change pixels

1. **Operation order.** `((x1 - x0) * i) / n` and `(x1 - x0) * (i / n)` round differently. Copy the
   parenthesisation exactly. Same for `a * b * c` (left to right).
2. **Integer division.** Section 3. Check every `/` whose operands are both `Int`.
3. **`Math.round` halves.** Section 3. A wrong rounding moves a whole column of an LED digit.
4. **Float32 state.** Only the engine stores Float (it mirrors `Float32Array`). Every store is
   `Float(<Double expression>)`; every comparison with a literal widens first:
   `Double(b[i]) > 0.04`. `b[i] > 0.04` would compare against `Float(0.04)` and flip particles.
5. **Snapping.** `g.on` floors coordinates. A value that should be `17.0` but is `16.9999999` lands
   in another cell. If a ported scene shows a stray cell, look for an operation-order change first.
6. **Time.** The engine's `t` must be small (seconds since the view's epoch, plus a 2 s lead) so
   Float32 `start` times stay precise. Never pass `Date().timeIntervalSince1970`.
7. **Frame rate.** Never use per-frame constants in scenes; scenes are pure functions of `T`, `t`
   and the live data. The engine's brightness easing is time-based on iOS (`.timeBased`) and
   per-frame only in parity tests (`.perFrame`).

## 5. Identity: keep push order and counts identical

The engine keeps a particle per target identity:

- `on(x, y)`: id `iy * 256 + ix`. The cell keeps its dot as long as something writes it each frame.
  Order of `out()` is first-write order, so a cell's position in the list (and therefore the deal)
  depends on the order of the `on` calls.
- `fr / fs`: id `1_000_000 + push index`. **The nth free particle of the frame is the same dot every
  frame.** Anything that moves must be free particles pushed in the same order and count every
  frame. To hide one, push it with `b = 0`; never skip it, or every later particle re-keys and jumps.
  Branches like `if (a >= 0) g.fr(...)` in the TS are bugs to copy faithfully, not fix, unless the
  owner asks.
- `out()` is capped (720 card, 1400 story). Cells come first. If a scene exceeds the cap, the last free
  particles drop out; the TS does the same.
- A new key (state, day, pos, phase) re-deals everything. The key format is
  `"<moment>:<day>:<pos>:<phase or 0>"` on the card and `"<screen><day>:<phase>"` or `"count"` in
  the story, exactly as on the web.

## 6. Testing: render the same frame on web and iOS

Three levels, cheapest first.

### 6.1 Golden numbers (unit test, no rendering)

`MatrixParity.run()` and `MatrixParity.runStory()` (DEBUG) compare hashes, easings, ring helpers,
target counts and checksums of whole frames, and an engine run, against values produced from the
TypeScript sources. Wire them into Swift Testing:

```swift
import Testing
@testable import GymLock

@MainActor @Test func matrixParity() {
    #expect(MatrixParity.run() == [])
    #expect(MatrixParity.runStory() == [])
}
```

To add golden values for a newly ported scene, extend the Node script that made them,
`tools/matrix-golden.ts` (it imports the prototype under `gymlock-intro/web` by relative path),
bundle with esbuild from the prototype root, and run with Node. The core of it:

```ts
import {G} from '<web>/hero13/mxlib';
import {SCENES as B} from '<web>/hero13/mx/bedtime';
const f = (x: number) => +x.toPrecision(12);
const sum = (o: any[]) => f(o.reduce((a, q) => a + q.x * 1.3 + q.y * 0.7 + q.b * 5 + (q.c ? 11 : 0) + (q.id % 9973) * 0.001, 0));
const mc = (T: number) => ({t: 100 + T, T, d: {setupDone: [true, true, true], countdown: 3725.3, atgym: 0, stillLeft: 0}, day: 2, pos: 'middle', N: 5, D: {day: 23, week: 3, sessions: 14}});
for (const T of [0.5, 1, 2]) { const g = new G(); const o = B[0].draw(g, mc(T)); const out = g.out(); console.log(T, out.length, sum(out), JSON.stringify(o)); }
```

```sh
npx esbuild golden.ts --bundle --platform=node --format=cjs --jsx=automatic --outfile=golden.js && node golden.js
```

Tolerances: hash and integer helpers exact (1e-11); frame checksums 1e-9 relative (libm `sin`/`cos`
may differ from V8 in the last bit); engine runs 1e-5 (an `atan2` difference can swap two particles
with equal angles in a deal).

### 6.2 Frame images (snapshot diff)

The web has a harness per moment: `web/hero13/test/h_<moment>.html`, which calls
`window.paint(day, T, dd, theme, pos)` and steps a fresh engine from T = 0 at 30 fps
(`test/hcore.ts`). `MatrixHarnessFrame` in `MatrixCardView.swift` does exactly the same on iOS.

1. Web: open `h_verified.html`, run `paint(2, 1.0, {}, 'dark', 'middle')`, save
   `document.getElementById('c').toDataURL()` as `web.png` (600 x 293).
2. iOS: `let r = ImageRenderer(content: MatrixHarnessFrame(moment: .verified, day: 2, T: 1.0, dayData: ...)); r.scale = 1` and save `r.cgImage` as `ios.png`.
3. Diff the board rectangle (x 295...580, y 15...278 at this scale): per-pixel max channel
   difference <= 8 on 99.5% of pixels. Anti-aliasing differs slightly between Skia and Core
   Graphics; a wrong identity or rounding shows up as whole dots, far above that threshold.
   Ignore the copy area: the harness copy is a rough guide only.

Check T = 0.2 (dots in flight), the beat (e.g. battery `FULL(5) = 0.95 s`), and 3 s (idle), in light
and dark.

### 6.3 On device

Run the card on a 60 Hz iPhone (or the simulator) and a ProMotion iPhone side by side at the same
state: the motion must look identical (the 1/120 s substeps and time-based brightness guarantee
it). Check Reduce Motion (no flash, no shake, headline fades) and that haptics land on the visual hit.

## 7. Checklist per ported file

- [ ] One `extension MX { public enum <Moment> { ... } }`, constants `static let`, helpers `static func`.
- [ ] Every `/` between integers converted to Double; every `Math.round` is `JSMath.round`.
- [ ] Every `%` on Doubles is `JSMath.rem`; every `**2` is `x * x`.
- [ ] Loops with Double bounds kept as Double `while` loops; `stride` instead of `a..<b` where b may be < a.
- [ ] Same order and count of `on / fr / fs / line / ring / disc / rect / glyph / num` calls as the TS,
      including the ones with `b = 0`.
- [ ] `ph` strings identical to the web's printed value; `o` options identical (including stagger).
- [ ] `hap` cues identical (times and kinds).
- [ ] Seven entries added to `MatrixSceneRegistry`, Monday first.
- [ ] Golden values generated from the TS and added to `MatrixParity`; test passes.
- [ ] Harness image diff at three times (in flight, beat, idle), light and dark.
- [ ] No randomness, no `Date()`, no per-frame state inside the scene.
