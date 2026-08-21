import Observation
import SwiftUI

/// Lets an interactive control temporarily take the vertical drag away from the
/// pager.
///
/// The onboarding pager listens for a swipe anywhere on the page, which is
/// exactly right for storytelling scenes and exactly wrong for a picker wheel:
/// dragging the wheel would spin it *and* turn the page. Controls therefore
/// claim the gesture while they are being used and release it afterwards.
///
/// Claims are held by token rather than counted, so a drag that fires
/// `onChanged` fifty times still only holds one claim, and a control that never
/// receives its `onEnded` cannot wedge the pager permanently as long as it
/// releases on the next interaction.
@Observable
final class PagerInteractionLock {
    private var holders: Set<String> = []

    /// True while any control is using the vertical drag.
    var isLocked: Bool { !holders.isEmpty }

    func hold(_ token: String) {
        holders.insert(token)
    }

    func release(_ token: String) {
        holders.remove(token)
    }
}

extension View {
    /// Claims the pager's drag for the lifetime of a control interaction.
    func claimsPagerDrag(_ lock: PagerInteractionLock?, token: String, isActive: Bool) -> some View {
        onChange(of: isActive) { _, active in
            if active {
                lock?.hold(token)
            } else {
                lock?.release(token)
            }
        }
    }
}
