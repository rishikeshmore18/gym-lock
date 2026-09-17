import SwiftUI

/// How big the expanded streak card and its contents are on this device.
///
/// Derived from the space actually available rather than hardcoded, so the card
/// keeps the same presence on a small phone as on a large one, and computed
/// once per layout rather than per frame.
struct StreakCardMetrics: Equatable {
    let size: CGSize

    var cornerRadius: CGFloat { 44 }

    /// The number crowns the flame, so it is sized off the card rather than off
    /// the artwork.
    var numberSize: CGFloat { size.width * 0.17 }

    var labelSize: CGFloat { 15 }
    /// The "2 of 3 this week" line and the freeze row under the label.
    var detailSize: CGFloat { 13 }

    var topPadding: CGFloat { 26 }
    var bottomPadding: CGFloat { 24 }
    var numberToFlame: CGFloat { 8 }
    var flameToLabel: CGFloat { 6 }
    var labelToDetail: CGFloat { 4 }

    /// Height of the flame the user can actually see — not of the square canvas
    /// it is drawn on, which is mostly empty.
    ///
    /// Takes everything the card has left after the number, the label and the
    /// two detail lines, and is capped so the flame never runs wider than three
    /// quarters of the card.
    var flameHeight: CGFloat {
        let chrome = numberSize * 1.2
            + numberToFlame
            + flameToLabel
            + labelSize * 1.35
            + labelToDetail
            + detailSize * 1.35 * 2
            + topPadding
            + bottomPadding

        let byHeight = size.height - chrome
        let byWidth = size.width * 0.75 / FlameArtwork.aspect
        return max(min(byHeight, byWidth), 120)
    }

    /// Fits the card into the available space. Tall, because the flame is now
    /// the subject rather than an illustration — but never edge to edge: home
    /// has to stay visible behind it for the card to read as something sitting
    /// on top of home.
    static func fit(_ available: CGSize) -> StreakCardMetrics {
        let width = min(max(available.width * 0.84, 240), 390)
        let height = min(max(available.height * 0.58, 330), 500)
        return StreakCardMetrics(size: CGSize(width: width, height: height))
    }
}

/// What the expanded streak shows: a number, a large flame, and a label.
///
/// Contents only — the surface underneath is drawn separately, because it is
/// the same surface as the header capsule and has to travel and reshape
/// independently of what is printed on it.
struct StreakCardContent: View {
    let streak: StreakSnapshot
    let metrics: StreakCardMetrics
    /// Whether the flame is playing. False under Reduce Motion, and while the
    /// card is resting unseen behind the header — either way the flame is held
    /// on a single frame rather than torn down.
    let isAnimated: Bool
    /// Only a card the user opened themselves offers a way to close it.
    let showsClose: Bool
    let onClose: () -> Void
    /// Spends a freeze on the live week. Confirmed first — see `freezeRow`.
    let onArmFreeze: () -> Void

    @State private var isConfirmingFreeze = false

    var body: some View {
        ZStack {
            figure

            if showsClose {
                closeButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: metrics.size.width, height: metrics.size.height)
        // The card is transient decoration around a value that is also
        // announced in full to VoiceOver, so its type stays fixed rather than
        // reflowing a fixed-size surface at accessibility sizes.
        .dynamicTypeSize(.large)
        .accessibilityElement(children: .contain)
    }

    /// The flame is decorative: the number and its label already say everything
    /// this card is communicating, so VoiceOver is given one clear element
    /// instead of an animation it cannot describe.
    private var figure: some View {
        VStack(spacing: 0) {
            Text("\(streak.weeks)")
                .font(.system(size: metrics.numberSize, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // Clears the close button even at three digits.
                .padding(.horizontal, 56)
                .padding(.top, metrics.topPadding)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(StreakChip.accessibilityLabel(for: streak.weeks))
                // Focused first, so VoiceOver reads the streak before offering
                // the close button.
                .accessibilitySortPriority(1)

            FlameFigure(visibleHeight: metrics.flameHeight, isAnimating: isAnimated)
                .padding(.top, metrics.numberToFlame)
                .accessibilityHidden(true)

            Text("\(streak.weeksLabel) · \(streak.thisWeekLabel)")
                .font(.system(size: metrics.labelSize, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 24)
                .padding(.top, metrics.flameToLabel)

            freezeRow
                .padding(.top, metrics.labelToDetail)

            Spacer(minLength: 0)
        }
    }

    /// The freeze bank, and the one way to spend from it.
    ///
    /// One row, one confirmation. The confirmation exists because arming is
    /// irreversible until the week ends — the freeze is refunded if the week is
    /// kept, but it cannot be un-armed by hand — and a single accidental tap
    /// should not be able to spend something that took a month to earn.
    @ViewBuilder
    private var freezeRow: some View {
        if streak.lastCompletedWeekWasFrozen {
            detail("streak frozen · \(freezeCountLabel) left")
        } else if streak.isLiveWeekPreArmed {
            detail("this week frozen · \(freezeCountLabel) left")
        } else if streak.canArmFreeze {
            Button {
                Haptics.tap()
                isConfirmingFreeze = true
            } label: {
                Text("\(freezeCountLabel) · freeze this week")
                    .font(.system(size: metrics.detailSize, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Freeze this week. \(freezeCountLabel) available.")
            .accessibilityHint("Protects the streak if this week is not kept.")
            .confirmationDialog(
                "Freeze this week?",
                isPresented: $isConfirmingFreeze,
                titleVisibility: .visible
            ) {
                Button("Freeze This Week") {
                    Haptics.commit()
                    onArmFreeze()
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("Uses one freeze. You get it back if you keep the week anyway.")
            }
        } else if streak.freezesAvailable > 0 {
            detail(freezeCountLabel)
        } else {
            // Holds the line so the flame does not jump when a freeze arrives.
            detail(" ").accessibilityHidden(true)
        }
    }

    private var freezeCountLabel: String {
        "\(streak.freezesAvailable) \(streak.freezesAvailable == 1 ? "freeze" : "freezes")"
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.system(size: metrics.detailSize, weight: .medium))
            .foregroundStyle(Theme.inkTertiary)
            .frame(minHeight: 32)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 30, height: 30)
                .background(Theme.surfaceMuted, in: .circle)
                // Quiet to look at, but still a full-size target to hit.
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .padding(.trailing, 8)
        .accessibilityLabel("Close streak")
    }
}

#Preview {
    let metrics = StreakCardMetrics.fit(CGSize(width: 393, height: 740))

    return ZStack {
        Theme.canvas.ignoresSafeArea()
        Color.black.opacity(0.4).ignoresSafeArea()

        StreakCardContent(
            streak: StreakSnapshot(
                weeks: 6,
                weeklyGoal: 3,
                thisWeekSessionDays: 2,
                isThisWeekKept: false,
                freezesAvailable: 2,
                lastCompletedWeekWasFrozen: false,
                isLiveWeekPreArmed: false,
                liveWeekStart: Date()
            ),
            metrics: metrics,
            isAnimated: true,
            showsClose: true,
            onClose: {},
            onArmFreeze: {}
        )
        .background(Theme.surface, in: .rect(cornerRadius: metrics.cornerRadius))
        .shadow(color: .black.opacity(0.18), radius: 40, y: 18)
    }
}
