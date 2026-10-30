//
//  BadgeCardView.swift
//  GymLock — Badges
//
//  One grid cell (badge art + name + rule), styled exactly like the approved design,
//  light and dark. Reports its art frame so the rank-up can fly the badge into it.
//

import SwiftUI

/// Colours of the badges screen (light / dark).
struct BadgePalette {
    let bg, card, text, sub, off, line, seg, segSel: Color

    static func of(_ scheme: ColorScheme) -> BadgePalette {
        scheme == .dark
            ? BadgePalette(bg: .black, card: Color(hex: 0x151517), text: Color(hex: 0xF4F4F6), sub: Color(hex: 0x8E8E96),
                           off: Color(hex: 0x5D5D64), line: .white.opacity(0.07), seg: Color(hex: 0x1F1F22), segSel: Color(hex: 0x3A3A3F))
            // Light sits on GymLock's own canvas, surface and ink.
            : BadgePalette(bg: Theme.canvas, card: Theme.surface, text: Theme.ink, sub: Color(hex: 0x8A8A92),
                           off: Color(hex: 0xA4A4AB), line: .black.opacity(0.06), seg: Color(hex: 0xE4E4EA), segSel: .white)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// Global frames of every badge slot, keyed by badge id (used for the fly-to-slot hand-off).
struct BadgeSlotFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct BadgeCardView: View {
    let badge: BadgeDefinition
    let unlocked: Bool
    /// Locked progress, e.g. "63 / 100 DAYS". Replaces a ladder's rule line;
    /// sits under an achievement's rule.
    var progress: String? = nil
    /// What VoiceOver reads for the whole cell.
    var accessibilityText: String? = nil
    /// Seconds to wait before the "just unlocked" pop (nil = no pop).
    var popDelay: Double? = nil
    var onTap: () -> Void = {}

    @Environment(\.colorScheme) private var scheme
    @State private var popToken = 0
    @ScaledMetric(relativeTo: .subheadline) private var nameSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption2) private var ruleSize: CGFloat = 10.5

    static let artWidth: CGFloat = 100

    var body: some View {
        let P = BadgePalette.of(scheme)
        Button(action: onTap) {
            VStack(spacing: 0) {
                art(P)
                    .padding(.top, -4)
                    .padding(.bottom, 4)
                Text(badge.name)
                    .font(.system(size: nameSize, weight: .bold))
                    .foregroundStyle(unlocked ? P.text : P.off)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if unlocked || !(badge.isLadder && progress != nil) {
                    Text(badge.rule)
                        .font(.system(size: badge.isLadder ? ruleSize - 0.5 : ruleSize + 0.5, weight: badge.isLadder ? .semibold : .medium))
                        .tracking(badge.isLadder ? ruleSize * 0.09 : 0)
                        .foregroundStyle(P.sub)
                        .opacity(unlocked ? 1 : 0.75)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                if let progress, !unlocked {
                    Text(progress)
                        .font(.system(size: ruleSize - 0.5, weight: .bold))
                        .tracking(ruleSize * 0.09)
                        .monospacedDigit()
                        .foregroundStyle(P.text.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(P.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(P.line, lineWidth: 1))
            .shadow(color: P.line, radius: 1, x: 0, y: 1)
        }
        .buttonStyle(BadgePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText ?? badge.name))
        .accessibilityHint(Text("shows details"))
        .accessibilityAddTraits(.isButton)
        .onChange(of: popDelay) { _, new in
            if new != nil { popToken += 1 }
        }
        .onAppear { if popDelay != nil { popToken += 1 } }
    }

    @ViewBuilder
    private func art(_ P: BadgePalette) -> some View {
        ZStack(alignment: .bottomTrailing) {
            BadgeArtView(badge: badge, locked: !unlocked, width: Self.artWidth)
                .opacity(unlocked ? 1 : 0.6)
            if !unlocked {
                Circle()
                    .fill(P.card)
                    .overlay(Circle().stroke(P.line, lineWidth: 1.5))
                    .overlay(LockGlyph().fill(P.off).frame(width: 12, height: 12))
                    .frame(width: 22, height: 22)
                    .padding(.trailing, 8)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: Self.artWidth, height: Self.artWidth * 1.1)
        .modifier(PopEffect(token: popToken, delay: popDelay ?? 0, accent: badge.tier.accent))
        .background(GeometryReader { g in
            Color.clear.preference(key: BadgeSlotFramesKey.self, value: [badge.id: g.frame(in: .global)])
        })
    }
}

/// CSS .card:active { transform: scale(.96) } with a .15s transition.
struct BadgePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The small padlock in the locked chip (same shape as the design's SVG, 24×24 box).
struct LockGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 4.5 * s, y: 10 * s, width: 15 * s, height: 11 * s), cornerSize: CGSize(width: 2.6 * s, height: 2.6 * s))
        var arc = Path()
        arc.move(to: CGPoint(x: 7 * s, y: 10 * s))
        arc.addLine(to: CGPoint(x: 7 * s, y: 7.5 * s))
        arc.addArc(center: CGPoint(x: 12 * s, y: 7.5 * s), radius: 5 * s, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        arc.addLine(to: CGPoint(x: 17 * s, y: 10 * s))
        p.addPath(arc.strokedPath(StrokeStyle(lineWidth: 2.6 * s, lineCap: .round)))
        return p
    }
}

/// "Just unlocked": scale .55 → 1.14 → 1 over .75 s (cubic-bezier .2,1.5,.4,1) + an accent ring
/// spreading 16 px and fading over .9 s — same as the design's CSS keyframes.
struct PopEffect: ViewModifier {
    let token: Int
    let delay: Double
    let accent: Color
    @State private var t0: Date?

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: t0 == nil)) { tl in
            let e = t0.map { max(0, tl.date.timeIntervalSince($0)) } ?? 10
            let p = min(1, e / 0.75)
            let q = CubicBezier(0.2, 1.5, 0.4, 1).value(p)
            // keyframes 0 → .55, 60% → 1.14, 100% → 1 (linear between, eased overall)
            let scale = t0 == nil ? 1 : (q < 0.6 ? 0.55 + (1.14 - 0.55) * (q / 0.6) : 1.14 + (1 - 1.14) * ((q - 0.6) / 0.4))
            let rp = min(1, e / 0.9)
            let ring = CubicBezier(0, 0, 0.58, 1).value(rp)   // ease-out
            content
                .scaleEffect(scale)
                .overlay {
                    if t0 != nil && rp < 1 {
                        Ellipse()
                            .stroke(accent, lineWidth: 16 * ring + 0.01)
                            .padding(-6 - 8 * ring)
                            .opacity(0.9 * (1 - ring))
                            .allowsHitTesting(false)
                    }
                }
        }
        .task(id: token) {
            guard token > 0 else { return }
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            t0 = Date()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            t0 = nil
        }
    }
}

/// CSS cubic-bezier() timing function.
struct CubicBezier {
    let x1, y1, x2, y2: Double
    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) { self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2 }

    func value(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var t = x
        for _ in 0..<8 {                                  // Newton–Raphson on x(t) = x
            let xt = bez(t, x1, x2) - x
            let d = dbez(t, x1, x2)
            if abs(xt) < 1e-6 { break }
            if abs(d) < 1e-6 { break }
            t -= xt / d
        }
        var lo = 0.0, hi = 1.0                            // bisection fallback
        if abs(bez(t, x1, x2) - x) > 1e-4 {
            t = x
            for _ in 0..<30 {
                let xt = bez(t, x1, x2)
                if xt < x { lo = t } else { hi = t }
                t = (lo + hi) / 2
            }
        }
        return bez(t, y1, y2)
    }

    private func bez(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }
    private func dbez(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b)
    }
}
