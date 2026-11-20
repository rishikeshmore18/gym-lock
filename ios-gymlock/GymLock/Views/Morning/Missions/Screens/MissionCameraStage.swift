//
//  MissionCameraStage.swift
//  GymLock · mission screens
//
//  The full-bleed camera page. It draws state it is handed and owns none: the runner decides when
//  a photo is checked, how a miss is worded and when the swap is earned.
//
//  Layers, bottom to top: the live preview (or a dark feed), a top and bottom shade, a sparse dot
//  grid at 6%, the flash, then the column: glass close and title, the aiming ghost, the status pill,
//  the controls (the earned "Try a different one", the shutter, the light) and the privacy line.
//  Under the controls sits the Ridge band (a dark strip) or, in Matrix, a dot horizon.
//
//  The image is never shown back or kept: the shutter hands the capture to the verifier through the
//  runner and the preview simply carries on.
//

import AVFoundation
import Foundation
import SwiftUI

/// A calm explanation shown in place of the ghost when the camera cannot be used.
struct MissionCameraNotice: Equatable {
    let title: String
    let detail: String
}

struct MissionCameraStage: View {
    let style: MissionStyle
    let figure: MissionFigure
    let title: String
    let subtitle: String
    let phase: MissionCameraPhase
    let pillText: String
    /// The live session, or nil while the camera is not ready (a dark feed shows instead).
    let previewSession: AVCaptureSession?
    let notice: MissionCameraNotice?
    let isFlashing: Bool
    let canTakePhoto: Bool
    let showsLight: Bool
    let isTorchOn: Bool
    /// True only once the swap is earned (two failed attempts) or the camera cannot run.
    let canSwap: Bool
    let onClose: () -> Void
    let onShutter: () -> Void
    let onLight: () -> Void
    let onSwap: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let m = MissionMetrics(proxy)
            ZStack {
                column(m)
                band(m)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background { backdrop }
        .environment(\.colorScheme, .dark)
        .blocksHeroHaptics("camera")
    }

    // MARK: Backdrop

    private var backdrop: some View {
        ZStack {
            if let previewSession {
                MissionCameraPreview(session: previewSession)
                    .allowsHitTesting(false)
            } else {
                RadialGradient(
                    colors: [
                        Color(red: 0.169, green: 0.180, blue: 0.204),
                        Color(red: 0.082, green: 0.090, blue: 0.106),
                        Color(red: 0.035, green: 0.035, blue: 0.043),
                    ],
                    center: UnitPoint(x: 0.3, y: 0.18),
                    startRadius: 0,
                    endRadius: 620
                )
            }

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.45), location: 0),
                    .init(color: Color.clear, location: 0.22),
                    .init(color: Color.clear, location: 0.6),
                    .init(color: Color.black.opacity(0.55), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            MissionCameraDotGrid()
                .allowsHitTesting(false)

            Color.white
                .opacity(isFlashing ? 0.9 : 0)
                .animation(isFlashing ? nil : .easeOut(duration: 0.2), value: isFlashing)
                .allowsHitTesting(false)
        }
        .background(MissionPalette.stage)
        .ignoresSafeArea()
    }

    // MARK: Column

    private func column(_ m: MissionMetrics) -> some View {
        VStack(spacing: 0) {
            header(m)
            ghost(m)
            controls(m)
            Color.clear.frame(height: m(56))
        }
        .padding(.top, m(8))
        .padding(.horizontal, m(18))
        .frame(width: m.columnWidth)
    }

    private func header(_ m: MissionMetrics) -> some View {
        HStack(spacing: 0) {
            Button {
                MissionHaptic.selection.play()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: m(17), weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: m(44), height: m(44))
                    .missionGlass(in: Circle())
                    .frame(width: m.tapSize, height: m.tapSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            VStack(spacing: m(2)) {
                Text(title)
                    .font(.system(size: m(17), weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.system(size: m(13)))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            Color.clear.frame(width: m.tapSize, height: 1)
        }
        .frame(height: m.tapSize)
    }

    // MARK: Ghost

    private func ghost(_ m: MissionMetrics) -> some View {
        ZStack {
            if let notice {
                VStack(spacing: m(8)) {
                    Text(notice.title)
                        .font(.system(size: m(22), weight: .bold))
                        .foregroundStyle(Color.white)
                    Text(notice.detail)
                        .font(.system(size: m(16)))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, m(24))
                .accessibilityElement(children: .combine)
            } else {
                switch style {
                case .matrix:
                    MissionMatrixFigureView(
                        figure: phase == .done ? .check : figure,
                        mode: .outline,
                        dot: Color.white,
                        board: nil,
                        accent: nil,
                        level: phase == .aim ? 0.55 : 1,
                        pulseToken: 0,
                        cols: 30,
                        rows: 24
                    )
                    .frame(maxWidth: m(330))
                    .aspectRatio(30.0 / 24.0, contentMode: .fit)
                    .accessibilityHidden(true)
                case .ridge:
                    MissionCameraRings(
                        figure: figure,
                        level: phase == .aim ? 0.55 : 1,
                        isDone: phase == .done
                    )
                    .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Controls

    private func controls(_ m: MissionMetrics) -> some View {
        VStack(spacing: m(16)) {
            if phase == .done {
                MissionDonePanel(metrics: m, isDark: true)
                    .transition(.opacity)
            } else {
                pill(m)

                // The shutter stays dead centre; the swap and light buttons are
                // pinned to the edges over it, so their appearing or vanishing
                // never shifts it.
                ZStack {
                    Button(action: onShutter) {
                        Color.clear.frame(width: m(78), height: m(78))
                    }
                    .buttonStyle(MissionShutterStyle(scale: m.scale))
                    .disabled(!canTakePhoto)
                    .opacity(canTakePhoto ? 1 : 0.4)
                    .accessibilityLabel("Take the photo")

                    HStack(spacing: 0) {
                        if canSwap { swapButton(m) }
                        Spacer(minLength: 0)
                        if showsLight { lightButton(m) }
                    }
                    .frame(maxWidth: m.contentWidth)
                }

                HStack(spacing: m(6)) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: m(11), weight: .bold))
                    Text("Checked on your phone. Deleted right after.")
                        .font(.system(size: m(12)))
                }
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: m(200), alignment: .bottom)
        .padding(.bottom, m(12))
        .animation(.easeInOut(duration: 0.3), value: phase)
    }

    private func pill(_ m: MissionMetrics) -> some View {
        let shape = RoundedRectangle(cornerRadius: m(18), style: .continuous)
        return HStack(spacing: m(10)) {
            if phase == .checking {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color.white)
                    .scaleEffect(0.8)
                    .frame(width: m(16), height: m(16))
            } else {
                Circle()
                    .fill(phase == .found ? Theme.accent : Color.white.opacity(0.6))
                    .frame(width: m(8), height: m(8))
            }
            Text(pillText)
                .font(.system(size: m(17), weight: .semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, m(16))
        .padding(.vertical, m(7))
        .frame(minHeight: m(36))
        .frame(maxWidth: m.contentWidth)
        .missionGlass(in: shape)
        .animation(.easeInOut(duration: 0.3), value: phase)
        .accessibilityElement(children: .combine)
    }

    private func swapButton(_ m: MissionMetrics) -> some View {
        Button {
            MissionHaptic.selection.play()
            onSwap()
        } label: {
            Text("Try a different one")
                .font(.system(size: m(15), weight: .semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, m(14))
                .frame(maxWidth: m(128))
                .frame(height: m.tapSize)
                .missionGlass(in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(MissionPressStyle(playsHaptic: false))
    }

    private func lightButton(_ m: MissionMetrics) -> some View {
        Button {
            onLight()
        } label: {
            Image(systemName: isTorchOn ? "bolt.fill" : "bolt")
                .font(.system(size: m(20), weight: .semibold))
                .foregroundStyle(isTorchOn ? Color(red: 0.067, green: 0.067, blue: 0.067) : Color.white)
                .padding(.horizontal, m(24))
            .frame(height: m.tapSize)
            .background(Color.white.opacity(isTorchOn ? 1 : 0.16), in: Capsule())
            .background(.ultraThinMaterial, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(MissionPressStyle(playsHaptic: false))
        .accessibilityLabel(isTorchOn ? "Light on" : "Light off")
    }

    // MARK: Band

    private func band(_ m: MissionMetrics) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Group {
                switch style {
                case .ridge: MissionRidgeBandView(phase: phase)
                case .matrix: MissionCameraHorizon(scale: m.scale)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: m(56) + m.insets.bottom)
            .accessibilityHidden(true)
        }
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }
}

// MARK: - Dot grid and horizon

/// A sparse white dot grid at 6%, 24 pt apart, behind the ghost.
struct MissionCameraDotGrid: View {
    var body: some View {
        GeometryReader { proxy in
            let scale = MissionLayout.scale(for: proxy.size)
            Canvas { context, size in
                let pitch = 24 * scale
                let radius = 0.85 * scale
                var path = Path()
                var y = pitch / 2
                while y < size.height {
                    var x = pitch / 2
                    while x < size.width {
                        path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                        x += pitch
                    }
                    y += pitch
                }
                context.fill(path, with: .color(Color.white.opacity(0.06)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Matrix's strip under the camera controls: two rows of dots drifting sideways, fading downward.
struct MissionCameraHorizon: View {
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let elapsed = reduceMotion ? 0 : timeline.date.timeIntervalSince(start)
            let scale = self.scale
            Canvas { context, size in
                let pitch = 14 * scale
                let radius = 0.8 * scale
                // 140 pt every 9 s, as the prototype.
                let drift = CGFloat((elapsed / 9).truncatingRemainder(dividingBy: 1)) * 140 * scale
                var path = Path()
                var row: CGFloat = 0
                while row < 3 {
                    let y = 12 * scale + pitch * row + pitch / 2
                    var x = pitch / 2 - drift.truncatingRemainder(dividingBy: pitch)
                    while x < size.width + pitch {
                        path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                        x += pitch
                    }
                    row += 1
                }
                context.fill(path, with: .color(Color.white.opacity(0.55)))
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: Color.black, location: 0),
                    .init(color: Color.clear, location: 0.7),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Ridge ghost

/// Ridge's aiming ghost: the mission's thin line icon inside breathing contour rings. When the
/// photo is verified the rings fold in and the icon becomes a check.
struct MissionCameraRings: View {
    let figure: MissionFigure
    /// 0.55 while aiming, 1 once in frame and after.
    let level: Double
    let isDone: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var collapse: Double = 0
    @State private var brightness: Double = 0.55

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height) * 0.22
            ZStack {
                TimelineView(.animation(paused: reduceMotion)) { timeline in
                    MissionGhostRings(
                        collapse: collapse,
                        level: brightness,
                        size: size,
                        time: reduceMotion ? 0 : timeline.date.timeIntervalSince(start)
                    )
                }
                MissionRidgeIcon(figure: figure, size: size, color: Color.white)
                    .opacity((0.55 + 0.45 * brightness) * (1 - collapse))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear {
            collapse = isDone ? 1 : 0
            brightness = level
        }
        .onChange(of: isDone) { _, done in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.7)) { collapse = done ? 1 : 0 }
        }
        .onChange(of: level) { _, newLevel in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) { brightness = newLevel }
        }
    }
}

/// The rings and the check, drawn from animatable values so they fold in smoothly.
private struct MissionGhostRings: View, Animatable {
    var collapse: Double
    var level: Double
    let size: CGFloat
    let time: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(collapse, level) }
        set {
            collapse = newValue.first
            level = newValue.second
        }
    }

    var body: some View {
        // Plain values copied out of the view, so the Canvas closure reads no view state.
        let collapse = self.collapse
        let level = self.level
        let size = self.size
        let time = self.time
        return Canvas { context, canvas in
            let cx = canvas.width / 2
            let cy = canvas.height / 2
            let unit = Double(size)
            let r0 = unit * 0.72

            for ring in 0..<5 {
                let breath = sin(time * 1.1 - Double(ring) * 0.7) * unit * 0.03
                let radius: Double
                let alpha: Double
                if ring == 0 {
                    radius = r0 + breath * (1 - collapse)
                    alpha = 0.5 * (0.5 + 0.5 * level)
                } else {
                    let spread: Double = Double(ring) * unit * 0.2 + breath
                    let base: Double = 0.28 - Double(ring) * 0.045
                    radius = r0 + spread * (1 - collapse)
                    alpha = base * (1 - collapse) * (0.5 + 0.5 * level)
                }
                guard alpha > 0.01 else { continue }
                let rect = CGRect(
                    x: cx - CGFloat(radius),
                    y: cy - CGFloat(radius),
                    width: CGFloat(radius) * 2,
                    height: CGFloat(radius) * 2
                )
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(Color.white.opacity(alpha)),
                    lineWidth: ring == 0 ? 1.5 : 1
                )
            }

            if collapse > 0.02 {
                let r = CGFloat(r0)
                var check = Path()
                check.move(to: CGPoint(x: cx - r * 0.36, y: cy + r * 0.02))
                check.addLine(to: CGPoint(x: cx - r * 0.1, y: cy + r * 0.3))
                check.addLine(to: CGPoint(x: cx + r * 0.4, y: cy - r * 0.28))
                context.stroke(
                    check,
                    with: .color(Color.white.opacity(collapse)),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
}
