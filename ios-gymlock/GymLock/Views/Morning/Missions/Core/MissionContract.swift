//
//  MissionContract.swift
//  GymLock
//
//  The shared contract for the mission screens (Matrix and Ridge). Three parts are built against
//  this file: Matrix/ (dot figures), Ridge/ (the living painted world) and Screens/ (the two pages
//  and the runners). Every type here is prefixed `Mission` so nothing collides with WakeIntro
//  (Wake*, MatrixWake*, RidgeWake*, RidgeWorld, RidgeAssets) or the hero card (MX, RW).
//
//  Layout: every page lays out with SwiftUI stacks and `MissionLayout.scale(for:)`, which fits a
//  390 x 844 design to any iPhone or iPad (min of width/390 and height/844, capped 1.25, column
//  centred), so the composition is identical everywhere.
//

import SwiftUI
import UIKit

/// The look, from the user's hero card choice (`@AppStorage("gymlock.home.cardStyle")`).
nonisolated enum MissionStyle: String, Sendable {
    case matrix, ridge
    init(_ style: HeroCardStyle) { self = style == .matrix ? .matrix : .ridge }
}

/// Every drawable figure: the seven missions plus the two helpers.
nonisolated enum MissionFigure: String, CaseIterable, Sendable {
    case shoes, shoesOn, steps, water, bag, door, mirror, check, camera

    /// `ActivationMissionType` is default-isolated (main actor), so this mapping is too.
    @MainActor init(_ mission: ActivationMissionType) {
        switch mission {
        case .showGymShoes: self = .shoes
        case .shoesOn: self = .shoesOn
        case .twentySteps: self = .steps
        case .grabWater: self = .water
        case .gymBag: self = .bag
        case .walkToDoor: self = .door
        case .mirrorBoost: self = .mirror
        }
    }
}

/// How a Matrix figure is drawn.
nonisolated enum MissionDotMode: Sendable { case fill, outline }

/// The camera page's live state. Drives the ghost, the status pill and the Ridge band.
nonisolated enum MissionCameraPhase: Equatable, Sendable { case aim, found, checking, done }

// MARK: - The views each part provides (signatures are fixed)
//
// Matrix/ provides:
//   struct MissionMatrixFigureView: View {
//       init(figure: MissionFigure, mode: MissionDotMode = .fill, dot: Color, board: Color?,
//            accent: Color? = Theme.accent, level: Double = 1, pulseToken: Int = 0,
//            cols: Int = 32, rows: Int = 22, onLand: ((MissionFigure) -> Void)? = nil)
//   }
//   - Changing `figure` flies the dots into the new figure (spring, left-to-right sweep, ~0.7 s);
//     onLand fires once when it has formed. Changing `pulseToken` plays a brightness ripple.
//     `level` eases the figure's brightness. Idle loop per figure. Reduce Motion = crossfade.
//   struct MissionDotIcon: View { init(figure: MissionFigure, size: CGFloat, color: Color) }
//
// Ridge/ provides:
//   struct MissionRidgeCardView: View {
//       init(mission: MissionFigure, onLand: (() -> Void)? = nil)
//   }   // the living hero card (light dawn): mist, sun glow, birds, footsteps to the coral gym,
//       // the mission's badge on the trail; changing `mission` pans to its framing.
//   struct MissionRidgeBandView: View { init(phase: MissionCameraPhase) }
//       // the dark strip under the camera controls; .done brings first light.
//   struct MissionRidgeIcon: View { init(figure: MissionFigure, size: CGFloat, color: Color) }
//       // SF Symbols-style line icon (stroke size/12).
//
// Screens/ provides the pages, using only the above plus the app's own types.

/// One icon in the current style (Matrix dots or Ridge line).
struct MissionIcon: View {
    let figure: MissionFigure
    let style: MissionStyle
    var size: CGFloat = 30
    var color: Color = Theme.ink

    var body: some View {
        switch style {
        case .matrix: MissionDotIcon(figure: figure, size: size, color: color)
        case .ridge: MissionRidgeIcon(figure: figure, size: size, color: color)
        }
    }
}

/// Fits the 390 x 844 design to the screen.
nonisolated enum MissionLayout {
    static let designWidth: CGFloat = 390
    static let designHeight: CGFloat = 844
    static let maxScale: CGFloat = 1.25
    static func scale(for size: CGSize) -> CGFloat {
        max(0.7, min(size.width / designWidth, size.height / designHeight, maxScale))
    }
}

/// Haptics for the mission screens, mapped onto the app's `Haptics` utility.
///
/// `Haptics` itself has no settings check, so `play()` checks the app's own haptics switch first
/// (Profile > Preferences > haptics, `HeroHapticPlayer.shared.isEnabled`, key
/// "gymlock.hero.haptics", default on). The system haptics switch is honoured by UIKit itself.
/// Always go through `MissionHaptic`, never `Haptics` directly, on the mission screens.
enum MissionHaptic {
    case soft, selection, medium, rigid, success, warning
    /// The soft give of a control on finger-down (`Haptics.press`).
    case press

    /// The app-level haptics switch.
    @MainActor static var isEnabled: Bool { HeroHapticPlayer.shared.isEnabled }

    @MainActor func play() {
        guard Self.isEnabled else { return }
        switch self {
        case .soft: Haptics.soft()
        case .selection: Haptics.selection()
        case .medium: Haptics.medium()
        case .rigid: UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1)
        case .success: Haptics.commit()
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .press: Haptics.press()
        }
    }
}
