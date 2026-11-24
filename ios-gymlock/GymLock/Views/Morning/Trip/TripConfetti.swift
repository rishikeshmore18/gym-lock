import SwiftUI

/// The arrival confetti, shared by both trip styles.
///
/// A rare, once-a-session celebration (UI-RULES §5.1, the delight tier), so it
/// may run longer than 300 ms. Every burst ends: nothing loops. Mostly black,
/// white and greys, with a few coral pieces carried over from the user's dot.
/// Under Reduce Motion it draws nothing; the screen still dims and verifies.
struct TripConfetti: View {
    enum Look {
        /// Round dots that squash as they spin (Matrix).
        case dots
        /// Small paper rectangles and circles that flip (Ridge).
        case paper
    }

    /// One burst request. Change `id` to fire another.
    struct Burst: Equatable {
        var id: Int
        /// Where the pieces leave from, in this view's coordinates.
        var origin: CGPoint
        var count: Int
        /// Also rain a second, smaller wave from the top edge.
        var fromTop: Bool
    }

    let look: Look
    let burst: Burst?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pieces: [Piece] = []
    @State private var lastBurstID: Int?
    @State private var lastTick: Date?

    private struct Piece {
        var x, y, vx, vy: Double
        var spin, spinRate: Double
        var size: Double
        var life: Double
        var maxLife: Double
        var shade: Int        // 0 white, 1 light grey, 2 mid grey, 3 ink, 4 coral
        var isRound: Bool
    }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: pieces.isEmpty)) { context in
                Canvas { ctx, _ in
                    for piece in pieces { draw(piece, in: &ctx) }
                }
                .onChange(of: context.date) { _, now in step(to: now) }
            }
            .onChange(of: burst) { _, new in fire(new, size: proxy.size) }
            .onAppear { fire(burst, size: proxy.size) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Simulation

    private func fire(_ burst: Burst?, size: CGSize) {
        guard let burst, burst.id != lastBurstID, !reduceMotion else { return }
        lastBurstID = burst.id
        var generator = SystemRandomNumberGenerator()
        var added: [Piece] = []
        for _ in 0..<burst.count {
            let angle = Double.random(in: -Double.pi * 0.92 ... -Double.pi * 0.08, using: &generator)
            let speed = Double.random(in: 260...720, using: &generator)
            added.append(makePiece(x: burst.origin.x, y: burst.origin.y,
                                   vx: cos(angle) * speed, vy: sin(angle) * speed, using: &generator))
        }
        if burst.fromTop {
            for _ in 0..<(burst.count / 2) {
                added.append(makePiece(x: Double.random(in: 0...Double(size.width), using: &generator), y: -10,
                                       vx: Double.random(in: -60...60, using: &generator),
                                       vy: Double.random(in: 40...220, using: &generator), using: &generator))
            }
        }
        pieces.append(contentsOf: added)
        lastTick = nil
    }

    private func makePiece(x: Double, y: Double, vx: Double, vy: Double, using generator: inout SystemRandomNumberGenerator) -> Piece {
        let roll = Double.random(in: 0...1, using: &generator)
        let shade = roll < 0.1 ? 4 : roll < 0.4 ? 0 : roll < 0.62 ? 1 : roll < 0.82 ? 2 : 3
        let life = Double.random(in: 1.9...2.8, using: &generator)
        return Piece(
            x: x, y: y, vx: vx, vy: vy,
            spin: Double.random(in: 0...(2 * .pi), using: &generator),
            spinRate: Double.random(in: -9...9, using: &generator),
            size: look == .dots ? Double.random(in: 3...7, using: &generator) : Double.random(in: 4...9, using: &generator),
            life: life, maxLife: life,
            shade: shade,
            isRound: look == .dots ? true : Bool.random(using: &generator)
        )
    }

    private func step(to now: Date) {
        guard !pieces.isEmpty else { lastTick = nil; return }
        let dt = min(1.0 / 20, lastTick.map { now.timeIntervalSince($0) } ?? 1.0 / 60)
        lastTick = now
        let gravity = 900.0, drag = 0.985
        for index in pieces.indices {
            pieces[index].vy += gravity * dt
            pieces[index].vx *= drag
            pieces[index].vy *= drag
            pieces[index].x += pieces[index].vx * dt
            pieces[index].y += pieces[index].vy * dt
            pieces[index].spin += pieces[index].spinRate * dt
            pieces[index].life -= dt
        }
        pieces.removeAll { $0.life <= 0 }
    }

    // MARK: - Drawing

    private func color(_ shade: Int) -> Color {
        switch shade {
        case 0: Color(white: 0.97)
        case 1: Color(white: 0.82)
        case 2: Color(white: 0.55)
        case 3: Theme.ink
        default: Theme.accent
        }
    }

    private func draw(_ piece: Piece, in ctx: inout GraphicsContext) {
        let fade = min(1, piece.life / 0.6)
        let flip = abs(cos(piece.spin))
        var layer = ctx
        layer.opacity = fade
        layer.translateBy(x: piece.x, y: piece.y)
        layer.rotate(by: .radians(piece.spin * 0.4))
        let w = piece.size
        let h = piece.isRound ? piece.size * max(0.25, flip) : piece.size * 0.55 * max(0.2, flip)
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        let path = piece.isRound ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1)
        layer.fill(path, with: .color(color(piece.shade)))
    }
}
