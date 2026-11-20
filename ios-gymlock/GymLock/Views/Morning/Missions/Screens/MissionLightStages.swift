//
//  MissionLightStages.swift
//  GymLock · mission screens
//
//  The two light pages of the runner: the step counter (also the first half of the door mission)
//  and the spoken line. Like the camera page they draw what they are handed and own no state.
//
//  Coral appears once per page: on Matrix the speech page's progress ring (Ridge's one coral is the
//  gym in its art, so its ring is ink); the step page has none of its own.
//

import SwiftUI

// MARK: - Back row

/// "Back" at the leading edge, 56 pt tall.
struct MissionBackRow: View {
    let metrics: MissionMetrics
    let action: () -> Void

    var body: some View {
        let m = metrics
        HStack {
            Button {
                MissionHaptic.selection.play()
                action()
            } label: {
                Text("Back")
                    .font(.system(size: m(17)))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(minWidth: m.tapSize, minHeight: m.tapSize, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .frame(height: m.tapSize)
    }
}

/// A quiet notice for a sensor that cannot be used, in place of the page's live part.
struct MissionNoticeBlock: View {
    let metrics: MissionMetrics
    let notice: MissionCameraNotice

    var body: some View {
        let m = metrics
        VStack(spacing: m(4)) {
            Text(notice.title)
                .font(.system(size: m(17), weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(notice.detail)
                .font(.system(size: m(15)))
                .foregroundStyle(Theme.inkSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Steps

struct MissionStepsStage: View {
    let style: MissionStyle
    let figure: MissionFigure
    let count: Int
    let target: Int
    let pulseToken: Int
    let isDone: Bool
    /// A line of quiet guidance ("Then one photo of the open door.").
    let note: String?
    let notice: MissionCameraNotice?
    let canSwap: Bool
    let onClose: () -> Void
    let onSwap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let m = MissionMetrics(proxy)
            let shown = min(count, target)
            let fraction = target > 0 ? Double(shown) / Double(target) : 0

            VStack(spacing: 0) {
                MissionBackRow(metrics: m, action: onClose)

                MissionArtCard(metrics: m, figure: figure, style: style, pulseToken: pulseToken)
                    .frame(height: m.size.height * 0.32)

                VStack(spacing: m(8)) {
                    Text("\(shown)")
                        .font(.system(size: m(112), weight: .bold))
                        .tracking(-4.5 * m.scale)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: shown)

                    Text("of \(target) steps")
                        .font(.system(size: m(17)))
                        .foregroundStyle(Theme.inkSecondary)

                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.border)
                        Capsule()
                            .fill(Theme.ink)
                            .frame(width: m(200) * CGFloat(fraction))
                    }
                    .frame(width: m(200), height: m(4))
                    .padding(.top, m(12))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: fraction)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(shown) of \(target) steps")

                VStack(spacing: m(8)) {
                    if isDone {
                        MissionDonePanel(metrics: m)
                            .transition(.opacity)
                    } else {
                        if let notice {
                            MissionNoticeBlock(metrics: m, notice: notice)
                        } else if let note {
                            Text(note)
                                .font(.system(size: m(13)))
                                .foregroundStyle(Theme.inkTertiary)
                                .multilineTextAlignment(.center)
                        }
                        if canSwap {
                            MissionQuietButton(
                                metrics: m,
                                title: "Try a different one",
                                isEmphasised: true,
                                tint: Theme.ink,
                                action: onSwap
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: m(128), alignment: .bottom)
            }
            .padding(.top, m(8))
            .padding(.horizontal, m(18))
            .padding(.bottom, m(12))
            .frame(width: m.columnWidth, height: m.size.height)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isDone)
    }
}

// MARK: - Speech

struct MissionSpeechStage: View {
    let style: MissionStyle
    let figure: MissionFigure
    let phrase: String
    /// 0...1 share of the phrase heard so far.
    let match: Double
    let isListening: Bool
    /// "Listening", "Getting ready to listen", "Tap the mic to try again".
    let statusText: String
    /// The live transcript. Held in memory only; the runner discards it on exit.
    let transcript: String
    let isDone: Bool
    let note: String?
    let notice: MissionCameraNotice?
    let canSwap: Bool
    let onClose: () -> Void
    let onSwap: () -> Void
    let onMic: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let m = MissionMetrics(proxy)

            VStack(spacing: 0) {
                MissionBackRow(metrics: m, action: onClose)

                MissionArtCard(metrics: m, figure: figure, style: style)
                    .frame(height: m.size.height * 0.26)

                Text(phrase)
                    .font(.system(size: m(28), weight: .bold))
                    .tracking(-0.56 * m.scale)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(m(2))
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, m(8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: m(8)) {
                    if isDone {
                        MissionDonePanel(metrics: m)
                            .transition(.opacity)
                    } else {
                        if let notice {
                            MissionNoticeBlock(metrics: m, notice: notice)
                        } else {
                            mic(m)
                            Text(statusText)
                                .font(.system(size: m(13)))
                                .foregroundStyle(Theme.inkTertiary)
                            if !transcript.isEmpty {
                                Text(transcript)
                                    .font(.system(size: m(13)))
                                    .foregroundStyle(Theme.inkTertiary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .transition(.opacity)
                            }
                            if let note {
                                Text(note)
                                    .font(.system(size: m(13), weight: .medium))
                                    .foregroundStyle(Theme.inkSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        if canSwap {
                            MissionQuietButton(
                                metrics: m,
                                title: "Try a different one",
                                isEmphasised: true,
                                tint: Theme.ink,
                                action: onSwap
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: m(168), alignment: .bottom)
            }
            .padding(.top, m(8))
            .padding(.horizontal, m(18))
            .padding(.bottom, m(12))
            .frame(width: m.columnWidth, height: m.size.height)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isDone)
    }

    /// Coral on Matrix. Ridge's art already carries the page's one coral (the gym), so its ring is ink.
    private var ringColor: Color { style == .matrix ? Theme.accent : Theme.ink }

    private func mic(_ m: MissionMetrics) -> some View {
        ZStack {
            Circle()
                .stroke(Theme.border, lineWidth: m(4))
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, match))))
                .stroke(ringColor, style: StrokeStyle(lineWidth: m(4), lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: match)

            Button {
                MissionHaptic.selection.play()
                onMic()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: m(34), weight: .regular))
                    .foregroundStyle(Color.white)
                    .frame(width: m(88), height: m(88))
                    .background(Theme.ink, in: .circle)
                    .contentShape(Circle())
            }
            .buttonStyle(MissionPressStyle(playsHaptic: false))
            .accessibilityLabel(isListening ? "Listening" : "Listen again")
        }
        .frame(width: m(112), height: m(112))
    }
}
