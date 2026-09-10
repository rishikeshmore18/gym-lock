import SwiftUI

/// The badges emblem: the GymLock mark.
///
/// Badges do not exist yet, so there is nothing earned to draw. Rather than
/// invent one, the mark shows up dimmed — the same honesty rule the momentum
/// field follows for a day with no record. When the first badge is earned the
/// mark comes up to full strength, which makes the dimmed state read as
/// "not yet" instead of "broken".
struct LogoEmblem: View {
    /// True once at least one badge exists.
    var isEarned: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image("GymLockLogo")
            .resizable()
            .scaledToFit()
            .frame(height: 76)
            .clipShape(.rect(cornerRadius: 18))
            .saturation(isEarned ? 1 : 0)
            .opacity(isEarned ? 1 : 0.38)
            .shadow(color: .black.opacity(isEarned ? 0.16 : 0.06), radius: 8, y: 4)
            .animation(
                reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8),
                value: isEarned
            )
    }
}

#Preview("Unearned") {
    LogoEmblem()
        .padding(40)
        .background(Theme.surface)
}

#Preview("Earned") {
    LogoEmblem(isEarned: true)
        .padding(40)
        .background(Theme.surface)
}
