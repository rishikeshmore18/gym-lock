#if DEBUG
import SwiftUI

/// Preview fixtures for every frame state.
///
/// Debug only, never referenced from runtime code. Each fixture is a
/// hand-built `ShareContext`, so the frames can be looked at without a ledger,
/// a photo store or a morning behind them — and so the absent states (a
/// Receipt with no departure, a Journey with no percentage) are as easy to
/// look at as the present ones.
enum StoryFixtures {
    static let day = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 7, minute: 3)) ?? Date()

    static func streak(weeks: Int, thisWeek: Int = 2, goal: Int = 3) -> StreakSnapshot {
        StreakSnapshot(
            weeks: weeks,
            weeklyGoal: goal,
            thisWeekSessionDays: thisWeek,
            isThisWeekKept: thisWeek >= goal,
            freezesAvailable: 1,
            lastCompletedWeekWasFrozen: false,
            isLiveWeekPreArmed: false,
            liveWeekStart: day
        )
    }

    static let photo = ProgressPhoto(
        id: UUID(),
        createdAt: day,
        fileName: "fixture.jpg",
        thumbnailName: "fixture-thumb.jpg",
        source: .camera
    )

    static let dayZero = ProgressPhoto(
        id: UUID(),
        createdAt: day.addingTimeInterval(-29 * 86_400),
        fileName: "fixture-0.jpg",
        thumbnailName: "fixture-0-thumb.jpg",
        source: .camera,
        isDayZero: true
    )

    static func receipt(withWorkout: Bool) -> ReceiptTimeline {
        let alarm = day.addingTimeInterval(-48 * 60)
        return ReceiptTimeline(
            alarm: alarm,
            left: alarm.addingTimeInterval(29 * 60),
            arrived: day,
            workout: withWorkout ? day.addingTimeInterval(46 * 60) : nil
        )
    }

    static func context(
        photo: ProgressPhoto? = photo,
        weeks: Int = 6,
        thisWeek: Int = 2,
        outcome: SessionOutcomeKind? = .showedUp,
        minutes: Int? = nil,
        receipt: ReceiptTimeline? = receipt(withWorkout: true),
        journey: JourneySnapshot? = nil,
        comeback: ComebackInfo? = nil,
        milestone: Milestone? = nil,
        history: FrameHistory = .everything
    ) -> ShareContext {
        ShareContext(
            referenceDay: day,
            photo: photo,
            streak: streak(weeks: weeks, thisWeek: thisWeek),
            outcome: outcome.map { SessionOutcome(date: day, kind: $0, minutes: minutes) },
            receipt: receipt,
            arrivedAt: receipt?.arrived ?? day,
            verifiedVisitsTotal: 12,
            verifiedVisitsThisWeek: 2,
            quick20ThisWeek: 0,
            sessionDaysThisWeek: thisWeek,
            journey: journey,
            comeback: comeback,
            milestone: milestone,
            installDate: day.addingTimeInterval(-29 * 86_400),
            history: history
        )
    }

    /// A brand-new user: Clean only, everything else locked.
    static var newUser: ShareContext {
        context(
            weeks: 0, thisWeek: 1, outcome: nil, receipt: nil,
            journey: JourneySnapshot(dayNumber: 3, verifiedVisits: 0, completion: nil, due: 0, dayZeroPhoto: nil),
            history: .none
        )
    }

    /// The whole editor over a fixture, for looking at the rail and the
    /// All Frames sheet without a real morning.
    static func editor(_ context: ShareContext, assets: StoryAssets = assets) -> StoryEditorModel {
        StoryEditorModel(fixtureContext: context, assets: assets, origin: .progressPhoto(photo))
    }

    static let journey30 = JourneySnapshot(
        dayNumber: 30, verifiedVisits: 12, completion: 0.83, due: 12, dayZeroPhoto: dayZero
    )
    static let journeyNoPercent = JourneySnapshot(
        dayNumber: 100, verifiedVisits: 41, completion: nil, due: 0, dayZeroPhoto: nil
    )
    static let comeback = ComebackInfo(
        missedDay: day.addingTimeInterval(-2 * 86_400),
        returnDay: day
    )

    /// Demo artwork stands in for the user's photo.
    static var assets: StoryAssets {
        StoryAssets(photo: ProgressPhotoDemoArtwork.frame(2), dayZero: ProgressPhotoDemoArtwork.frame(0))
    }
}

/// The editor chrome over a fixture model: canvas, rail and share bar.
private struct FixtureEditor: View {
    @State var model: StoryEditorModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            StoryEditableCanvas(model: model, canvasSize: CGSize(width: 320, height: 320 / model.format.ratio))
                .overlay(alignment: .bottom) {
                    FramePreviewRail(model: model) { model.select($0) }
                        .frame(width: 320)
                        .padding(.bottom, 10)
                }
        }
        .sheet(isPresented: $model.isShowingAllFrames) {
            AllFramesSheet(model: model) { model.select($0) }
        }
        .preferredColorScheme(.dark)
    }
}

/// One frame at preview size on a black stage.
private struct FixtureCanvas: View {
    let context: ShareContext
    let frame: ShareFrame
    var format: StoryFormat = .story
    var assets: StoryAssets = StoryFixtures.assets

    var body: some View {
        let size = CGSize(width: 320, height: 320 / format.ratio)
        ZStack {
            Color.black.ignoresSafeArea()
            StoryCanvasView(
                context: context,
                frame: frame,
                format: format,
                assets: assets,
                transform: .default,
                layouts: .defaults(for: frame, format: format),
                canvasSize: size,
                isAnimated: true
            )
            .clipShape(.rect(cornerRadius: 28))
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("1 · Clean") { FixtureCanvas(context: StoryFixtures.context(), frame: .clean) }
#Preview("2 · Showed Up") { FixtureCanvas(context: StoryFixtures.context(), frame: .showedUp) }
#Preview("3 · Momentum 6") { FixtureCanvas(context: StoryFixtures.context(weeks: 6, thisWeek: 3), frame: .momentum) }
#Preview("4 · Momentum 127") { FixtureCanvas(context: StoryFixtures.context(weeks: 127), frame: .momentum) }
#Preview("5 · Receipt with workout") { FixtureCanvas(context: StoryFixtures.context(), frame: .receipt) }
#Preview("6 · Receipt three rows") {
    FixtureCanvas(context: StoryFixtures.context(receipt: StoryFixtures.receipt(withWorkout: false)), frame: .receipt)
}
#Preview("7 · Receipt unavailable → frames offered") {
    let context = StoryFixtures.context(receipt: nil)
    return VStack(alignment: .leading, spacing: 8) {
        Text("frames offered without a departure event:")
        ForEach(ShareFrameAvailability.frames(for: context)) { Text("· \($0.title)") }
        Text(ShareFrameAvailability.frames(for: context).contains(.receipt) ? "RECEIPT PRESENT (bug)" : "receipt absent ✓")
            .foregroundStyle(Theme.accent)
    }
    .padding()
}
#Preview("8 · Journey Day 30 with inset") {
    FixtureCanvas(context: StoryFixtures.context(outcome: nil, receipt: nil, journey: StoryFixtures.journey30), frame: .journey)
}
#Preview("9 · Journey DAY 100, no percentage") {
    FixtureCanvas(context: StoryFixtures.context(outcome: nil, receipt: nil, journey: StoryFixtures.journeyNoPercent), frame: .journey)
}
#Preview("10 · Comeback") {
    FixtureCanvas(context: StoryFixtures.context(comeback: StoryFixtures.comeback), frame: .comeback)
}
#Preview("11 · The Save") {
    FixtureCanvas(context: StoryFixtures.context(outcome: .homeWorkout, minutes: 20, receipt: nil), frame: .quickSave)
}
#Preview("12 · Milestone 10 visits") {
    FixtureCanvas(context: StoryFixtures.context(milestone: Milestone(kind: .verifiedVisits(10))), frame: .milestone)
}
#Preview("13 · Milestone FIRST MONTH") {
    FixtureCanvas(context: StoryFixtures.context(milestone: Milestone(kind: .streakWeeks(4))), frame: .milestone)
}
#Preview("14 · Post · Showed Up") { FixtureCanvas(context: StoryFixtures.context(), frame: .showedUp, format: .post) }
#Preview("14 · Post · Momentum") { FixtureCanvas(context: StoryFixtures.context(thisWeek: 3), frame: .momentum, format: .post) }
#Preview("14 · Post · Receipt") { FixtureCanvas(context: StoryFixtures.context(), frame: .receipt, format: .post) }
#Preview("15 · Card mode · Showed Up") {
    FixtureCanvas(context: StoryFixtures.context(photo: nil), frame: .showedUp, assets: .none)
}
#Preview("15 · Card mode · Receipt") {
    FixtureCanvas(context: StoryFixtures.context(photo: nil), frame: .receipt, assets: .none)
}
#Preview("16 · Long strings · Donnerstag") {
    FixtureCanvas(
        context: StoryFixtures.context(comeback: StoryFixtures.comeback),
        frame: .comeback
    )
    .environment(\.locale, Locale(identifier: "de_DE"))
}
#Preview("17 · Rail · mature user") {
    FixtureEditor(model: StoryFixtures.editor(StoryFixtures.context(weeks: 6, thisWeek: 3, comeback: StoryFixtures.comeback)))
}
#Preview("17 · Rail · new user (Clean + 2 locked)") {
    FixtureEditor(model: StoryFixtures.editor(StoryFixtures.newUser))
}
#Preview("17 · Rail · card mode") {
    FixtureEditor(model: StoryFixtures.editor(StoryFixtures.context(photo: nil), assets: .none))
}
#Preview("18 · All Frames sheet · new user") {
    AllFramesSheet(model: StoryFixtures.editor(StoryFixtures.newUser)) { _ in }
        .background(Color.black)
}
#Preview("16 · Long strings · DAY 100") {
    FixtureCanvas(context: StoryFixtures.context(outcome: nil, receipt: nil, journey: StoryFixtures.journeyNoPercent), frame: .journey)
}
#endif
