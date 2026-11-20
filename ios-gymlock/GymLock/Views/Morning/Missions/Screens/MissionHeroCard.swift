//
//  MissionHeroCard.swift
//  GymLock · mission screens
//
//  The big card on the first page: the mission's art on white (Matrix dots or the Ridge world),
//  then the kind chip, the title (30 bold, with a full stop) and the subtitle (17). Tapping the
//  art pulses it with a soft haptic.
//

import SwiftUI

struct MissionHeroCard: View {
    let metrics: MissionMetrics
    let mission: ActivationMissionType
    let style: MissionStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = 0
    @State private var hasLandedOnce = false

    var body: some View {
        let m = metrics
        VStack(spacing: 0) {
            MissionArt(
                figure: MissionFigure(mission),
                style: style,
                pulseToken: pulse,
                onLand: {
                    // The first formation is the page arriving; only later ones (a different
                    // mission) are felt.
                    if hasLandedOnce { MissionHaptic.soft.play() }
                    hasLandedOnce = true
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                MissionHaptic.soft.play()
                if !reduceMotion { pulse += 1 }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(MissionCopy.chip(mission))
                    .font(.system(size: m(13), weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
                    .frame(height: m(16), alignment: .leading)
                    .padding(.bottom, m(8))

                Text(MissionCopy.title(mission))
                    .font(.system(size: m(30), weight: .bold))
                    .tracking(-0.66 * m.scale)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, m(4))

                Text(MissionCopy.subtitle(mission))
                    .font(.system(size: m(17)))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id(mission)
            .transition(.opacity)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: m(148), alignment: .top)
            .padding(.horizontal, m(22))
            .padding(.top, m(16))
            .clipped()
        }
        .missionCard(m)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: mission)
        .accessibilityElement(children: .contain)
    }
}
