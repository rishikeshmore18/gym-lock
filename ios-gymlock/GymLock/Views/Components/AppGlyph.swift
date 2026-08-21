import SwiftUI

/// A recognisable stand-in for one of the apps that usually wins.
///
/// These are drawn, not bundled: each is the app's colour signature and a
/// symbol standing for what the app *is*, in GymLock's own rounded-square
/// language. That keeps the row instantly scannable without shipping anyone
/// else's trademarked artwork.
///
/// `lockProgress` drives the demonstration on the lock and unlock screens. At
/// `0` the glyph is in full colour; at `1` it is drained and dimmed with a lock
/// badge on the corner. Everything in between is a real intermediate state, so
/// the transition can be scrubbed by an animation rather than swapped.
struct AppGlyph: View {
    let app: DistractingApp
    var size: CGFloat = 52
    /// 0 = available and colourful, 1 = locked and drained.
    var lockProgress: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(fill)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: app.symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            }
            // Draining colour and dimming are what make an icon read as
            // unavailable — far more legible at a glance than an overlay alone.
            .saturation(1 - 0.88 * lockProgress)
            .brightness(-0.30 * lockProgress)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(Color.black.opacity(0.22 * lockProgress))
            }
            .overlay(alignment: .bottomTrailing) { lockBadge }
            .accessibilityElement()
            .accessibilityLabel(lockProgress > 0.5 ? "\(app.label), locked" : app.label)
    }

    @ViewBuilder
    private var lockBadge: some View {
        if lockProgress > 0.01 {
            Image(systemName: "lock.fill")
                .font(.system(size: size * 0.2, weight: .black))
                .foregroundStyle(.white)
                .frame(width: size * 0.38, height: size * 0.38)
                .background(Theme.ink, in: .circle)
                .overlay {
                    Circle().strokeBorder(Theme.canvas, lineWidth: 1.6)
                }
                .offset(x: size * 0.11, y: size * 0.11)
                .scaleEffect(0.6 + 0.4 * lockProgress)
                .opacity(lockProgress)
        }
    }

    private var fill: LinearGradient {
        LinearGradient(
            colors: app.brandColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension DistractingApp {
    /// The symbol standing for what this app does.
    var symbol: String {
        switch self {
        case .instagram: "camera.fill"
        case .tiktok: "music.note"
        case .youtube: "play.fill"
        case .reddit: "bubble.left.and.bubble.right.fill"
        case .x: "xmark"
        case .snapchat: "paperplane.fill"
        case .games: "gamecontroller.fill"
        case .other: "square.grid.2x2.fill"
        }
    }

    /// Two-stop colour signature, recognisable without being a copy.
    var brandColors: [Color] {
        switch self {
        case .instagram:
            [Color(red: 0.51, green: 0.23, blue: 0.71), Color(red: 0.98, green: 0.42, blue: 0.20)]
        case .tiktok:
            [Color(red: 0.13, green: 0.13, blue: 0.15), Color(red: 0.02, green: 0.02, blue: 0.03)]
        case .youtube:
            [Color(red: 0.94, green: 0.22, blue: 0.18), Color(red: 0.78, green: 0.10, blue: 0.09)]
        case .reddit:
            [Color(red: 1.00, green: 0.42, blue: 0.16), Color(red: 0.91, green: 0.28, blue: 0.06)]
        case .x:
            [Color(red: 0.16, green: 0.16, blue: 0.18), Color(red: 0.04, green: 0.04, blue: 0.05)]
        case .snapchat:
            [Color(red: 1.00, green: 0.88, blue: 0.20), Color(red: 0.98, green: 0.75, blue: 0.05)]
        case .games:
            [Color(red: 0.35, green: 0.36, blue: 0.86), Color(red: 0.24, green: 0.22, blue: 0.65)]
        case .other:
            [Color(red: 0.58, green: 0.58, blue: 0.60), Color(red: 0.42, green: 0.42, blue: 0.45)]
        }
    }
}
