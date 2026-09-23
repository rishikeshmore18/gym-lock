import SwiftUI

/// The Alarm screen's header, for the pages pushed from it: the round glass
/// back button on the left and the centred title that shrinks into a glass
/// pill as the page scrolls under it.
///
/// Same button, same diameter, same padding and the same collapsing title as
/// `AlarmSettingsView.header`, so moving from Alarm to Sound to Haptics feels
/// like one continuous surface rather than three screens with three styles.
///
/// Always drawn as an overlay over a fixed spacer of `band` points, never as a
/// safe-area inset of the scroll view that drives the collapse: feeding the
/// title's size back into the scroll insets is what once froze the Alarm
/// screen.
struct AlarmPageHeader: View {
    /// 40pt button + 2 top + 4 bottom, rounded up for air. Matches the Alarm
    /// screen's `headerBand`.
    static let band: CGFloat = 52

    let title: String
    var scrollOffset: CGFloat = 0
    /// `chevron.left` when pushed; `xmark` when the page was presented over
    /// something rather than pushed onto it.
    var symbol: String = "chevron.left"
    var label: String = "Back"
    let onBack: () -> Void

    var body: some View {
        ZStack {
            CollapsingTitle(
                title: title,
                collapse: CollapsingTitleMetrics.collapse(forOffset: scrollOffset),
                overscroll: CollapsingTitleMetrics.overscroll(forOffset: scrollOffset),
                containerWidth: 0,
                start: .centred,
                expandedSize: 30
            )

            HStack(spacing: 0) {
                GlassCircleButton(symbol: symbol, label: label, action: onBack)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }
}
