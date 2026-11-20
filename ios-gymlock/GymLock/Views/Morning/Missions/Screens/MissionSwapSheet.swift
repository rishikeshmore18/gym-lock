//
//  MissionSwapSheet.swift
//  GymLock · mission screens
//
//  The earned swap: a bottom sheet of the other missions this device can verify, two to a row.
//  It is only ever presented after the current mission has failed twice, or when it cannot run at
//  all (see MissionAttemptLedger). It never accuses: the copy is "same goal, whatever is easiest".
//

import SwiftUI

struct MissionSwapSheet: View {
    let missions: [ActivationMissionType]
    let style: MissionStyle
    let onPick: (ActivationMissionType) -> Void
    /// Offered at the foot of the sheet when given (the first page's honest way out).
    var onSkip: (() -> Void)?

    var body: some View {
        GeometryReader { proxy in
            // Width-led scale: the sheet is not the whole screen, so height must not shrink it.
            let scale = MissionLayout.scale(
                for: CGSize(
                    width: proxy.size.width,
                    height: proxy.size.width / MissionLayout.designWidth * MissionLayout.designHeight
                )
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Try a different one")
                        .font(.system(size: 22 * scale, weight: .bold))
                        .tracking(-0.33 * scale)
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 8 * scale)

                    Text("Same goal. Whatever is easiest right now.")
                        .font(.system(size: 16 * scale))
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.top, 2 * scale)
                        .padding(.bottom, 14 * scale)

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12 * scale),
                            GridItem(.flexible(), spacing: 12 * scale),
                        ],
                        spacing: 12 * scale
                    ) {
                        ForEach(missions) { mission in
                            tile(mission, scale: scale)
                        }
                    }

                    if let onSkip {
                        Button {
                            MissionHaptic.selection.play()
                            onSkip()
                        } label: {
                            Text("Skip and start my window")
                                .font(.system(size: 16 * scale, weight: .medium))
                                .foregroundStyle(Theme.inkSecondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: max(56, 56 * scale))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4 * scale)
                    }
                }
                .padding(.horizontal, 18 * scale)
                .padding(.bottom, 20 * scale)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.white.ignoresSafeArea())
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    private func tile(_ mission: ActivationMissionType, scale: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20 * scale, style: .continuous)
        return Button {
            MissionHaptic.selection.play()
            onPick(mission)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                MissionIcon(figure: MissionFigure(mission), style: style, size: 44 * scale, color: Theme.ink)
                    .frame(width: 44 * scale, height: 44 * scale, alignment: .leading)

                Spacer(minLength: 0)

                Text(MissionCopy.shortTitle(mission))
                    .font(.system(size: 16 * scale, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(MissionCopy.chip(mission))
                    .font(.system(size: 13 * scale))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(14 * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 120 * scale)
            .background(Theme.canvas, in: shape)
            .overlay { shape.strokeBorder(Theme.border, lineWidth: 1) }
            .contentShape(shape)
        }
        .buttonStyle(MissionPressStyle())
        .accessibilityLabel("\(MissionCopy.shortTitle(mission)), \(MissionCopy.chip(mission))")
    }
}
