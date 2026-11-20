import Testing
import SwiftUI
@testable import GymLock

struct ReelSceneTests {
    static let layout = ReelLayout(size: CGSize(width: 393, height: 852), safeTop: 59, stripWidth: 329, stripTop: 125)

    private func entries(_ p: ProjectionTransform) -> [Double] {
        [p.m11, p.m12, p.m13, p.m21, p.m22, p.m23, p.m31, p.m32, p.m33].map { Double($0) }
    }

    @Test func poseAtTotalIsIdentityAndLive() {
        let pose = ReelScene.pose(at: ReelTimeline.total, layout: Self.layout)
        let id = entries(ProjectionTransform(CATransform3DIdentity))
        for (a, b) in zip(entries(pose.floorTransform), id) { #expect(abs(a - b) < 1e-9) }
        #expect(pose.filmClipLength == .infinity)
        #expect(pose.chromeOpacity == 1)
        #expect(pose.events.contains(.stripSeated))
        #expect(!pose.reelVisible)
    }

    @Test func rollingDoesNotSlip() {
        let g = ReelGeo(Self.layout)
        let h = 0.0005 // ms
        var t = ReelMath.tRoll0 + 50
        while t < ReelMath.tBl0 - 50 {
            let a = ReelScene3D.at(t - h, g), b = ReelScene3D.at(t + h, g)
            let centre = (b.d - a.d) / (2 * h)              // distance along the floor per ms
            let spin = (b.spin - a.spin) / (2 * h)          // rad per ms
            let contact = centre + g.rr * spin              // contact point velocity
            #expect(abs(contact) < 1e-3 * max(1, abs(centre)))
            t += 50
        }
        // laid film never longer than the arc rolled
        let mid = ReelScene3D.at(2200, g)
        #expect(mid.lc <= mid.d + 1e-9)
        #expect(mid.lc > 0)
    }

    @Test func eventsAreMonotonic() {
        var previous: ReelEvents = []
        var t = 0.0
        while t <= ReelTimeline.total + 0.2 {
            let e = ReelScene.pose(at: t, layout: Self.layout).events
            #expect(e.isSuperset(of: previous))
            previous = e
            t += 0.01
        }
        #expect(previous.contains([.reelLanded, .titleComplete, .stripSeated]))
    }

    @Test func closeStartsWhereIntroEnds() {
        let a = ReelScene.closePose(at: 0, layout: Self.layout)
        let b = ReelScene.pose(at: ReelTimeline.total, layout: Self.layout)
        for (x, y) in zip(entries(a.floorTransform), entries(b.floorTransform)) { #expect(abs(x - y) < 1e-12) }
        #expect(a.filmClipLength == b.filmClipLength)
        let end = ReelScene.closePose(at: ReelTimeline.closeTotal, layout: Self.layout)
        #expect(end.filmClipLength == 0)
    }
}
