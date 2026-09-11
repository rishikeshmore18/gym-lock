import Foundation
import Testing
@testable import GymLock

/// Tests for the two pieces of the Progress Photos card that are pure logic and
/// therefore worth pinning down: which photographs the stack picks, and what
/// the opening card is allowed to call itself.
///
/// Both are easy to get subtly wrong in ways a screenshot would never reveal —
/// a stack showing four photos from the same fortnight still looks correct.
@MainActor
struct ProgressPhotoSelectionTests {
    /// Photos at the given day offsets from a fixed origin, oldest first.
    private func photos(daysAgo: [Double]) -> [ProgressPhoto] {
        let origin = Date(timeIntervalSince1970: 1_700_000_000)
        return daysAgo.sorted(by: >).map { offset in
            ProgressPhoto(
                id: UUID(),
                createdAt: origin.addingTimeInterval(-offset * 86_400),
                fileName: "f.jpg",
                thumbnailName: "t.jpg",
                source: .camera
            )
        }
    }

    // MARK: Counts

    @Test("The stack shows every photo when there are four or fewer")
    func showsAllWhenFewer() {
        for count in 1...4 {
            let all = photos(daysAgo: (0..<count).map { Double($0) * 7 })
            let picked = ProgressPhotoSelection.representative(from: all)
            #expect(picked.count == count)
            #expect(picked.map(\.id) == all.map(\.id))
        }
    }

    @Test("A long history is reduced to exactly four")
    func capsAtFour() {
        for count in 5...60 {
            let all = photos(daysAgo: (0..<count).map { Double($0) * 3 })
            #expect(ProgressPhotoSelection.representative(from: all).count == 4)
        }
    }

    @Test("No photograph is ever shown twice")
    func neverDuplicates() {
        for count in 1...40 {
            let all = photos(daysAgo: (0..<count).map { Double($0) * 5 })
            let ids = ProgressPhotoSelection.representative(from: all).map(\.id)
            #expect(Set(ids).count == ids.count)
        }
    }

    @Test("Identical timestamps still fill four distinct slots")
    func identicalDatesStillFillFour() {
        // Every photo claims the same moment, so time carries no information
        // and the sampler has to fall back to position without repeating.
        let all = photos(daysAgo: Array(repeating: 0, count: 9))
        let picked = ProgressPhotoSelection.representativeIndices(in: all)
        #expect(picked.count == 4)
        #expect(Set(picked).count == 4)
    }

    // MARK: Ends

    @Test("The first and latest photos are always kept")
    func keepsBothEnds() {
        for count in 5...30 {
            let all = photos(daysAgo: (0..<count).map { Double($0) * 4 })
            let picked = ProgressPhotoSelection.representativeIndices(in: all)
            #expect(picked.first == 0)
            #expect(picked.last == count - 1)
        }
    }

    @Test("Dragging keeps the focused photo on screen, ends included")
    func windowKeepsFocusAndEnds() {
        let all = photos(daysAgo: (0..<20).map { Double($0) * 4 })
        for focus in all.indices {
            let window = ProgressPhotoSelection.window(around: focus, in: all)
            #expect(window.count == 4)
            #expect(Set(window).count == 4)
            #expect(window.contains(focus))
            #expect(window.contains(0))
            #expect(window.contains(all.count - 1))
        }
    }

    // MARK: Spacing

    /// The middle cards must be chosen by date, not by position.
    ///
    /// This history is deliberately lopsided: eleven photos crammed into the
    /// first eleven days, then three spread across the following eleven
    /// months. Sampling by array position would pick positions 0, 4, 8 and 13 —
    /// three of the four cards from that opening fortnight — and show the user
    /// a "progress" stack in which almost nothing changes.
    @Test("Middle cards follow the calendar, not the array")
    func samplesByDateNotPosition() {
        // Large `daysAgo` is older, so this cluster is the *oldest* stretch.
        let clustered = (0..<11).map { 330 - Double($0) }
        let spread: [Double] = [210, 90, 0]
        let all = photos(daysAgo: clustered + spread)

        let picked = ProgressPhotoSelection.representative(from: all)
        #expect(picked.count == 4)

        let origin = all[0].createdAt
        let days = picked.map { $0.createdAt.timeIntervalSince(origin) / 86_400 }
        let span = days[3]
        #expect(span == 330)

        // Each interior card should sit near its third of the elapsed time.
        // Generous tolerance — the point is that it reaches for the midpoints
        // at all, not that a photo happens to exist exactly there.
        #expect(abs(days[1] - span / 3) < span * 0.2)
        #expect(abs(days[2] - span * 2 / 3) < span * 0.2)

        // And concretely: only the opening card may come from the cluster.
        // Position-based sampling would take three from it.
        let inCluster = days.filter { $0 <= 10 }.count
        #expect(inCluster == 1)
    }

    @Test("Evenly spaced photos give evenly spaced cards")
    func evenHistoryStaysEven() {
        let all = photos(daysAgo: (0..<13).map { Double($0) * 10 })
        let picked = ProgressPhotoSelection.representativeIndices(in: all)
        #expect(picked == [0, 4, 8, 12])
    }

    // MARK: Day 0 versus 1st

    @Test("A photo taken on install day earns Day 0")
    func labelsInstallDayAsDayZero() {
        let all = photos(daysAgo: [0, 30, 60])
        let marker = ProgressPhotoSlide.openingMarker(
            for: all[0],
            installDate: all[0].createdAt
        )
        #expect(marker == .dayZero)
    }

    @Test("A user who started later gets 1st, not Day 0")
    func labelsLateStarterAsFirst() {
        let all = photos(daysAgo: [0, 30, 60])
        let marker = ProgressPhotoSlide.openingMarker(
            for: all[0],
            installDate: all[0].createdAt.addingTimeInterval(-45 * 86_400)
        )
        #expect(marker == .first)
        #expect(
            ProgressPhotoSlide(
                id: "x",
                content: .demo(index: 0),
                marker: .first,
                date: nil
            ).markerText == "1st"
        )
    }

    @Test("The onboarding capture stays Day 0 whatever its date")
    func onboardingCaptureIsAlwaysDayZero() {
        var photo = photos(daysAgo: [10])[0]
        photo.isDayZero = true
        let marker = ProgressPhotoSlide.openingMarker(
            for: photo,
            installDate: Date(timeIntervalSince1970: 0)
        )
        #expect(marker == .dayZero)
    }

    @Test("Only the two ends are labelled")
    func labelsOnlyTheEnds() {
        let all = photos(daysAgo: (0..<9).map { Double($0) * 10 })
        let slides = ProgressPhotoSlide.slides(for: all, installDate: all[0].createdAt)

        #expect(slides.count == 4)
        #expect(slides[0].markerText == "Day 0")
        #expect(slides[1].markerText == nil)
        #expect(slides[2].markerText == nil)
        #expect(slides[3].markerText == "Latest")
    }

    @Test("A single photo reads as the beginning, not the end")
    func singlePhotoIsAStart() {
        let all = photos(daysAgo: [0])
        let slides = ProgressPhotoSlide.slides(for: all, installDate: all[0].createdAt)
        #expect(slides.count == 1)
        #expect(slides[0].markerText == "Day 0")
    }

    @Test("Photos saved before Day 0 tracking existed still decode")
    func decodesLegacyPhotos() throws {
        // The stored shape as it was before `isDayZero` was added. A throwing
        // decoder here would take the user's whole history with it, because
        // the array is decoded in one piece.
        let legacy = """
        [{"id":"\(UUID().uuidString)","createdAt":760000000,\
        "fileName":"a.jpg","thumbnailName":"a-thumb.jpg","source":"camera"}]
        """
        let decoded = try JSONDecoder().decode(
            [ProgressPhoto].self,
            from: Data(legacy.utf8)
        )
        #expect(decoded.count == 1)
        #expect(decoded[0].isDayZero == false)
    }
}
