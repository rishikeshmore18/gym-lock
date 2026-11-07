# Ridge port plan: the painted hero, native

A precise plan for porting the Ridge look (black and white watercolour world per weekday) of the hero
card and its done flow to SwiftUI, iOS 18, rendering the same picture on every iPhone at 60 or 120 Hz.

Sources (prototype, `web/`):

| File | Role |
|---|---|
| `hero10/wash.ts` | primitives (palette, `rng`, `gauss`, `fbm1`, `deform`, `wash`, `grain`, `granulate`), layout, and `Painter` (the `ridge` world) with its layer caches |
| `hero10/wash2.ts` | `Painter2`: the other nine worlds (`night`, `beach`, `sunrise`, `path`, `fog`, `lake`, `sunset`, `cairn`, `hourglass`), each with its own cached layers, plus birds, reflections, glitter |
| `hero12/wash3.ts` | `Painter3 extends Painter2`: the per-frame overlay (sun halo, ripples, ice, drip, tide, footprints, beacon, fireflies, constellation, shooting star, skipping stones, flash, bird burst, lanterns, rain, snow) |
| `hero13/stage13.ts` | the shared stage: `Shape` list in stage units, `Cam`, `camMatrix`, `paintShapes` (Ridge) and `toTargets` (Matrix) |
| `hero13/props13.ts` | 133 scenes (`W[state][day]`): backdrop params (`bd`), shapes (`draw`), camera (`cam`), haptics, kinetic type; `build()` with framing (`frameOf`) and `embolden` |
| `hero13/card13.tsx` | the card: `clampCam`, render order, paper fade, copy column, note |
| `hero12/story12.tsx` | the full-screen done flow (`sceneAt`, chips on the rock, copy) |

## 1. One frame of the Ridge card (card13.tsx), in order

```
B   = build(state, day, ctx)             // props13: scene params, shapes (emboldened), cam, type
cam = reduceMotion ? CAM0 : clampCam(B.cam)
P.xf = camMatrix(cam, pxScale)           // camera as a 2D affine, in device pixels
pal = palette(theme, round(S.night * 4) / 4)
shapes = reduceMotion ? B.shapes without 'flash' : B.shapes

P.render(ctx, cw, ch, S, theme, t, extra)    // Painter3 (inherits Painter2.render)
  ctx.setTransform(xf)                       // EVERYTHING below moves with the camera
  if S.kind == 'ridge': Painter.render       // section 2.1
  else: kinds[S.kind](...)                   // section 2.2
  if S.birds: birds(...)
  extra():
     P.overlay(ctx, cw, ch, S, theme, t)     // wash3, per frame
     paintShapes(ctx, shapes, px, pal, ...)  // stage13, per frame
  paper grain: multiply @0.55 (light) / screen @0.30 (dark)
reset transform
HTML on top: left fade to paper (0%: 1, 32%: .96, 44%: .70, 55%: .30, 66%: 0),
             the handwritten note (rotated -5 deg), the copy column (SF Pro Display 900)
```

Card background (paper): `rgb(246,246,244)` light, `rgb(14,14,16)` dark.

Quirk to preserve or consciously drop: for `kind == 'ridge'`, `Painter.render` draws the paper grain
and then `Painter2.render` draws it again, so the ridge world gets paper twice.

## 2. The layer stack

Every `layer(slot, key, w, h, paint)` call is a cache: repaint only when `key` changes. Keys include
the pixel size, theme, seed and the quantised night level, plus slot-specific parameters.

### 2.1 `Painter` (ridge world), back to front

| # | Layer | Cache key (beyond `w x h : theme : seed : night`) | Per frame |
|---|---|---|---|
| 1 | `sky` | none | draw at (0, 0) |
| 2 | sun glow + disc | not cached | radial gradient r = 6 sr, disc; y from `S.sun` |
| 3 | `far` | `peak.toFixed(2)` | x offset `px * 0.4`, `px = sin(t * 0.12) * w * 0.004` (slow parallax) |
| 4 | `mist` (2w wide) | `w x h : theme : night` | alpha `min(1, mist)`, x offset `((t * w * 0.006) % w) - w` |
| 5 | `near` (ledge, trees, pine) | `tree.toFixed(3) : rubble` | x offset `px` |
| 6 | `rock` (boulder) | `cracks.toFixed(3) : broken.toFixed(3) : rockIn.toFixed(3)` | x offset `px`; skipped if `noRock` |
| 7 | `front` mist (2w) | `w x h : theme : night` | when `mist > 0.6`: alpha `(mist - 0.6) * 1.5`, x `((t * w * 0.012) % w) - w` |
| 8 | rain | not cached | 160 strokes from `rng(3)` moving with t |
| 9 | `paper` grain | `w x h` | multiply 0.55 / screen 0.3 |

Layers 5 and 6 have keys that change **while a beat animates** (tree growth, cracks, `rockIn`). The web
repaints them every frame during those beats. See section 6 for how to avoid that natively.

### 2.2 `Painter2` worlds (wash2.ts `kinds`)

Each world caches 2 to 4 layers keyed `kind : w x h : theme : seed : night : peak`, then draws its
dynamic parts every frame:

| kind | cached layers | dynamic every frame |
|---|---|---|
| night | `n-sky` (stars), `n-mtn`, `n-shore` | moon phase (charge), water fill, **`reflect(ctx, ctx.canvas)`** (reads back the canvas), glitter |
| beach | `b-back`, `b-sand`, `b-palms` | hammock sway, waves |
| sunrise | `s-sky`, `s-peaks`, `s-sea` | sun disc, 14 radial-gradient rays (`screen` in dark), cloud sea drift |
| path | `p-base` | trail progress |
| fog | `f-base`, `f-mist` | mist drift |
| lake | `l-above`, `l-reeds` | `reflect(ctx, above)` (reads the cached `above` layer), boat |
| sunset | `ss-sky`, `ss-sea`, `ss-rocks` | sun, glitter |
| cairn | `c-base`, `c-near`, `c-stones` (stones count), `c-mist` | |
| hourglass | `h-base`, `h-near`, `h-ledge2`, `h-mist`, and the background kind (`hgBg`) | falling sand, lantern candle |

Plus `birds(...)` when `S.birds`, then the `extra` callback, then paper.

### 2.3 `Painter3.overlay` (wash3.ts), per frame, inside the camera transform

In this order: sunrise halo (ring-shaped radial gradient), ripples, ice, drip, tide, footprints,
beacon, fireflies, constellation (+ lines), shooting star, skipping stones, flash, bird burst,
lanterns, rain band, snow. All small vector work; no caching.

### 2.4 Props: `paintShapes` (stage13.ts), per frame, inside the camera transform

Shapes are in **stage units** (x 0...100, y 0...92; `SX(x) = 492 + 4.75 x`, `SY(y) = 26 + 4.75 y` in
card design units). Materials map to palette colours (`ink` = near, `mid`, `mist`, `light` = sun,
`paper`, `coral` = #E85D4E). Each kind is a short recipe of fills and strokes:

- `glow`: radial gradient, stops 0: 0.75a, 0.4: 0.28a, 1: 0.
- `disc`: optional dark under-bleed (light theme, pale material), optional pale halo, a 1.12 r body
  at 0.35a, the disc at 0.92a. Radius `max(0.5, r * k * 1.3)`, `k = 4.75 * px`.
- `dots`: same as disc for many points in one path (one fill per pass).
- `poly`: soft (three feathered strokes + fill at 0.62a) or hard (under-stroke, fill 0.88a, rim).
- wide `line` (w >= 2.4): six stacked butt-capped strokes at 0.13a, narrowing (a beam).
- `ring` / `line`: under-stroke (light theme, pale), a soft wide stroke, then the core stroke; dashes
  `[dash k, 0.9 dash k]`; ellipse arcs `a0...a1`.
- `flash`: full-canvas fill at `min(0.7, a)`.

## 3. Coordinate spaces and "identical on every iPhone"

The web paints in **device pixels** (`cw = 1000 * pxScale`), and several constants are absolute
pixels (`lineWidth = 1`, `Math.max(1, w / 900)`, the 256 px grain tile, `max(2, round(h / 220))`
reflection strips). `layoutFor(w, h)` switches to a tall layout when `w / h <= 1.2`.

Native rule: **paint every layer in card design units (1000 x 488) with the device scale in the
CTM.** Call every painter with `w = 1000, h = 488` (story: the composition size, 1080 x H) and set
`ctx.scaleBy(k * displayScale)` on the bitmap context. Geometry, random sequences and the layout
branch are then identical on every device; only the raster density changes. Treat the absolute pixel
constants as design units (1 px of the prototype on a ~1000 px wide card is ~1 design unit). The
grain tile is the one exception: generate it at 256 x 256 device pixels and tile it unscaled, so the
paper texture stays fine-grained on every density.

## 4. Camera

`build()` finds a frame per scene (`frameOf`: the shapes' bounding box at T = 1.2, 2.4, 3.6 s, cached
per `state:day:pos`), pushes in to it over 1.3 s (`ez(T / 1.3)`), pulls the subject toward the
picture's middle, slides so the subject is never cropped, then the scene's own `cam` move
(push, pan, punch, shake) is merged. `clampCam` keeps the painted backdrop covering the card.
`camMatrix` turns it into an affine: rotate and scale around the pivot `(SX(px), SY(py))`, then move
by `(x, y) * 4.75`. The same transform applies to every layer, the overlay and the shapes.

```swift
import CoreGraphics
import Foundation

/// stage13.ts `Cam`: s scale, (x, y) move in stage units, r rotation (radians), (px, py) pivot in stage units.
struct RidgeCam: Equatable, Sendable {
    var s: Double = 1, x: Double = 0, y: Double = 0, r: Double = 0
    var px: Double? = nil, py: Double? = nil
    static let zero = RidgeCam()

    static func SX(_ x: Double) -> Double { 492 + x * 4.75 }
    static func SY(_ y: Double) -> Double { 26 + y * 4.75 }

    /// card13.tsx `clampCam`: never reveal the card edge while the camera moves.
    func clamped() -> RidgeCam {
        var c = self
        let s = max(1, c.s, 1 + abs(c.r) * 0.9)
        let pxs = 492 + (c.px ?? 55) * 4.75, pys = 26 + (c.py ?? 46) * 4.75
        let lo = (-(1000 - pxs) * (s - 1)) / 4.75, hi = (pxs * (s - 1)) / 4.75
        let loY = (-(488 - pys) * (s - 1)) / 4.75, hiY = (pys * (s - 1)) / 4.75
        c.s = s
        c.x = min(hi, max(lo, c.x))
        c.y = min(hiY, max(loY, c.y))
        return c
    }

    /// stage13.ts `camMatrix(c, 1)`: card design units -> card design units.
    /// Concatenate with the device scale: `matrix.concatenating(CGAffineTransform(scaleX: k * ds, y: k * ds))`.
    /// Canvas `setTransform(a, b, c, d, e, f)` and `CGAffineTransform(a:b:c:d:tx:ty:)` share the layout.
    var matrix: CGAffineTransform {
        let pxs = Self.SX(px ?? 55), pys = Self.SY(py ?? 46)
        let s = max(1, self.s)
        let cs = cos(r) * s, sn = sin(r) * s
        let tx = pxs - (pxs * cs - pys * sn) + x * 4.75
        let ty = pys - (pxs * sn + pys * cs) + y * 4.75
        return CGAffineTransform(a: cs, b: sn, c: -sn, d: cs, tx: tx, ty: ty)
    }
}
```

## 5. Canvas 2D to Core Graphics / SwiftUI GraphicsContext

| Canvas 2D (prototype) | Core Graphics (layer painting) | SwiftUI `GraphicsContext` (per frame) | Note |
|---|---|---|---|
| `save()/restore()` | `saveGState/restoreGState` | copy the context struct (`var c = ctx`) | |
| `setTransform/translate/scale/rotate` | `concatenate`, `translateBy`, ... (CTM starts y-up: flip once) | `transform`, `translateBy`, `scaleBy`, `rotate(by:)` | |
| `globalAlpha` | `setAlpha` | `opacity` | |
| `globalCompositeOperation` `source-over / multiply / screen / source-atop / destination-out` | `setBlendMode(.normal / .multiply / .screen / .sourceAtop / .destinationOut)` | `blendMode` (same names) | |
| `fillStyle = 'rgba(...)'` via `css(c, a)` | `setFillColor(CGColor(srgbRed:...))` | `.color(Color(.sRGB, ...))` | `css` truncates channels (`c \| 0`): use `floor(c) / 255` |
| `createLinearGradient` + stops | `CGGradient` + `drawLinearGradient(..., options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])` inside a clip | `.linearGradient(Gradient(stops:), startPoint:, endPoint:)` | canvas pads beyond the ends; CG does not unless you pass both options |
| `createRadialGradient(x, y, r0, x, y, r1)` | `drawRadialGradient(..., startRadius: r0, endRadius: r1, options: [.drawsAfterEndLocation])` | `.radialGradient(_:center:startRadius:endRadius:)` | all prototype uses share one centre; elliptical glows use a scaled CTM (`paintMist`), which both APIs honour |
| `beginPath/moveTo/lineTo/closePath` | `CGMutablePath` | `Path` | |
| `arc(x, y, r, a0, a1)` | `addArc(center:radius:startAngle:endAngle:clockwise: false)` | `Path.addArc(..., clockwise: false)` | in a y-down space `clockwise: false` is the canvas default direction |
| `ellipse(x, y, rx, ry, rot, a0, a1)` | unit arc under `CGAffineTransform(scaleX: rx, y: ry)` + rotation + translation | same with `Path.applying(_:)` | |
| `quadraticCurveTo / bezierCurveTo` | `addQuadCurve / addCurve` | same | |
| `fill()` | `fillPath(using: .winding)` | `fill(path, with:)` (default non-zero) | never even-odd: overlapping washes must union |
| `stroke()`, `lineWidth`, `lineCap`, `lineJoin`, `setLineDash` | `strokePath`, `setLineWidth`, `setLineCap`, `setLineJoin`, `setLineDash(phase: 0, lengths:)` | `stroke(path, with:, style: StrokeStyle(lineWidth:, lineCap:, lineJoin:, dash:))` | |
| `clip()` | `clip()` | `clip(to:)` | |
| `fillRect / clearRect` | `fill(rect)` / `clear(rect)` | `fill(Path(rect))` / `blendMode = .clear` | |
| `createPattern(grain, 'repeat')` | `draw(image, in: tileRect, byTiling: true)` | `.tiledImage(Image, origin:, sourceRect:, scale:)` | |
| `createImageData / putImageData` (grain) | build a byte buffer, `CGImage(width:height:...provider:)` | | the grain bytes come from `rng(99)`: port exactly |
| `drawImage(layer, x, y)` | `draw(cgImage, in:)` (mind the flip) | `draw(Image(decorative:), in:)` | |
| `drawImage(src, sx, sy, sw, sh, dx, dy, dw, dh)` (reflection strips) | `image.cropping(to:)` then draw | Metal `layerEffect` (section 6) | |
| CSS `filter: blur()` (kinetic `blur` headline only) | | `.blur(radius:)` on the Text | the painters use no blur passes; softness is layered alpha |

## 6. Architecture, caching and performance

**Budget.** 120 Hz leaves 8.3 ms per frame. Keep Ridge at **at most 3 ms of main-thread work per card
frame and 5 ms per done-flow frame**, measured on an iPhone 12. Layer painting never happens on a
frame; it happens on a background queue and swaps in when ready.

**Static layers: Core Graphics, off the main thread.** Port the painters 1:1 against a thin
canvas-like wrapper over `CGContext` (skeleton below), so 2500 lines of `wash*.ts` translate almost
statement by statement. Paint each cached layer into a `CGImage` sized `design size x k x
displayScale` (story: cap the scale at 2 to bound memory). Cache by the same keys as the web. The card
needs about 10 layers of ~2 MB at 3x (mist layers are twice as wide): about 25 MB. The done flow at
2x is ~5 MB per layer; keep only the current world's layers and purge on memory warnings and when
the app backgrounds.

**Per-frame composition: GPU.** Do not composite eight full-size images on the CPU every frame. Build
the frame as a SwiftUI stack the render server composites:

```
ZStack {
  Image(sky); SunGlowCanvas; Image(far).offset(px * 0.4); Image(mist).offset(drift).opacity(mist)
  Image(near).offset(px); Image(rock).offset(px); Image(front).offset(drift2).opacity(...)
  DynamicCanvas            // rain, birds, world-specific dynamics, Painter3.overlay, paintShapes
  Image(paper).resizable(resizingMode: .tile).blendMode(light ? .multiply : .screen).opacity(light ? 0.55 : 0.3)
}
.transformEffect(cam.matrix scaled to points)   // the camera moves everything, like ctx.setTransform(xf)
.clipped()
// then, outside the camera: the left paper fade (LinearGradient), the note, the copy column
```

`DynamicCanvas` is one `Canvas` holding only vector work (tens of paths); add `.drawingGroup()` if
Instruments shows its rasterisation above ~1 ms.

**Reflections.** `reflect()` copies horizontal strips of what is already drawn, mirrored about the
waterline, each strip shifted by `sin(y * 0.09 + t * 1.6) * amp + sin(y * 0.031 - t * 0.9) * amp * 1.6`
with `amp = (1.2 + d * 0.035) * w / 1000`. SwiftUI cannot read back a Canvas. Wrap the above-water
part of the stack in a view and apply a Metal `layerEffect` shader that samples
`(x - off(y), wl - (y - wl) * 1.05 - step)` below the waterline (one function, ~15 lines of Metal,
`[[ stitchable ]]`), then draw the water gradient and ripple lines over it. The lake variant reads
the cached `above` layer, so it can also be done on the CPU by drawing cropped strips of that one
`CGImage`; the shader serves both.

**Layers whose key animates** (`rock` with `cracks`, `broken`, `rockIn`; `near` with `tree`; cairn
`stones`): the web repaints them per frame during the beat. Natively, either (a) pre-paint the beat's
key frames on the background queue when the state is entered (e.g. 16 steps of `cracks`, about 0.3 s
of work) and cross-fade between neighbours, or (b) move the animating part (the newest crack being
drawn, the growing tip) into `DynamicCanvas` as vector strokes over the last settled layer. Prefer
(b) for cracks and growth (cheap and exact); (a) for `broken` (the split boulder).

## 7. Determinism

Every random choice in Ridge comes from seeded generators. Port them bit-exactly (same 32-bit wrap
rules as `MatrixHash` in `MatrixEngine.swift`), and consume them **in the same order**: Swift
evaluates arguments and array literal elements left to right, like JS, so keep each `r()` call in the
same expression position (`cx = r() * w, cy = ...` stays one `let` per call, in order).

```swift
import Foundation

enum RidgeRandom {
    /// wash.ts `rng(seed)`: mulberry32 variant. `(seed * 2654435761) >>> 0 || 1`.
    struct Rng {
        private var s: UInt32
        init(_ seed: Double) {
            let s0 = JSMath.toUint32(seed * 2_654_435_761)
            s = s0 == 0 ? 1 : s0
        }
        mutating func next() -> Double {
            s = s &+ 0x6D2B_79F5
            var t = s
            t = (t ^ (t >> 15)) &* (t | 1)
            t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
            return Double(t ^ (t >> 14)) / 4_294_967_296
        }
    }

    /// wash.ts `gauss(r)`: Box-Muller, consumes two draws (u first, then v).
    static func gauss(_ r: inout Rng) -> Double {
        let u = max(1e-6, r.next()), v = r.next()
        return (-2 * log(u)).squareRoot() * cos(2 * Double.pi * v)
    }

    /// wash.ts `h1` (sin hash), `vn1` (value noise), `fbm1` (fractal noise, optionally ridged).
    static func h1(_ n: Double) -> Double {
        let x = sin(n * 127.1) * 43758.5453
        return x - x.rounded(.down)
    }
    static func vn1(_ x: Double) -> Double {
        let i = x.rounded(.down), f = x - i, u = f * f * (3 - 2 * f)
        return h1(i) + (h1(i + 1) - h1(i)) * u
    }
    static func fbm1(_ x: Double, _ oct: Int = 6, ridged: Bool = false) -> Double {
        var s = 0.0, a = 0.5, fq = 1.0, n = 0.0
        for i in 0..<oct {
            var v = vn1(x * fq + Double(i) * 17.3)
            if ridged { v = 1 - abs(v * 2 - 1) }
            s += v * a
            n += a
            a *= 0.5
            fq *= 2.07
        }
        return s / n
    }

    /// wash3.ts `rnd(i)` (k = 1000) and props13.ts `rnd(i)` (k = 997): integer avalanche hashes.
    static func rndK(_ i: Double, _ k: Double) -> Double {
        var x = UInt32(bitPattern: JSMath.toInt32((i * k).rounded(.down))) ^ 0x9E37_79B9
        x = (x ^ (x >> 16)) &* 0x85EB_CA6B
        x = (x ^ (x >> 13)) &* 0xC2B2_AE35
        return Double(x ^ (x >> 16)) / 4_294_967_296
    }
}
```

Note: `JSMath.toInt32` of `Math.floor(i * k)` then `^ 0x9e3779b9` in JS yields an int32 XOR, then
`>>> 0`; working on the `UInt32` bit pattern is equivalent. Verify `Rng`, `gauss`, `fbm1` and both
`rnd`s against Node with a golden script, exactly as for Matrix (`tools/matrix-golden.ts`).

`h1` and `fbm1` go through `sin`, which may differ from V8 by one ulp; the result moves by about
1e-11 and only matters at a `floor` boundary, which the prototype never relies on.

## 8. Swift skeletons

```swift
import SwiftUI

/// A canvas-like facade over CGContext so the painters port almost line by line.
/// Coordinates are design units; the init sets a y-down CTM scaled to device pixels.
final class RidgeCanvas {
    let cg: CGContext
    let width: Double, height: Double            // design units (1000 x 488 for the card)
    var globalAlpha: Double = 1 { didSet { cg.setAlpha(globalAlpha) } }
    var composite: CGBlendMode = .normal { didSet { cg.setBlendMode(composite) } }
    private var path = CGMutablePath()

    init?(width: Double, height: Double, pixelScale: Double) {
        let wpx = Int((width * pixelScale).rounded(.up)), hpx = Int((height * pixelScale).rounded(.up))
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let cg = CGContext(data: nil, width: wpx, height: hpx, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        cg.translateBy(x: 0, y: CGFloat(hpx))
        cg.scaleBy(x: pixelScale, y: -pixelScale)
        self.cg = cg
        self.width = width
        self.height = height
    }

    func save() { cg.saveGState() }
    func restore() { cg.restoreGState() }
    func beginPath() { path = CGMutablePath() }
    func moveTo(_ x: Double, _ y: Double) { path.move(to: CGPoint(x: x, y: y)) }
    func lineTo(_ x: Double, _ y: Double) { path.addLine(to: CGPoint(x: x, y: y)) }
    func quadraticCurveTo(_ cx: Double, _ cy: Double, _ x: Double, _ y: Double) { path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy)) }
    func arc(_ x: Double, _ y: Double, _ r: Double, _ a0: Double, _ a1: Double, anticlockwise: Bool = false) {
        path.addArc(center: CGPoint(x: x, y: y), radius: r, startAngle: a0, endAngle: a1, clockwise: anticlockwise)
    }
    func closePath() { path.closeSubpath() }
    func fill(_ color: CGColor) { cg.addPath(path); cg.setFillColor(color); cg.fillPath(using: .winding) }
    func stroke(_ color: CGColor, width: Double) { cg.addPath(path); cg.setStrokeColor(color); cg.setLineWidth(width); cg.strokePath() }
    func makeImage() -> CGImage? { cg.makeImage() }
    // ... fillRect, clearRect, gradients (clip + draw), drawImage, pattern tiling, setLineDash
}

/// One cached layer: a key and the CGImage painted for it.
struct RidgeLayer {
    let key: String
    let image: CGImage
}

/// Paints cached layers off the main thread and publishes them when ready.
@MainActor
final class RidgeLayerCache {
    private var layers: [String: RidgeLayer] = [:]          // slot -> layer
    private var pending: Set<String> = []                   // slot:key being painted
    private let queue = DispatchQueue(label: "ridge.paint", qos: .userInitiated)
    var onUpdate: (() -> Void)?

    /// Returns the current image for `slot` (possibly the previous key's while the new one paints).
    func image(_ slot: String, key: String, size: CGSize, scale: Double, paint: @escaping @Sendable (RidgeCanvas) -> Void) -> CGImage? {
        if let l = layers[slot], l.key == key { return l.image }
        let job = slot + ":" + key
        if !pending.contains(job) {
            pending.insert(job)
            let w = Double(size.width), h = Double(size.height)
            queue.async {
                guard let c = RidgeCanvas(width: w, height: h, pixelScale: scale) else { return }
                paint(c)
                let img = c.makeImage()
                Task { @MainActor in
                    self.pending.remove(job)
                    if let img { self.layers[slot] = RidgeLayer(key: key, image: img); self.onUpdate?() }
                }
            }
        }
        return layers[slot]?.image
    }

    func purge() { layers.removeAll() }
}

/// The scene parameters a painter reads (wash.ts Scene + wash2 Scene2 + wash3 Scene3), flattened.
struct RidgeScene: Equatable, Sendable {
    enum Kind: String, Sendable { case ridge, hourglass, night, beach, sunrise, path, fog, lake, sunset, cairn }
    var kind: Kind = .ridge
    var seed: Int = 17
    var tree = 0.0, cracks = 0.0, broken = 0.0, sun = 0.4, night = 0.0, mist = 0.8, rain = 0.0, peak = 1.0
    var rubble = 0
    var rockIn: Double? = nil
    var noRock = false
    var birds: Double? = nil
    // Scene2 / Scene3 extras: charge, moonX, moonY, boatX, sand, stones, trail, candle, snow, frozen,
    // fireflies, drip, tide, steps, beacon, lanterns, stars, starLines, shoot, skips, skipN, skipDone,
    // burst, burstAt, flash, ripples ...
}

enum RidgeTheme: String, Sendable { case light, dark }

/// One world painter (Painter for `ridge`, one per Painter2 kind).
@MainActor
protocol RidgeWorldPainter {
    /// The cached layers, back to front, with how each is placed this frame (offset, opacity, blend).
    func layers(scene: RidgeScene, theme: RidgeTheme, t: Double, size: CGSize, cache: RidgeLayerCache, scale: Double) -> [RidgePlacedLayer]
    /// Per-frame vector work for this world (sun disc, rain, birds, waves, sand), design units.
    func drawDynamic(_ ctx: inout GraphicsContext, scene: RidgeScene, theme: RidgeTheme, t: Double, size: CGSize)
}

struct RidgePlacedLayer: Identifiable {
    let id: String
    let image: CGImage
    var offset: CGSize = .zero
    var opacity: Double = 1
    var blend: BlendMode = .normal
    /// Insert the world's dynamic canvas after this layer (e.g. the sun between sky and far).
    var dynamicAfter = false
}

/// stage13.ts `Shape`, in stage units.
enum RidgeShape: Sendable {
    enum Mat: Sendable { case ink, mid, mist, light, coral, paper }
    case disc(x: Double, y: Double, r: Double, m: Mat, a: Double)
    case ring(x: Double, y: Double, r: Double, ry: Double?, m: Mat, a: Double, w: Double, a0: Double, a1: Double, dash: Double?)
    case line(p: [Double], m: Mat, a: Double, w: Double, dash: Double?)
    case poly(p: [Double], m: Mat, a: Double, soft: Bool)
    case dots(p: [Double], r: Double, m: Mat, a: Double)
    case glow(x: Double, y: Double, r: Double, m: Mat, a: Double)
    case flash(a: Double, m: Mat)
}
```

## 9. Recommended order of work

1. **Primitives and golden tests** (1 to 2 days): `Rng`, `gauss`, `h1`, `vn1`, `fbm1`, both `rnd`s,
   `deform`, `palette`, `mixc`, `css` rounding, `layoutFor`. Node golden script for sequences and for
   `deform` outputs. Nothing visual until these match.
2. **`RidgeCanvas` facade** and the grain texture (bytes from `rng(99)` + 70 fibres).
3. **`Painter` (ridge world)**: sky, far, near (pine growth), boulder, mist, front, paper; static
   frame compared with a web screenshot at the same `S` and `t` (render both at 1000 x 488 x 3).
4. **Composition view** (section 6) with layer cache, parallax and mist drift; measure in Instruments.
5. **Camera**: `RidgeCam`, `clampCam`, `frameOf`, `build()` push-in; reduce motion uses `.zero`.
6. **`paintShapes`** and the props table: port `props13.ts` scene by scene with the same mechanical
   rules as Matrix (PORTING-GUIDE.md); shapes are enums, `draw` returns `[RidgeShape]`.
7. **`Painter2` worlds**, one at a time, simplest first: fog, path, cairn, sunset, sunrise, beach,
   hourglass, then night and lake with the reflection shader.
8. **`Painter3.overlay`** features, in file order.
9. **Card copy** (DISPLAY = SF Pro Display 900; kinetic headline shared with Matrix), the left paper
   fade, the note.
10. **Done flow** (`story12.tsx`): `sceneAt` per screen, chips on the rock, copy; same flow model as
    `MatrixStoryModel` with `CFG_R` timings.

## 10. Conflicts with docs/UI-RULES.md to resolve with the owner before step 9

- The note uses a bundled handwriting font (Permanent Marker). UI-RULES bans bundled and handwriting
  fonts.
- Paper grain, washes and soft glows are textures and glows, which UI-RULES' anti-slop list bans for
  app chrome. The hero is art, not chrome, but get an explicit exception.
- Idle loops (mist drift, water shimmer, birds) conflict with "nothing loops". The prototype is
  built on them.
- Prototype copy is title case with curly quotes; UI-RULES wants lowercase chrome.

## Threading

- The card paints off the main thread on `RidgeRenderThread` (16 MB stack, newest job per card wins)
  and shows the newest finished image through `RidgeFrameSink`, one frame behind the clock.
- Everything the painter touches is `nonisolated`: `RW` and its generated extensions, the C2D canvas,
  `RScene`/`RCam`/`RShape`/`RPC`, `JS`, `JSMath`, `HapticCue`, `MatrixLiveData`. ts2swift emits
  `nonisolated extension RW {` and `nonisolated final class` so regenerated files keep this.
- The done flow's story still paints on main, so the shared caches (`palette`, `grain`, `frameOf`,
  `C2DColor.parse`) sit behind locks. Never hold those locks while painting.
