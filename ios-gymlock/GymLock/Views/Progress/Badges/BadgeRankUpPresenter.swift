//
//  BadgeRankUpPresenter.swift
//  GymLock — Badges
//
//  Full-screen rank-up overlay + the hand-off: after the reveal, a tap flies the badge from
//  the centre of the screen into its slot in the grid (same 0.72 s arc as the design),
//  then calls `onLanded` so the app can mark it unlocked and play the slot's pop.
//
//  Usage (on the screen that contains the badge grid):
//      .badgeRankUp($rankUpRequest) { req in /* mark req.to unlocked, trigger pops */ }
//

import SwiftUI

struct BadgeRankUpRequest: Identifiable, Equatable {
    let id = UUID()
    let to: BadgeDefinition
    /// Previous rung (ladders); nil → starts from the locked version of `to`.
    let from: BadgeDefinition?

    /// Builds the request the way the design does: ladders rank up from the previous rung.
    init(unlocking badge: BadgeDefinition) {
        to = badge
        from = BadgeCatalog.previousRung(of: badge)
    }
}

extension View {
    /// Presents the rank-up for `request`; when the user taps after the reveal the badge flies into
    /// its slot (any `BadgeCardView` for that badge on screen) and `onLanded` is called.
    func badgeRankUp(_ request: Binding<BadgeRankUpRequest?>, playbackRate: Double = 1, onLanded: @escaping (BadgeRankUpRequest) -> Void) -> some View {
        modifier(BadgeRankUpPresenter(request: request, playbackRate: playbackRate, onLanded: onLanded))
    }
}

struct BadgeRankUpPresenter: ViewModifier {
    @Binding var request: BadgeRankUpRequest?
    var playbackRate: Double
    var onLanded: (BadgeRankUpRequest) -> Void

    @State private var flight: Flight?

    struct Flight: Equatable {
        let request: BadgeRankUpRequest
        let from: CGRect   // overlay coordinates
        let to: CGRect
    }

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(BadgeSlotFramesKey.self) { slots in
                GeometryReader { geo in
                    let origin = geo.frame(in: .global).origin
                    ZStack {
                        if let req = request, flight?.request.id != req.id {
                            RankUpView(to: req.to, from: req.from, playbackRate: playbackRate) {
                                let start = RankUpLayout(size: geo.size).badgeFrame
                                guard let slot = slots[req.to.id] else {
                                    finish(req)
                                    return
                                }
                                let target = slot.offsetBy(dx: -origin.x, dy: -origin.y)
                                flight = Flight(request: req, from: start, to: target)
                            }
                            .id(req.id)
                            .transition(.opacity.animation(.easeOut(duration: 0.2)))
                        }
                        if let fl = flight {
                            BadgeFlightView(flight: fl) { finish(fl.request) }
                                .id(fl.request.id)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .ignoresSafeArea()
                .allowsHitTesting(request != nil || flight != nil)
            }
    }

    private func finish(_ req: BadgeRankUpRequest) {
        BadgeHaptics.shared.playLand()
        onLanded(req)
        flight = nil
        if request?.id == req.id { request = nil }
    }
}

/// The badge flying from the rank-up into its slot while the dark backdrop fades away.
/// WAAPI equivalent: duration .72 s, easing cubic-bezier(.45,.05,.25,1), keyframes
///   0: translate(dx,dy) scale(k) · .45: translate(.45dx, .45dy − 60) scale(1+(k−1)·.45) rotate(−6°) · 1: identity
struct BadgeFlightView: View {
    let flight: BadgeRankUpPresenter.Flight
    var onDone: () -> Void
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { tl in
            let e = tl.date.timeIntervalSince(start)
            let p = min(1, e / 0.72)
            let q = CubicBezier(0.45, 0.05, 0.25, 1).value(p)
            let to = flight.to
            let from = flight.from
            let dx = from.midX - to.midX
            let dy = from.midY - to.midY
            let k = from.width / to.width
            let (tx, ty, sc, rot): (Double, Double, Double, Double) = {
                if q < 0.45 {
                    let u = q / 0.45
                    return (dx + (dx * 0.45 - dx) * u, dy + (dy * 0.45 - 60 - dy) * u, k + (1 + (k - 1) * 0.45 - k) * u, -6 * u)
                } else {
                    let u = (q - 0.45) / 0.55
                    return (dx * 0.45 * (1 - u), (dy * 0.45 - 60) * (1 - u), (1 + (k - 1) * 0.45) + (1 - (1 + (k - 1) * 0.45)) * u, -6 * (1 - u))
                }
            }()
            let fade = CubicBezier(0.25, 0.1, 0.25, 1).value(min(1, e / 0.55))   // CSS `ease`
            ZStack(alignment: .topLeading) {
                Color(.sRGB, red: 4 / 255, green: 5 / 255, blue: 10 / 255, opacity: 0.94 * (1 - fade))
                    .ignoresSafeArea()
                BadgeArtView(badge: flight.request.to, width: to.width)
                    .scaleEffect(sc)
                    .rotationEffect(.degrees(rot))
                    .offset(x: tx, y: ty)
                    .position(x: to.midX, y: to.midY)
            }
        }
        .allowsHitTesting(true)
        .task {
            try? await Task.sleep(nanoseconds: 720_000_000)
            onDone()
        }
    }
}
