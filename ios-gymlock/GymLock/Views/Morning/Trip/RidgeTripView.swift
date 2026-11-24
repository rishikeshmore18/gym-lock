import CoreLocation
import MapKit
import SwiftUI

// MARK: - The Ridge trip screen
//
// A live black and white map on top, an ink-wash Ridge band straddling the
// map and the sheet, and a countdown sheet below. The climber on the band
// walks a switchback trail as `model.progress` grows; on arrival a dark
// scrim, confetti and a verification panel take over the screen.
//
// Ported from the approved HTML prototype (gymlock-trip-ridge.html). Band
// maths work in that prototype's 390 x 180 design space and are scaled to the
// screen width, so every number below matches the picture the owner approved.

// MARK: - Small maths

enum RidgeTripMath {
    static func clamp(_ value: Double, _ low: Double = 0, _ high: Double = 1) -> Double {
        min(high, max(low, value))
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    static func easeOut(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }

    /// A point `metres` away from `origin` along `bearing` (degrees from north).
    static func offset(_ origin: CLLocationCoordinate2D, metres: Double, bearing: Double) -> CLLocationCoordinate2D {
        let radians = bearing * Double.pi / 180
        let metresPerDegree = 111_320.0
        let dLat = metres * cos(radians) / metresPerDegree
        let cosLat = max(0.01, cos(origin.latitude * Double.pi / 180))
        let dLon = metres * sin(radians) / (metresPerDegree * cosLat)
        return CLLocationCoordinate2D(latitude: origin.latitude + dLat, longitude: origin.longitude + dLon)
    }
}

// MARK: - Layout

struct RidgeTripLayout {
    let width: CGFloat
    let height: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat

    /// The band is drawn in a 390 pt wide design space.
    var scale: CGFloat { width / 390 }
    var sheetHeight: CGFloat { 372 + bottomInset }
    var mapHeight: CGFloat { max(200, height - sheetHeight) }
    var sheetTop: CGFloat { height - sheetHeight }
    /// Where the 180 pt band starts, in this view's coordinates. Its bottom edge
    /// sits 63 pt below the sheet's top, as in the prototype.
    var bandTop: CGFloat { sheetTop + 63 - 180 * scale }
}

// MARK: - Trail geometry

struct RidgeTripSample {
    var s: Double
    var x: Double
    var y: Double
    var tx: Double
    var ty: Double
    var steep: Double
}

struct RidgeTripEffort {
    var s: Double
    var c: Double
    var raw: Double
    var steep: Double
    var leg: Int
    var pause: Int
    var phi: Double
}

struct RidgeTripPose {
    var s: Double
    var x: Double
    var y: Double
    var tx: Double
    var ty: Double
    var steep: Double
    var phi: Double
    var leg: Int
    var face: Double
    var turn: Double
    var paused: Bool
}

/// The switchback trail on the peak layer, built once. Direct port of the
/// prototype: rounded polyline, per-leg lit strips, effort table (steep
/// stretches cost more time, corners hold a pause) and whole hops per leg so
/// the climber is grounded at every corner.
final class RidgeTripTrail {
    static let shared = RidgeTripTrail()
    static let apex = CGPoint(x: 262.4, y: 8.4)
    static let dotPeriod: Double = 7.51
    static let legSigns: [Double] = [1, -1, 1, -1, 1]

    let samples: [RidgeTripSample]
    let points: [CGPoint]
    let length: Double
    let legs: [Double]
    let legPoints: [[CGPoint]]
    let efforts: [RidgeTripEffort]
    let totalCost: Double

    init() {
        let waypoints: [(x: Double, y: Double, r: Double)] = [
            (22, 138, 0), (64, 133, 22), (116, 134, 24), (158, 127, 22), (190, 122, 10),
            (318, 104, 5), (224, 88, 5), (290, 70, 5), (250, 50, 5), (262.4, 8.4, 0)
        ]

        // Rounded polyline.
        var poly: [CGPoint] = [CGPoint(x: waypoints[0].x, y: waypoints[0].y)]
        for i in 1..<(waypoints.count - 1) {
            let cur = waypoints[i]
            let prev = waypoints[i - 1]
            let next = waypoints[i + 1]
            let l1 = max(0.001, hypot(prev.x - cur.x, prev.y - cur.y))
            let l2 = max(0.001, hypot(next.x - cur.x, next.y - cur.y))
            let r1 = min(cur.r, l1 * 0.45)
            let r2 = min(cur.r, l2 * 0.45)
            let ax = cur.x + (prev.x - cur.x) / l1 * r1
            let ay = cur.y + (prev.y - cur.y) / l1 * r1
            let bx = cur.x + (next.x - cur.x) / l2 * r2
            let by = cur.y + (next.y - cur.y) / l2 * r2
            poly.append(CGPoint(x: ax, y: ay))
            for k in 1...10 {
                let t = Double(k) / 10
                let m = 1 - t
                let px = m * m * ax + 2 * m * t * cur.x + t * t * bx
                let py = m * m * ay + 2 * m * t * cur.y + t * t * by
                poly.append(CGPoint(x: px, y: py))
            }
        }
        let lastWaypoint = waypoints[waypoints.count - 1]
        poly.append(CGPoint(x: lastWaypoint.x, y: lastWaypoint.y))

        var cumulative: [Double] = [0]
        for i in 1..<poly.count {
            let step = hypot(Double(poly[i].x - poly[i - 1].x), Double(poly[i].y - poly[i - 1].y))
            cumulative.append(cumulative[i - 1] + step)
        }
        let total = max(1, cumulative[cumulative.count - 1])

        func pointAt(_ distance: Double) -> CGPoint {
            let q = min(max(distance, 0), total)
            var lo = 0
            var hi = cumulative.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if cumulative[mid] <= q { lo = mid } else { hi = mid }
            }
            let span = cumulative[hi] - cumulative[lo]
            let t = span > 0 ? (q - cumulative[lo]) / span : 0
            let x = Double(poly[lo].x) + Double(poly[hi].x - poly[lo].x) * t
            let y = Double(poly[lo].y) + Double(poly[hi].y - poly[lo].y) * t
            return CGPoint(x: x, y: y)
        }

        // Resample every 1.2 units with tangent and steepness.
        let sampleCount = max(1, Int(ceil(total / 1.2)))
        var sampled: [RidgeTripSample] = []
        for i in 0...sampleCount {
            let s = total * Double(i) / Double(sampleCount)
            let a = pointAt(max(0, s - 2))
            let b = pointAt(min(total, s + 2))
            let p = pointAt(s)
            var l = hypot(Double(b.x - a.x), Double(b.y - a.y))
            if l == 0 { l = 1 }
            let dx = Double(b.x - a.x) / l
            let dy = Double(b.y - a.y) / l
            let steep = min(1, max(0, (-dy) / 0.5))
            sampled.append(RidgeTripSample(s: s, x: Double(p.x), y: Double(p.y), tx: dx, ty: dy, steep: steep))
        }

        // Switchback corners: waypoints 5...8.
        var corners: [Int] = []
        for waypointIndex in [5, 6, 7, 8] {
            var best = 0
            var bestDistance = Double.greatestFiniteMagnitude
            for (i, q) in sampled.enumerated() {
                let d = hypot(q.x - waypoints[waypointIndex].x, q.y - waypoints[waypointIndex].y)
                if d < bestDistance {
                    bestDistance = d
                    best = i
                }
            }
            corners.append(best)
        }
        var legBounds: [Double] = [0]
        for index in corners { legBounds.append(sampled[index].s) }
        legBounds.append(total)

        // Effort table: steep costs more, corners pause, hops land on corners.
        let pauseCost = 26.0
        let stepsFlat = 11.0
        let stepsSteep = 5.0
        var table: [RidgeTripEffort] = []
        var cost = 0.0
        var leg = 0
        var raw = 0.0
        var legRaw: [Double] = []
        for i in 0...sampleCount {
            let q = sampled[i]
            if i > 0 {
                let ds = q.s - sampled[i - 1].s
                let st = (q.steep + sampled[i - 1].steep) / 2
                cost += ds * (1 + 3 * st)
                raw += ds / RidgeTripMath.lerp(stepsFlat, stepsSteep, st)
            }
            table.append(RidgeTripEffort(s: q.s, c: cost, raw: raw, steep: q.steep, leg: leg, pause: -1, phi: 0))
            if let k = corners.firstIndex(of: i) {
                legRaw.append(raw)
                cost += pauseCost
                table.append(RidgeTripEffort(s: q.s, c: cost, raw: raw, steep: q.steep, leg: leg, pause: k, phi: 0))
                leg += 1
            }
        }
        legRaw.append(raw)

        var hopLegs: [(r0: Double, r1: Double, base: Double, n: Double)] = []
        var previousRaw = 0.0
        var base = 0.0
        for r in legRaw {
            let n = max(1.0, (r - previousRaw).rounded())
            hopLegs.append((r0: previousRaw, r1: r, base: base, n: n))
            base += n
            previousRaw = r
        }
        for i in 0..<table.count {
            var chosen = hopLegs[hopLegs.count - 1]
            for candidate in hopLegs where table[i].raw <= candidate.r1 + 1e-9 {
                chosen = candidate
                break
            }
            let span = chosen.r1 - chosen.r0
            table[i].phi = chosen.base + (table[i].raw - chosen.r0) / (span == 0 ? 1 : span) * chosen.n
        }

        // Per-leg strips for the lit dots.
        var strips: [[CGPoint]] = []
        for i in 0..<5 {
            var strip: [CGPoint] = []
            for q in sampled where q.s >= legBounds[i] - 1e-6 && q.s <= legBounds[i + 1] + 1e-6 {
                strip.append(CGPoint(x: q.x, y: q.y))
            }
            strips.append(strip)
        }

        self.samples = sampled
        self.points = sampled.map { CGPoint(x: $0.x, y: $0.y) }
        self.length = total
        self.legs = legBounds
        self.legPoints = strips
        self.efforts = table
        self.totalCost = max(1, table[table.count - 1].c)
    }

    func pose(at progress: Double) -> RidgeTripPose {
        let t = RidgeTripMath.clamp(progress) * totalCost
        var lo = 0
        var hi = efforts.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if efforts[mid].c <= t { lo = mid } else { hi = mid }
        }
        let a = efforts[lo]
        let b = efforts[hi]
        let span = b.c - a.c
        let f = RidgeTripMath.clamp((t - a.c) / (span == 0 ? 1 : span))
        let paused = b.s == a.s && b.pause >= 0
        let s = RidgeTripMath.lerp(a.s, b.s, f)
        let index = min(samples.count - 1, max(0, Int((s / length * Double(samples.count - 1)).rounded())))
        let q = samples[index]

        let signs = RidgeTripTrail.legSigns
        var face = signs[min(4, paused ? b.pause : a.leg)]
        if paused {
            let next = signs[min(4, b.pause + 1)]
            face = RidgeTripMath.lerp(signs[min(4, b.pause)], next, RidgeTripMath.easeInOut(f))
        }
        return RidgeTripPose(
            s: s, x: q.x, y: q.y, tx: q.tx, ty: q.ty,
            steep: RidgeTripMath.lerp(a.steep, b.steep, f),
            phi: RidgeTripMath.lerp(a.phi, b.phi, f),
            leg: paused ? b.pause + 1 : a.leg,
            face: face,
            turn: paused ? sin(Double.pi * f) : 0,
            paused: paused
        )
    }

    /// The trail points from the start up to `distance`, ending exactly there.
    func points(upTo distance: Double) -> [CGPoint] {
        var result: [CGPoint] = []
        for q in samples {
            if q.s <= distance {
                result.append(CGPoint(x: q.x, y: q.y))
            } else {
                break
            }
        }
        return result
    }
}

// MARK: - Layers

struct RidgeTripLayerSpec {
    let name: String
    let amplitude: Double
    let partShift: Double
    let widthFactor: Double
    /// Image height over width, from the asset files.
    let ratio: Double
    let isMist: Bool
    let driftPeriod: Double
    let driftReverse: Bool

    static let all: [RidgeTripLayerSpec] = [
        RidgeTripLayerSpec(name: "ridge_day_far", amplitude: 6, partShift: 0, widthFactor: 1.08, ratio: 800.0 / 1600.0, isMist: false, driftPeriod: 0, driftReverse: false),
        RidgeTripLayerSpec(name: "ridge_day_mid", amplitude: 10, partShift: 0, widthFactor: 1.08, ratio: 1280.0 / 1600.0, isMist: false, driftPeriod: 0, driftReverse: false),
        RidgeTripLayerSpec(name: "ridge_day_mist0", amplitude: 14, partShift: -18, widthFactor: 1.3, ratio: 123.0 / 512.0, isMist: true, driftPeriod: 22, driftReverse: false),
        RidgeTripLayerSpec(name: "ridge_day_near", amplitude: 15, partShift: 0, widthFactor: 1.08, ratio: 1280.0 / 1600.0, isMist: false, driftPeriod: 0, driftReverse: false),
        RidgeTripLayerSpec(name: "ridge_day_mist1", amplitude: 18, partShift: 18, widthFactor: 1.3, ratio: 107.0 / 512.0, isMist: true, driftPeriod: 30, driftReverse: true),
        RidgeTripLayerSpec(name: "ridge_day_peak", amplitude: 0, partShift: 0, widthFactor: 1.08, ratio: 888.0 / 1600.0, isMist: false, driftPeriod: 0, driftReverse: false),
        RidgeTripLayerSpec(name: "ridge_day_mist2", amplitude: 22, partShift: -14, widthFactor: 1.3, ratio: 98.0 / 512.0, isMist: true, driftPeriod: 22, driftReverse: false),
        RidgeTripLayerSpec(name: "ridge_day_fg", amplitude: 30, partShift: 0, widthFactor: 1.08, ratio: 256.0 / 1600.0, isMist: false, driftPeriod: 0, driftReverse: false)
    ]
}

// MARK: - Band simulation

struct RidgeTripSpark {
    var x: Double = 0
    var y: Double = 0
    var vx: Double = 0
    var vy: Double = 0
    var born: Double = -1_000_000_000
}

struct RidgeTripMark {
    var x: Double
    var y: Double
    var r: Double
    var alpha: Double
}

/// Everything the band draws for one frame.
struct RidgeTripSnap {
    var layerX: [Double]
    var mistOpacity: Double
    var glow: Double
    var zoom: Double
    var camX: Double
    var camY: Double
    var pose: RidgeTripPose
    var lit: [Double]
    var hop: Double
    var idle: Double
    var squashX: Double
    var squashY: Double
    var flag: Double
    var now: Double
    var reduceMotion: Bool
    var footprints: [RidgeTripMark]
    var dust: [RidgeTripMark]
}

/// The band's smoothed state (parallax, zoom, hops, dust, flag). A plain
/// reference type: it is stepped from inside the band's `TimelineView` and
/// never read by SwiftUI's dependency tracking.
final class RidgeTripBandSim {
    private let trail = RidgeTripTrail.shared
    private var lastNow: Double?
    private var primed = false
    private var shown = 0.0
    private var zoom = 1.0
    private var part = 0.0
    private var glow = 0.0
    private var flag = 0.0
    private var moving = 0.0
    private var lit = [Double](repeating: 0, count: 5)
    private var lastStep = 0
    private var lastS = 0.0
    private var arrivedAt: Double?
    private var footprints = [RidgeTripSpark](repeating: RidgeTripSpark(), count: 10)
    private var dust = [RidgeTripSpark](repeating: RidgeTripSpark(), count: 12)
    private var footprintIndex = 0
    private var dustIndex = 0

    func step(now: Double, progress: Double, phase: TripPhase, reduceMotion: Bool) -> RidgeTripSnap {
        let isHome = phase == .atHome
        let isArrived = phase == .verifying || phase == .verified
        var dt = 0.0
        if let last = lastNow { dt = min(0.05, max(0, now - last)) }
        lastNow = now
        let p = RidgeTripMath.clamp(progress)

        // The climber eases toward the real progress so a GPS step becomes a
        // short walk; a big jump (app opened mid trip) snaps.
        var jumped = false
        if !primed {
            shown = p
            jumped = true
        } else {
            let diff = p - shown
            if abs(diff) > 0.12 {
                shown = p
                jumped = true
            } else {
                shown += diff * (1 - exp(-dt * 1.4))
            }
        }

        func smooth(_ rate: Double) -> Double { 1 - exp(-dt * rate) }

        part += ((isHome ? 0 : 1) - part) * smooth(2.2)
        glow += ((isArrived ? 1 : 0) - glow) * smooth(2)

        let pose = trail.pose(at: shown)
        let u = pose.s / trail.length
        let alt = RidgeTripMath.clamp((u - 0.3) / 0.7)

        // Layer positions: parallax by progress, mists part and drift.
        let specs = RidgeTripLayerSpec.all
        var layerX: [Double] = []
        for spec in specs {
            var x = 0.0
            if !reduceMotion {
                x = (0.5 - shown) * spec.amplitude + spec.partShift * (part + 0.9 * alt)
                if spec.isMist && spec.driftPeriod > 0 {
                    let wave = cos(Double.pi * now / spec.driftPeriod)
                    x += (spec.driftReverse ? 14 : -14) * wave
                }
            }
            layerX.append(x)
        }
        let mistOpacity = 1 - 0.5 * part - 0.22 * alt

        // Band camera: zooms toward the climber.
        let zoomTarget = reduceMotion ? 1 : 1 + 0.12 * pow(u, 1.1)
        if jumped || !primed || reduceMotion {
            zoom = zoomTarget
        } else {
            zoom += (zoomTarget - zoom) * smooth(3.5)
        }
        let blend = 0.6 * (zoom - 1) / 0.12
        let camX = RidgeTripMath.clamp(RidgeTripMath.lerp(pose.x, 205, blend) - zoom * pose.x, 390 * (1 - zoom), 0)
        let camY = 180 * (1 - zoom) * 0.55

        // Current leg lights up.
        let currentLeg = isHome ? -1 : min(4, pose.leg)
        for i in 0..<lit.count {
            let on = i == currentLeg
            lit[i] += ((on ? 1 : 0) - lit[i]) * smooth(on ? 2.6 : 5)
        }

        // The climber: hops, grounded at every corner.
        let isMoving = abs(pose.s - lastS) > 0.02
        lastS = pose.s
        moving += (((isMoving && !reduceMotion) ? 1 : 0) - moving) * smooth(isMoving ? 18 : 9)
        let floorStep = Int(floor(pose.phi + 1e-6))
        let deltaStep = floorStep - lastStep
        lastStep = floorStep
        if primed && deltaStep == 1 && isMoving && !jumped && !reduceMotion {
            land(pose: pose, now: now)
        }
        let phase01 = pose.phi - floor(pose.phi)
        let hop = abs(sin(Double.pi * phase01)) * RidgeTripMath.lerp(3.4, 1.4, pose.steep) * moving
        let idle = (reduceMotion || !isHome) ? 0 : sin(now * 1000 / 520) * 0.5

        // Summit flag: furled until arrival, then unfurls.
        if isArrived {
            let start = arrivedAt ?? (primed ? now : now - 10)
            arrivedAt = start
            flag = reduceMotion ? 1 : RidgeTripMath.easeOut(RidgeTripMath.clamp((now - start - 0.35) / 1.1))
        } else {
            arrivedAt = nil
            flag += (0 - flag) * smooth(6)
        }

        primed = true

        var marks: [RidgeTripMark] = []
        for f in footprints {
            let a = (now - f.born) / 1.7
            if a >= 0 && a < 1 {
                marks.append(RidgeTripMark(x: f.x, y: f.y, r: 0.9, alpha: 0.6 * (1 - a)))
            }
        }
        var puffs: [RidgeTripMark] = []
        for d in dust {
            let a = (now - d.born) / 0.56
            if a >= 0 && a < 1 {
                let e = RidgeTripMath.easeOut(a)
                puffs.append(RidgeTripMark(x: d.x + d.vx * e, y: d.y + d.vy * e, r: 0.8 + e * 1.3, alpha: 0.55 * (1 - a)))
            }
        }

        return RidgeTripSnap(
            layerX: layerX, mistOpacity: mistOpacity, glow: glow, zoom: zoom,
            camX: camX, camY: camY, pose: pose, lit: lit, hop: hop, idle: idle,
            squashX: 1 + 0.12 * pose.turn, squashY: 1 - 0.1 * pose.turn,
            flag: flag, now: now, reduceMotion: reduceMotion,
            footprints: marks, dust: puffs
        )
    }

    private func land(pose: RidgeTripPose, now: Double) {
        let side: Double = (Int(floor(pose.phi)) % 2 != 0 ? 1 : -1) * 1.7
        var print = footprints[footprintIndex % footprints.count]
        footprintIndex += 1
        print.born = now
        print.x = pose.x - pose.ty * side
        print.y = pose.y + pose.tx * side
        footprints[(footprintIndex - 1) % footprints.count] = print

        if pose.steep > 0.45 {
            let direction: Double = pose.tx == 0 ? 1 : (pose.tx > 0 ? 1 : -1)
            for k in 0..<3 {
                let kd = Double(k)
                var puff = RidgeTripSpark()
                puff.born = now
                puff.x = pose.x
                puff.y = pose.y - 0.5
                puff.vx = -direction * (5 + kd * 5) + (kd - 1) * 2
                puff.vy = -(3 + kd * 2.5)
                dust[dustIndex % dust.count] = puff
                dustIndex += 1
            }
        }
    }
}

// MARK: - Small shapes

private struct RidgeTripCone: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 100
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 50 * s, y: rect.minY + 96 * s))
        path.addLine(to: CGPoint(x: rect.minX + 14 * s, y: rect.minY + 12 * s))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + 86 * s, y: rect.minY + 12 * s),
            control: CGPoint(x: rect.minX + 50 * s, y: rect.minY - 4 * s)
        )
        path.closeSubpath()
        return path
    }
}

private struct RidgeTripPinTip: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct RidgeTripCheck: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 56
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 18 * s, y: rect.minY + 29.5 * s))
        path.addLine(to: CGPoint(x: rect.minX + 25.5 * s, y: rect.minY + 37 * s))
        path.addLine(to: CGPoint(x: rect.minX + 39 * s, y: rect.minY + 21 * s))
        return path
    }
}

// MARK: - The user's puck

private struct RidgeTripPuck: View {
    let heading: Double
    let showsCone: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            if showsCone {
                cone
            }
            halo
            dot
        }
        .frame(width: 24, height: 24)
    }

    private var cone: some View {
        RidgeTripCone()
            .fill(
                RadialGradient(
                    colors: [Theme.accent.opacity(0.5), Theme.accent.opacity(0)],
                    center: UnitPoint(x: 0.5, y: 0.96),
                    startRadius: 0,
                    endRadius: 96
                )
            )
            .frame(width: 100, height: 100)
            .rotationEffect(.degrees(heading), anchor: UnitPoint(x: 0.5, y: 0.96))
            .offset(y: -46)
    }

    @ViewBuilder
    private var halo: some View {
        if reduceMotion {
            Circle().fill(Theme.accent).opacity(0.2).frame(width: 24, height: 24)
        } else {
            // The one live signal on this screen: a calm location pulse.
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 24, height: 24)
                    .scaleEffect(0.9 + 1.7 * t)
                    .opacity(0.35 * (1 - t))
            }
        }
    }

    private var dot: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 18, height: 18)
            .padding(3)
            .background(Circle().fill(Color.white))
            .shadow(color: Color.black.opacity(0.25), radius: 3, y: 1)
    }
}

// MARK: - The ridge band

private struct RidgeTripBand: View {
    let model: TripModel
    let phase: TripPhase
    let scale: CGFloat
    let layersIn: Bool
    let reduceMotion: Bool

    @State private var sim = RidgeTripBandSim()

    /// Where the summit flag sits in the parent's coordinates, for the confetti.
    static func summitPoint(layout: RidgeTripLayout, reduceMotion: Bool) -> CGPoint {
        let zoom = reduceMotion ? 1.0 : 1.12
        let apex = RidgeTripTrail.apex
        let blend = 0.6 * (zoom - 1) / 0.12
        let camX = RidgeTripMath.clamp(RidgeTripMath.lerp(Double(apex.x), 205, blend) - zoom * Double(apex.x), 390 * (1 - zoom), 0)
        let camY = 180 * (1 - zoom) * 0.55
        let x = camX + zoom * Double(apex.x)
        let y = camY + zoom * -5
        return CGPoint(x: CGFloat(x) * layout.scale, y: layout.bandTop + CGFloat(y) * layout.scale)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let snap = sim.step(
                now: timeline.date.timeIntervalSinceReferenceDate,
                progress: model.progress,
                phase: phase,
                reduceMotion: reduceMotion
            )
            bandContent(snap)
        }
        .frame(width: 390 * scale, height: 180 * scale, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func bandContent(_ snap: RidgeTripSnap) -> some View {
        ZStack(alignment: .topLeading) {
            layerStack(snap)
                .frame(width: 390, height: 180, alignment: .bottom)
                .scaleEffect(CGFloat(snap.zoom), anchor: .topLeading)
                .offset(x: CGFloat(snap.camX), y: CGFloat(snap.camY))
            bandFade
            trailCanvas(snap)
                .frame(width: 390, height: 260)
                .frame(width: 390, height: 180, alignment: .bottom)
                .scaleEffect(CGFloat(snap.zoom), anchor: .topLeading)
                .offset(x: CGFloat(snap.camX), y: CGFloat(snap.camY))
                .opacity(layersIn ? 1 : 0)
                .animation(reduceMotion ? Animation.easeOut(duration: 0.6) : Animation.easeOut(duration: 0.8).delay(0.9), value: layersIn)
        }
        .frame(width: 390, height: 180, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: 390 * scale, height: 180 * scale, alignment: .topLeading)
    }

    private var bandFade: some View {
        LinearGradient(
            stops: [
                .init(color: Theme.canvas.opacity(0), location: 0),
                .init(color: Theme.canvas.opacity(0.88), location: 0.55),
                .init(color: Theme.canvas, location: 0.85),
                .init(color: Theme.canvas, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: 390, height: 50)
        .frame(width: 390, height: 180, alignment: .bottom)
        .offset(y: 2)
    }

    // MARK: Layers

    private func layerStack(_ snap: RidgeTripSnap) -> some View {
        ZStack(alignment: .bottom) {
            ridgeLayer(0, snap)
            ridgeLayer(1, snap)
            ridgeLayer(2, snap)
            ridgeLayer(3, snap)
            ridgeLayer(4, snap)
            ridgeLayer(5, snap)
            glowView(snap)
            ridgeLayer(6, snap)
            ridgeLayer(7, snap)
        }
    }

    private func ridgeLayer(_ index: Int, _ snap: RidgeTripSnap) -> some View {
        let spec = RidgeTripLayerSpec.all[index]
        let width = CGFloat(390 * spec.widthFactor)
        let height = width * CGFloat(spec.ratio)
        let visible: Double = spec.isMist ? snap.mistOpacity : 1
        let delay: Double = reduceMotion ? 0 : Double(index) * 0.07
        let entry: Animation = reduceMotion
            ? Animation.easeOut(duration: 0.6)
            : Animation.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.9).delay(delay)
        return Image(spec.name)
            .resizable()
            .frame(width: width, height: height)
            .opacity(layersIn ? visible : 0)
            .offset(x: CGFloat(snap.layerX[index]), y: (layersIn || reduceMotion) ? 0 : 34)
            .animation(entry, value: layersIn)
    }

    private func glowView(_ snap: RidgeTripSnap) -> some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.95), Color.white.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 59.4
                    )
                )
                .frame(width: 180, height: 180)
                .offset(x: 172, y: -54)
                .opacity(snap.glow * 0.9)
        }
        .frame(width: 390, height: 180, alignment: .topLeading)
    }

    // MARK: Trail

    private func trailCanvas(_ snap: RidgeTripSnap) -> some View {
        Canvas { context, _ in
            var ctx = context
            drawTrail(&ctx, snap)
        }
    }

    private func drawTrail(_ ctx: inout GraphicsContext, _ snap: RidgeTripSnap) {
        // The canvas reaches 80 above the band so the flag and hops are not cut.
        ctx.translateBy(x: 0, y: 80)
        let trail = RidgeTripTrail.shared
        let ink = Theme.ink
        let grey = Color(white: 0.54)
        let pose = snap.pose

        // Ahead of the climber: dotted grey.
        var full = Path()
        full.addLines(trail.points)
        ctx.stroke(
            full,
            with: .color(grey.opacity(0.9)),
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.01, 7.5])
        )

        // The current leg lights up.
        for i in 0..<trail.legPoints.count {
            let strip = trail.legPoints[i]
            let value = i < snap.lit.count ? snap.lit[i] : 0
            if value > 0.01 && strip.count > 1 {
                var path = Path()
                path.addLines(strip)
                let phaseOffset = trail.legs[i].truncatingRemainder(dividingBy: RidgeTripTrail.dotPeriod)
                ctx.stroke(
                    path,
                    with: .color(ink.opacity(value * 0.85)),
                    style: StrokeStyle(lineWidth: 2.1, lineCap: .round, dash: [0.01, CGFloat(RidgeTripTrail.dotPeriod)], dashPhase: CGFloat(phaseOffset))
                )
            }
        }

        // Climbed part: solid ink.
        if pose.s > 0.6 {
            var done = trail.points(upTo: pose.s)
            done.append(CGPoint(x: pose.x, y: pose.y))
            if done.count > 1 {
                var path = Path()
                path.addLines(done)
                ctx.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }

        // Footprints.
        for mark in snap.footprints {
            let rect = CGRect(x: mark.x - mark.r, y: mark.y - mark.r, width: mark.r * 2, height: mark.r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(grey.opacity(mark.alpha)))
        }

        drawFlag(&ctx, snap)

        // Dust puffs on steep legs.
        for mark in snap.dust {
            let rect = CGRect(x: mark.x - mark.r, y: mark.y - mark.r, width: mark.r * 2, height: mark.r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(Color(white: 0.6).opacity(mark.alpha)))
        }

        // The climber.
        let rx = 4.2 - snap.hop * 0.35
        let shadowRect = CGRect(x: pose.x - rx, y: pose.y - 1.2, width: rx * 2, height: 2.4)
        ctx.fill(Path(ellipseIn: shadowRect), with: .color(ink.opacity(0.18 - snap.hop * 0.03)))

        var body = ctx
        body.translateBy(x: CGFloat(pose.x), y: CGFloat(pose.y - 3.2 - snap.hop - snap.idle))
        body.scaleBy(x: CGFloat(snap.squashX), y: CGFloat(snap.squashY))
        let ball = Path(ellipseIn: CGRect(x: -5.2, y: -5.2, width: 10.4, height: 10.4))
        body.fill(ball, with: .color(ink))
        body.stroke(ball, with: .color(Color.white), lineWidth: 2.4)
        let faceRect = CGRect(x: 2.3 * pose.face - 1.05, y: -1.2 - 1.05, width: 2.1, height: 2.1)
        body.fill(Path(ellipseIn: faceRect), with: .color(Color.white.opacity(0.85)))
    }

    private func drawFlag(_ ctx: inout GraphicsContext, _ snap: RidgeTripSnap) {
        let apex = RidgeTripTrail.apex
        let ink = Theme.ink
        var pole = Path()
        pole.move(to: CGPoint(x: apex.x, y: 9))
        pole.addLine(to: CGPoint(x: apex.x, y: -7))
        ctx.stroke(pole, with: .color(ink), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))

        let fu = snap.flag
        let w = RidgeTripMath.lerp(1.1, 9.5, fu)
        let h = 5.0
        let x0 = Double(apex.x) + 0.6
        let y0 = -7.0
        let amp = snap.reduceMotion ? 0 : fu * (1.0 + 0.5 * fu)
        let t = snap.now
        var top: [CGPoint] = []
        var bottom: [CGPoint] = []
        for i in 0...6 {
            let q = Double(i) / 6
            let wave = sin(t * 5 - q * 5) * amp * q
            let x = x0 + w * q
            top.append(CGPoint(x: x, y: y0 + wave))
            let flutter = snap.reduceMotion ? 0 : sin(t * 5.5 - q * 5 + 1) * 0.3 * fu * q
            bottom.append(CGPoint(x: x, y: y0 + h * RidgeTripMath.lerp(1.45, 1, fu) + wave + flutter))
        }
        var cloth = Path()
        cloth.move(to: top[0])
        for point in top.dropFirst() { cloth.addLine(to: point) }
        for point in bottom.reversed() { cloth.addLine(to: point) }
        cloth.closeSubpath()
        ctx.fill(cloth, with: .color(ink))
    }
}

// MARK: - Verification panel

private struct RidgeTripVerifyPanel: View {
    let trip: TripFrame
    let reduceMotion: Bool
    let onTrouble: () -> Void

    @State private var checkTrim: CGFloat = 0

    private var verified: Bool { trip.phase == .verified }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(TripCopy.youreHere)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            TimelineView(.animation(paused: verified)) { timeline in
                progressBlock(timeline.date)
            }
            Text(verified ? TripCopy.unlocked : TripCopy.stayInside)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 40, alignment: .topLeading)
                .padding(.top, 10)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.3), value: verified)
            Button {
                onTrouble()
            } label: {
                Text(TripCopy.trouble)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .opacity(verified ? 0 : 1)
            .allowsHitTesting(!verified)
            .animation(.easeOut(duration: 0.3), value: verified)
        }
        .onChange(of: verified) { _, isVerified in
            guard isVerified else { return }
            if reduceMotion {
                checkTrim = 1
            } else {
                withAnimation(.timingCurve(0.4, 0.1, 0.2, 1, duration: 0.5).delay(0.45)) {
                    checkTrim = 1
                }
            }
        }
        .onAppear {
            if verified { checkTrim = 1 }
        }
        .accessibilityElement(children: .contain)
    }

    private func progressBlock(_ date: Date) -> some View {
        let progress = min(1, max(0, trip.verifyProgress(date)))
        let seconds = trip.verifySecondsLeft(at: date)
        let dotCount = reduceMotion ? 3 : 1 + Int(date.timeIntervalSinceReferenceDate / 0.38) % 3
        let dots = String(repeating: ".", count: dotCount)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(verified ? TripCopy.verified : TripCopy.verifying)
                    Text(verified ? "" : dots)
                        .frame(width: 22, alignment: .leading)
                }
                .foregroundStyle(Color.white.opacity(0.8))
                Spacer(minLength: 8)
                Text(TripFormat.short(seconds))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .opacity(verified ? 0 : 1)
                    .animation(.easeOut(duration: 0.3), value: verified)
            }
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .padding(.top, 26)
            bar(progress: progress)
                .frame(height: 56)
                .padding(.top, 6)
        }
    }

    private func bar(progress: Double) -> some View {
        GeometryReader { geo in
            let fullWidth = geo.size.width
            let barWidth: CGFloat = verified ? 56 : fullWidth
            let barHeight: CGFloat = verified ? 56 : 18
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Rectangle()
                    .fill(Color.white)
                    .frame(width: barWidth * CGFloat(progress))
                    .opacity(verified ? 0 : 1)
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .opacity(verified ? 1 : 0)
                RidgeTripCheck()
                    .trim(from: 0, to: checkTrim)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 56, height: 56)
                    .frame(width: barWidth, height: barHeight)
                    .opacity(verified ? 1 : 0)
            }
            .frame(width: barWidth, height: barHeight)
            .clipShape(Capsule())
            .animation(
                reduceMotion ? Animation.easeOut(duration: 0.2) : Animation.timingCurve(0.5, 0, 0.2, 1, duration: 0.55),
                value: verified
            )
            .frame(width: fullWidth, height: geo.size.height, alignment: .center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(verified ? TripCopy.verified : TripCopy.verifying)
    }
}

// MARK: - RidgeTripView

struct RidgeTripView: View {
    let model: TripModel
    let frame: TripFrame
    let actions: TripActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var camera: MapCameraPosition
    @State private var isFollowing = true
    @State private var is3D = true
    @State private var entryPlayed = false
    @State private var entryDone = false
    @State private var sheetIn = false
    @State private var layersIn = false
    @State private var controlsIn = false
    @State private var mapShown = true
    @State private var mapTick = 0
    @State private var cameraHeading: Double = 0
    @State private var burst: TripConfetti.Burst?
    @State private var burstCount = 0
    @State private var finaleCalled = false

    init(model: TripModel, frame: TripFrame, actions: TripActions) {
        self.model = model
        self.frame = frame
        self.actions = actions
        let start = MapCamera(centerCoordinate: model.gym, distance: 2_500, heading: 0, pitch: 0)
        _camera = State(initialValue: MapCameraPosition.camera(start))
    }

    private var isArrival: Bool {
        frame.phase == .verifying || frame.phase == .verified
    }

    private var followKey: [Double] {
        let user = model.user
        return [
            user?.latitude ?? 0,
            user?.longitude ?? 0,
            model.heading.rounded(),
            isArrival ? 1 : 0
        ]
    }

    var body: some View {
        GeometryReader { geo in
            let layout = RidgeTripLayout(
                width: geo.size.width,
                height: geo.size.height,
                topInset: max(0, geo.safeAreaInsets.top),
                bottomInset: max(0, geo.safeAreaInsets.bottom)
            )
            screen(layout)
        }
        .ignoresSafeArea()
        .background(Theme.canvas)
        .task(id: frame.entryStarted) { await playEntry() }
        .task(id: frame.phase == .verified) { await runFinale() }
        .onChange(of: followKey) { _, _ in updateFollow() }
        .onChange(of: is3D) { _, _ in updateFollow() }
        .onChange(of: isArrival) { _, _ in
            isFollowing = true
            updateFollow()
        }
    }

    private func screen(_ layout: RidgeTripLayout) -> some View {
        ZStack(alignment: .topLeading) {
            Theme.canvas
            mapLayer(layout)
            sheetLayer(layout)
            chromeLayer(layout)
            arrivalLayer(layout)
            TripConfetti(look: .paper, burst: burst)
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
        .onChange(of: frame.phase) { old, new in
            handlePhaseChange(from: old, to: new, layout: layout)
        }
    }

    // MARK: Map

    private func mapLayer(_ layout: RidgeTripLayout) -> some View {
        ZStack(alignment: .top) {
            mapReader
            LinearGradient(
                colors: [Theme.canvas.opacity(0.9), Theme.canvas.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: layout.topInset + 70)
            .frame(maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
            // The approved Ridge exception: the map melts into the canvas
            // behind the band.
            LinearGradient(
                stops: [
                    .init(color: Theme.canvas.opacity(0), location: 0),
                    .init(color: Theme.canvas, location: 0.92),
                    .init(color: Theme.canvas, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
        }
        .frame(width: layout.width, height: layout.mapHeight)
        .clipped()
        .opacity(mapShown ? 1 : 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Map of your route to the gym")
    }

    private var mapReader: some View {
        MapReader { proxy in
            ZStack {
                mapBase
                puckLayer(proxy: proxy, tick: mapTick)
            }
        }
    }

    /// The map itself, forced to greys. The saturation blend only works inside
    /// its own compositing group, and the coral puck is drawn outside it.
    private var mapBase: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom, .rotate, .pitch]) {
            MapPolyline(coordinates: model.travelledPath)
                .stroke(Color(white: 0.72), lineWidth: 6)
            MapPolyline(coordinates: model.remainingPath)
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            Annotation("", coordinate: model.origin ?? model.gym, anchor: .center) {
                homeDot.opacity(model.origin == nil ? 0 : 1)
            }
            Annotation("", coordinate: model.gym, anchor: .bottom) {
                gymPin
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControlVisibility(.hidden)
        .onMapCameraChange(frequency: .continuous) { context in
            cameraHeading = context.camera.heading
            mapTick &+= 1
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 8).onChanged { _ in noteUserMovedMap() }
        )
        .simultaneousGesture(
            MagnifyGesture().onChanged { _ in noteUserMovedMap() }
        )
        .overlay {
            Rectangle()
                .fill(Color.white)
                .blendMode(.saturation)
                .allowsHitTesting(false)
        }
        .compositingGroup()
    }

    private var homeDot: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(Color(white: 0.6), lineWidth: 2))
    }

    private var gymPin: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Theme.ink)
                Circle().strokeBorder(Color.white, lineWidth: 2)
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 40, height: 40)
            RidgeTripPinTip()
                .fill(Theme.ink)
                .frame(width: 12, height: 8)
                .offset(y: -2)
        }
        .shadow(color: Color.black.opacity(0.25), radius: 4, y: 2)
    }

    @ViewBuilder
    private func puckLayer(proxy: MapProxy, tick: Int) -> some View {
        if let coordinate = model.snapped ?? model.user,
           let point = proxy.convert(coordinate, to: .local) {
            RidgeTripPuck(
                heading: model.heading - cameraHeading,
                showsCone: !isArrival,
                reduceMotion: reduceMotion
            )
            .position(point)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: Camera

    private func followCamera() -> MapCamera {
        let focus = model.user ?? model.gym
        if isArrival {
            return MapCamera(centerCoordinate: model.gym, distance: 520, heading: model.heading, pitch: is3D ? 58 : 0)
        }
        if is3D {
            // Look ahead of the puck so it sits low on the map, as in the prototype.
            let centre = RidgeTripMath.offset(focus, metres: 90, bearing: model.heading)
            return MapCamera(centerCoordinate: centre, distance: 700, heading: model.heading, pitch: 58)
        }
        return MapCamera(centerCoordinate: focus, distance: 900, heading: 0, pitch: 0)
    }

    private func updateFollow() {
        guard entryDone, isFollowing else { return }
        let target = MapCameraPosition.camera(followCamera())
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) { camera = target }
        } else {
            withAnimation(.easeInOut(duration: 0.8)) { camera = target }
        }
    }

    private func noteUserMovedMap() {
        if entryDone && isFollowing && !isArrival {
            isFollowing = false
        }
    }

    private func recenter() {
        Haptics.tap()
        isFollowing = true
        entryDone = true
        updateFollow()
    }

    /// A top-down rectangle that fits the route (or user and gym).
    private func overviewRect() -> MKMapRect {
        var coordinates: [CLLocationCoordinate2D] = model.route.count > 1 ? model.route : []
        coordinates.append(model.gym)
        if let user = model.user { coordinates.append(user) }
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        let perMetre = MKMapPointsPerMeterAtLatitude(model.gym.latitude)
        let minimumSpan = 1_200 * perMetre
        let width = max((maxX - minX) * 1.6, minimumSpan)
        let height = max((maxY - minY) * 1.6, minimumSpan)
        let centreX = (minX + maxX) / 2
        let centreY = (minY + maxY) / 2
        return MKMapRect(x: centreX - width / 2, y: centreY - height / 2, width: width, height: height)
    }

    // MARK: Entry

    private func playEntry() async {
        guard frame.entryStarted, !entryPlayed else { return }
        entryPlayed = true

        if reduceMotion {
            mapShown = false
            camera = MapCameraPosition.camera(followCamera())
            sheetIn = true
            layersIn = true
            withAnimation(.easeOut(duration: 0.4)) {
                mapShown = true
                controlsIn = true
            }
            entryDone = true
            updateFollow()
            return
        }

        camera = MapCameraPosition.rect(overviewRect())
        try? await Task.sleep(for: .milliseconds(500))
        if Task.isCancelled { return }

        withAnimation(.easeInOut(duration: 1.2)) {
            camera = MapCameraPosition.camera(followCamera())
        }
        withAnimation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.85)) {
            sheetIn = true
        }
        try? await Task.sleep(for: .milliseconds(100))
        layersIn = true
        try? await Task.sleep(for: .milliseconds(150))
        withAnimation(.easeOut(duration: 0.5)) {
            controlsIn = true
        }
        try? await Task.sleep(for: .milliseconds(950))
        entryDone = true
        updateFollow()
    }

    // MARK: Chrome

    private func chromeLayer(_ layout: RidgeTripLayout) -> some View {
        ZStack(alignment: .topLeading) {
            GlassCircleButton(symbol: "xmark", label: "End", diameter: 44) {
                actions.end()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 16)
            .padding(.top, layout.topInset + 12)

            headerCapsule
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, layout.topInset + 18)

            VStack(spacing: 10) {
                GlassCircleButton(
                    symbol: is3D ? "view.2d" : "view.3d",
                    label: is3D ? "Switch to 2D map" : "Switch to 3D map",
                    diameter: 44
                ) {
                    Haptics.tap()
                    is3D.toggle()
                    isFollowing = true
                }
                GlassCircleButton(symbol: "location.fill", label: "Recenter", diameter: 44) {
                    recenter()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, 16)
            .padding(.top, layout.topInset + 12)
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
        .opacity(controlsIn ? 1 : 0)
        .allowsHitTesting(controlsIn && !isArrival)
    }

    private var headerCapsule: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .semibold))
            Text("GymLock")
                .font(.system(size: 17, weight: .bold, design: .rounded))
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassCapsule()
        .accessibilityElement(children: .combine)
    }

    // MARK: Sheet

    private func sheetLayer(_ layout: RidgeTripLayout) -> some View {
        ZStack(alignment: .topLeading) {
            sheetBackground(layout)
            RidgeTripBand(
                model: model,
                phase: frame.phase,
                scale: layout.scale,
                layersIn: layersIn,
                reduceMotion: reduceMotion
            )
            .offset(y: 63 - 180 * layout.scale)
            sheetText(layout)
                .opacity(isArrival ? 0 : 1)
                .animation(.easeOut(duration: 0.5), value: isArrival)
        }
        .frame(width: layout.width, height: layout.sheetHeight, alignment: .topLeading)
        .offset(y: sheetOffset(layout))
        .opacity(sheetIn || !reduceMotion ? 1 : 0)
        .frame(width: layout.width, height: layout.height, alignment: .bottom)
    }

    private func sheetOffset(_ layout: RidgeTripLayout) -> CGFloat {
        if sheetIn || reduceMotion { return 0 }
        return layout.sheetHeight * 1.12 + 60
    }

    private func sheetBackground(_ layout: RidgeTripLayout) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 24,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 24,
            style: .continuous
        )
        return ZStack(alignment: .top) {
            shape
                .fill(Theme.canvas)
                .shadow(color: Color.black.opacity(0.06), radius: 15, y: -6)
            shape
                .stroke(Theme.border, lineWidth: 1)
                .mask(alignment: .top) {
                    Rectangle().frame(height: 26)
                }
        }
        .frame(width: layout.width, height: layout.sheetHeight)
    }

    private func sheetText(_ layout: RidgeTripLayout) -> some View {
        let atHome = frame.phase == .atHome
        return VStack(alignment: .leading, spacing: 0) {
            countdownRow
            infoRow
                .padding(.top, 2)
            Text(frame.heading)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)
                .animation(Theme.stateChange, value: frame.heading)
                .padding(.top, 14)
            Text(frame.support)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 42, alignment: .topLeading)
                .contentTransition(.opacity)
                .animation(Theme.stateChange, value: frame.support)
                .padding(.top, 4)
            Spacer(minLength: 8)
            actionZone(atHome: atHome)
        }
        .padding(.horizontal, 24)
        .padding(.top, 70)
        .padding(.bottom, layout.bottomInset + 34)
        .frame(width: layout.width, height: layout.sheetHeight, alignment: .topLeading)
    }

    private var countdownRow: some View {
        let clock = TripFormat.clock(frame.remaining)
        var spoken = "\(TripFormat.spoken(frame.remaining)) left"
        if let by = frame.gymBy { spoken += ", gym by \(by)" }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(clock)
                .font(.system(size: 68, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText(countsDown: true))
                .animation(.easeOut(duration: 0.2), value: clock)
                .layoutPriority(1)
            Spacer(minLength: 0)
            if let by = frame.gymBy {
                Text(TripCopy.gymBy(by))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(1)
            }
        }
        .frame(height: 72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Get to your gym")
        .accessibilityValue(spoken)
    }

    private var infoRow: some View {
        HStack(spacing: 10) {
            if let line = frame.distanceLine {
                Text(line)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if let name = frame.gymName {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(height: 22)
    }

    private func actionZone(atHome: Bool) -> some View {
        let animation: Animation = reduceMotion ? .easeOut(duration: 0.2) : Theme.settle
        return ZStack {
            TripPrimaryButton(
                title: TripCopy.leftButton,
                systemImage: "figure.walk.departure",
                action: actions.left
            )
            .opacity(atHome ? 1 : 0)
            .scaleEffect(
                x: (atHome || reduceMotion) ? 1 : 0.97,
                y: (atHome || reduceMotion) ? 1 : 0.45
            )
            .allowsHitTesting(atHome)
            .accessibilityHidden(!atHome)

            TripStatusRow()
                .opacity(atHome ? 0 : 1)
                .offset(y: (atHome || reduceMotion) ? 0 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(atHome)
        }
        .frame(height: 56)
        .animation(animation, value: atHome)
    }

    // MARK: Arrival

    private func arrivalLayer(_ layout: RidgeTripLayout) -> some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.04, green: 0.04, blue: 0.04)
                .opacity(0.62)
                .opacity(isArrival ? 1 : 0)
                .contentShape(Rectangle())
                .allowsHitTesting(isArrival)
                .animation(.easeOut(duration: reduceMotion ? 0.2 : 0.6), value: isArrival)

            RidgeTripVerifyPanel(trip: frame, reduceMotion: reduceMotion, onTrouble: actions.trouble)
                .frame(width: layout.width - 48)
                .opacity(isArrival ? 1 : 0)
                .offset(y: (isArrival || reduceMotion) ? 0 : 12)
                .allowsHitTesting(isArrival)
                .animation(
                    reduceMotion
                        ? Animation.easeOut(duration: 0.2)
                        : Animation.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.6).delay(isArrival ? 0.25 : 0),
                    value: isArrival
                )
                .position(x: layout.width / 2, y: layout.height * 0.74)
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
    }

    private func handlePhaseChange(from old: TripPhase, to new: TripPhase, layout: RidgeTripLayout) {
        let wasArrived = old == .verifying || old == .verified
        if new == .verifying && !wasArrived {
            // Opening mid-dwell never reaches here (no change), so no confetti then.
            fire(origin: RidgeTripBand.summitPoint(layout: layout, reduceMotion: reduceMotion), count: 170, fromTop: true)
        }
        if new == .verified && old != .verified {
            // No haptic here: confirmArrival() already fired the one success tap.
            fire(origin: CGPoint(x: layout.width / 2, y: layout.height * 0.74 + 3), count: 55, fromTop: false)
        }
    }

    private func fire(origin: CGPoint, count: Int, fromTop: Bool) {
        guard !reduceMotion else { return }
        burstCount += 1
        burst = TripConfetti.Burst(id: burstCount, origin: origin, count: count, fromTop: fromTop)
    }

    private func runFinale() async {
        guard frame.phase == .verified, !finaleCalled else { return }
        try? await Task.sleep(for: .milliseconds(2_400))
        guard !Task.isCancelled, !finaleCalled else { return }
        finaleCalled = true
        actions.finaleDone()
    }
}
