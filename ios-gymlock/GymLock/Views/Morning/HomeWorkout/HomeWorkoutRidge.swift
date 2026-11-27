//
//  HomeWorkoutRidge.swift
//  GymLock · shared geometry for the two Ridge home workout looks
//
//  The world image is RidgeAssets.shared.image(.worldDawn) (900 x 1948 image px), the same baked
//  world the "can't today" Ridge look draws. Skyline samples copied from RidgeCantTodayB.
//

import SwiftUI

enum HomeWorkoutRidge {
    static let worldW: CGFloat = 900
    static let worldH: CGFloat = 1948
    /// Main peak tip, image px.
    static let apex = CGPoint(x: 500, y: 1072)

    /// Skyline of the painted range, one sample per 10 image px (x 0 to 900, y in image px).
    static let skyline: [Double] = [
    1266, 1262, 1259, 1259, 1259, 1257, 1246, 1239, 1239, 1239, 1232, 1232, 1232, 1251, 1253, 1253, 1259, 1261, 1270, 1289,
    1310, 1292, 1292, 1292, 1299, 1299, 1279, 1278, 1278, 1278, 1291, 1291, 1263, 1247, 1230, 1230, 1230, 1239, 1232, 1232,
    1232, 1193, 1163, 1104, 1104, 1096, 1096, 1096, 1091, 1071, 1071, 1071, 1077, 1089, 1102, 1142, 1136, 1136, 1136, 1179,
    1219, 1230, 1226, 1226, 1226, 1227, 1250, 1262, 1285, 1286, 1286, 1283, 1283, 1283, 1286, 1240, 1240, 1240, 1243, 1257,
    1275, 1257, 1257, 1257, 1272, 1293, 1295, 1286, 1262, 1262, 1262
]

    /// Skyline height (image px) at image x, linearly interpolated.
    static func skylineY(_ x: Double) -> Double {
        let f = min(90, max(0, x / 10))
        let i = Int(f.rounded(.down))
        let j = min(90, i + 1)
        return skyline[i] + (skyline[j] - skyline[i]) * (f - Double(i))
    }

    /// Cover-fit of the world into a viewport, anchored high like the prototype:
    /// k = max(vw / 900, vh / 1948), ox = (vw - iw) / 2, oy = -(ih - vh) * 0.1.
    struct Fit {
        let k: CGFloat
        let ox: CGFloat
        let oy: CGFloat
        init(size: CGSize) {
            k = max(size.width / HomeWorkoutRidge.worldW, size.height / HomeWorkoutRidge.worldH)
            ox = (size.width - HomeWorkoutRidge.worldW * k) / 2
            oy = -(HomeWorkoutRidge.worldH * k - size.height) * 0.1
        }
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: ox + p.x * k, y: oy + p.y * k) }
    }

    /// The sky region above the skyline as a closed path in image px (clip for "behind the ridge").
    static func skyPath(liftedBy lift: Double = 1.5) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -4000))
        for i in 0...90 { p.addLine(to: CGPoint(x: Double(i) * 10, y: skyline[i] - lift)) }
        p.addLine(to: CGPoint(x: 900, y: -4000))
        p.closeSubpath()
        return p
    }
}
