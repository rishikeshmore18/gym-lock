import SwiftUI

extension View {
    /// Silences every hero haptic (the card and the done flow) while this view is on screen
    /// (spec §6.1): the alarm ringing, the camera open.
    func blocksHeroHaptics(_ reason: String) -> some View {
        onAppear { HeroHapticPlayer.shared.setBlocked(reason, true) }
            .onDisappear { HeroHapticPlayer.shared.setBlocked(reason, false) }
    }
}
