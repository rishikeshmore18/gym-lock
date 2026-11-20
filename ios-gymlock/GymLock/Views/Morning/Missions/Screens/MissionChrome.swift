//
//  MissionChrome.swift
//  GymLock · mission screens
//
//  The shared pieces of the mission pages: the layout metrics, the press style, the progress row,
//  the Start capsule, quiet text buttons, the glass treatment, the card chrome and the art card.
//  Everything is sized through `MissionMetrics`, so the 390 x 844 design looks the same on every
//  iPhone and iPad.
//

import SwiftUI

// MARK: - Metrics

/// Scales the 390 x 844 design to the screen. `m(17)` is 17 design points at this screen's scale.
struct MissionMetrics {
    /// Design-to-screen scale (`MissionLayout.scale`).
    let scale: CGFloat
    /// The area inside the safe areas.
    let size: CGSize
    let insets: EdgeInsets

    init(_ proxy: GeometryProxy) {
        size = proxy.size
        insets = proxy.safeAreaInsets
        let full = CGSize(
            width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
            height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
        )
        scale = MissionLayout.scale(for: full)
    }

    func callAsFunction(_ value: CGFloat) -> CGFloat { value * scale }

    /// A touch target: 56 pt at design size, never smaller than 56 pt on screen.
    var tapSize: CGFloat { max(56, 56 * scale) }

    /// The centred column the design lives in.
    var columnWidth: CGFloat { min(size.width, MissionLayout.designWidth * scale) }
    /// The column minus the 18 pt gutters.
    var contentWidth: CGFloat { max(0, columnWidth - 36 * scale) }
}

// MARK: - Palette

enum MissionPalette {
    /// The camera stage (#0A0A0B).
    static let stage = Color(red: 0.039, green: 0.039, blue: 0.043)
    /// The inactive rail between progress steps (#D9D8D3).
    static let rail = Color(red: 0.851, green: 0.847, blue: 0.827)
}

// MARK: - Press

/// A calm press: scale 0.97 on touch-down with the soft press haptic, a spring back on release.
struct MissionPressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var playsHaptic = true

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        MissionPressBody(configuration: configuration, scale: scale, playsHaptic: playsHaptic)
    }
}

private struct MissionPressBody: View {
    let configuration: ButtonStyleConfiguration
    let scale: CGFloat
    let playsHaptic: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let release: Animation? = reduceMotion || configuration.isPressed
            ? nil
            : .spring(response: 0.3, dampingFraction: 0.8)

        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .animation(release, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed && playsHaptic { MissionHaptic.press.play() }
            }
            .onAppear { Haptics.preparePress() }
    }
}

/// The shutter: a white disc inside a white ring that gives a little when pressed.
struct MissionShutterStyle: ButtonStyle {
    let scale: CGFloat

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white, lineWidth: 4 * scale)
                .frame(width: 78 * scale, height: 78 * scale)
            Circle()
                .fill(Color.white)
                .frame(width: 62 * scale, height: 62 * scale)
                .scaleEffect(configuration.isPressed ? 0.88 : 1)
                .animation(configuration.isPressed ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }
        .frame(width: 78 * scale, height: 78 * scale)
        .contentShape(Circle())
    }
}

// MARK: - Glass

extension View {
    /// Frosted white-on-dark glass for the camera controls.
    func missionGlass<S: Shape>(in shape: S) -> some View {
        background(Color.white.opacity(0.16), in: shape)
            .background(.ultraThinMaterial, in: shape)
    }

    /// The white card: 24 pt corners, a hairline and a soft lift (the prototype's hero card).
    func missionCard(_ m: MissionMetrics) -> some View {
        let shape = RoundedRectangle(cornerRadius: m(24), style: .continuous)
        return self
            .background(Color.white, in: shape)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Theme.ink.opacity(0.06), lineWidth: 1) }
            .shadow(color: Theme.ink.opacity(0.06), radius: m(15), x: 0, y: m(10))
    }
}

// MARK: - Progress row

/// "Up, Get ready, Gym 7:05": an ink check, a coral dot (the page's one coral), a hollow ring.
struct MissionProgressRow: View {
    let metrics: MissionMetrics
    /// The gym time, "7:05". Nil leaves the last step out.
    let gymTime: String?
    /// The "Get ready" dot is coral. Ridge's art already carries the page's one coral (the gym), so
    /// the page passes false there and the dot is ink.
    var usesCoral = true

    private enum Mark { case done, now, next }

    var body: some View {
        let m = metrics
        HStack(spacing: m(8)) {
            step(.done, "Up")
            rail(on: true)
            step(.now, "Get ready")
            if let gymTime {
                rail(on: false)
                step(.next, "Gym \(gymTime)")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let gymTime else { return "Up. Get ready, now." }
        return "Up. Get ready, now. Gym \(gymTime)."
    }

    private func step(_ mark: Mark, _ label: String) -> some View {
        let m = metrics
        return HStack(spacing: m(6)) {
            ZStack {
                switch mark {
                case .done:
                    Circle().fill(Theme.ink)
                    Image(systemName: "checkmark")
                        .font(.system(size: m(10), weight: .heavy))
                        .foregroundStyle(Color.white)
                case .now:
                    Circle().fill(usesCoral ? Theme.accent : Theme.ink).frame(width: m(8), height: m(8))
                case .next:
                    Circle().strokeBorder(Theme.inkTertiary, lineWidth: 1.5).frame(width: m(8), height: m(8))
                }
            }
            .frame(width: m(20), height: m(20))

            Text(label)
                .font(.system(size: m(13), weight: .semibold))
                .foregroundStyle(mark == .next ? Theme.inkTertiary : Theme.ink)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func rail(on: Bool) -> some View {
        let m = metrics
        return Capsule()
            .fill(on ? Theme.ink : MissionPalette.rail)
            .frame(minWidth: m(10), maxWidth: m(28))
            .frame(height: 1.5)
    }
}

// MARK: - Buttons

/// The primary action: a 64 pt ink capsule, an icon disc, "Start", the seconds and an arrow.
/// Press scales to 0.97 on touch-down with the soft press haptic; release plays a medium haptic.
struct MissionStartButton: View {
    let metrics: MissionMetrics
    let figure: MissionFigure
    let style: MissionStyle
    let seconds: Int
    let action: () -> Void

    var body: some View {
        let m = metrics
        Button {
            MissionHaptic.medium.play()
            action()
        } label: {
            HStack(spacing: m(14)) {
                MissionIcon(figure: figure, style: style, size: m(28), color: .white)
                    .frame(width: m(40), height: m(40))
                    .background(Color.white.opacity(0.12), in: .circle)

                Text("Start")
                    .font(.system(size: m(17), weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(seconds) s")
                    .font(.system(size: m(17), weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))

                Image(systemName: "arrow.right")
                    .font(.system(size: m(17), weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.leading, m(12))
            .padding(.trailing, m(24))
            .frame(maxWidth: .infinity)
            .frame(height: m(64))
            .background(Theme.ink, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(MissionPressStyle())
        .accessibilityLabel("Start, \(seconds) seconds")
    }
}

/// Quiet text on the page: 56 pt tall, no chrome.
struct MissionQuietButton: View {
    let metrics: MissionMetrics
    let title: String
    var isEmphasised = false
    var tint: Color = Theme.inkSecondary
    let action: () -> Void

    var body: some View {
        let m = metrics
        Button {
            MissionHaptic.soft.play()
            action()
        } label: {
            Text(title)
                .font(.system(size: m(isEmphasised ? 17 : 16), weight: isEmphasised ? .semibold : .medium))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: m.tapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(MissionPressStyle(scale: 0.98, playsHaptic: false))
    }
}

// MARK: - Done

/// "Got it. Your window is open." on a light or a dark page.
struct MissionDonePanel: View {
    let metrics: MissionMetrics
    var isDark = false

    var body: some View {
        let m = metrics
        VStack(spacing: m(8)) {
            Text("Got it.")
                .font(.system(size: m(36), weight: .bold))
                .tracking(-0.9 * m.scale)
                .foregroundStyle(isDark ? Color.white : Theme.ink)
            Text("Your window is open.")
                .font(.system(size: m(17)))
                .foregroundStyle(isDark ? Color.white.opacity(0.72) : Theme.inkSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Art

/// The mission's picture in the chosen style: Matrix dots on a quiet board, or the Ridge world.
struct MissionArt: View {
    let figure: MissionFigure
    let style: MissionStyle
    var pulseToken = 0
    var onLand: () -> Void = {}

    var body: some View {
        switch style {
        case .matrix:
            MissionMatrixFigureView(
                figure: figure,
                mode: .fill,
                dot: Theme.ink,
                board: Theme.ink.opacity(0.07),
                level: 1,
                pulseToken: pulseToken,
                cols: 32,
                rows: 22,
                onLand: { _ in onLand() }
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
        case .ridge:
            MissionRidgeCardView(mission: figure, onLand: onLand)
        }
    }
}

/// The art alone in a white card (the steps and mirror pages).
struct MissionArtCard: View {
    let metrics: MissionMetrics
    let figure: MissionFigure
    let style: MissionStyle
    var pulseToken = 0

    var body: some View {
        MissionArt(figure: figure, style: style, pulseToken: pulseToken)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .missionCard(metrics)
            .accessibilityHidden(true)
    }
}
