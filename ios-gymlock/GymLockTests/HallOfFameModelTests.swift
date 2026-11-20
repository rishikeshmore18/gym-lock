import Foundation
import Testing

@testable import GymLock

/// Fixed calendar (Gregorian, UTC, weeks start Monday) so no result depends on
/// where or when the suite runs. Exact month and weekday text is only asserted
/// for English, because the model formats in the user's locale.
struct HallOfFameModelTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }()

    private static let isEnglish = Locale.current.language.languageCode?.identifier == "en"

    private func date(_ y: Int, _ m: Int, _ d: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func photo(_ date: Date, dayZero: Bool = false) -> ProgressPhoto {
        let id = UUID()
        return ProgressPhoto(
            id: id,
            createdAt: date,
            fileName: "\(id).jpg",
            thumbnailName: "\(id)-thumb.jpg",
            source: .camera,
            isDayZero: dayZero
        )
    }

    private func frames(_ photos: [ProgressPhoto], install: Date) -> [HallOfFameFrame] {
        HallOfFameModel.frames(photos: photos, installDate: install, calendar: calendar)
    }

    // MARK: Demo

    @Test func demoFramesCarryNoDatesOrDays() {
        let result = frames([], install: date(2026, 11, 1))
        #expect(result.count == ProgressPhotoDemoArtwork.frameCount)
        #expect(HallOfFameModel.demoFrameCount == ProgressPhotoDemoArtwork.frameCount)
        for frame in result {
            #expect(frame.date == nil)
            #expect(frame.dayNumber == nil)
            #expect(frame.dateText == nil)
            #expect(frame.dayText == nil)
            #expect(HallOfFameModel.counterText(for: frame, total: result.count) == nil)
        }
        // Newest first: demo 3 is latest, demo 0 is Day 0.
        #expect(result.first?.id == "demo-3")
        #expect(result.first?.marker == .latest)
        #expect(result.last?.id == "demo-0")
        #expect(result.last?.marker == .dayZero)
        #expect(HallOfFameModel.availableLevels(isDemo: true) == [.photo, .day])
        #expect(HallOfFameModel.availableLevels(isDemo: false) == HallOfFameLevel.allCases)
    }

    @Test func demoWeekAndMonthFallBackToOneUntitledSection() {
        let result = frames([], install: date(2026, 11, 1))
        for level in [HallOfFameLevel.week, .month] {
            let sections = HallOfFameModel.sections(result, level: level, calendar: calendar)
            #expect(sections.count == 1)
            #expect(sections[0].id == "all")
            #expect(sections[0].title == nil)
            #expect(sections[0].frames.count == result.count)
        }
    }

    // MARK: Day numbers

    @Test func installDayIsDayZeroWhateverTheTimeOfDay() {
        let install = date(2026, 11, 1, 8)
        let result = frames([photo(date(2026, 11, 1, 23))], install: install)
        #expect(result[0].dayNumber == 0)
        #expect(result[0].dayText == "DAY 0")
    }

    @Test func dayNumbersCountCalendarDaysAndNeverGoNegative() {
        let install = date(2026, 11, 10, 23)
        let result = frames(
            [photo(date(2026, 11, 8)), photo(date(2026, 11, 11, 1)), photo(date(2026, 11, 13))],
            install: install
        )
        // Newest first. Nov 11 01:00 is one calendar day after a 23:00 install on Nov 10.
        #expect(result.map(\.dayNumber) == [3, 1, 0])
    }

    // MARK: Markers

    @Test func onboardingPhotoIsDayZeroEvenOnAnotherDay() {
        let result = frames(
            [photo(date(2026, 10, 1), dayZero: true), photo(date(2026, 11, 5))],
            install: date(2026, 11, 1)
        )
        #expect(result.last?.marker == .dayZero)
        #expect(result.last?.markerText == "Day 0")
        #expect(result.first?.marker == .latest)
        #expect(result.first?.markerText == "Latest")
    }

    @Test func oldestPhotoOnInstallDayIsDayZero() {
        let result = frames(
            [photo(date(2026, 11, 1, 20)), photo(date(2026, 11, 5))],
            install: date(2026, 11, 1, 8)
        )
        #expect(result.last?.marker == .dayZero)
    }

    @Test func oldestPhotoOnALaterDayIsFirstNotDayZero() {
        let result = frames(
            [photo(date(2026, 11, 3)), photo(date(2026, 11, 5)), photo(date(2026, 11, 9))],
            install: date(2026, 11, 1)
        )
        #expect(result.map(\.marker) == [.latest, nil, .first])
        #expect(result.last?.markerText == "1st")
    }

    @Test func singlePhotoGetsOnlyTheOpeningMarker() {
        let later = frames([photo(date(2026, 11, 3))], install: date(2026, 11, 1))
        #expect(later.count == 1)
        #expect(later[0].marker == .first)

        let same = frames([photo(date(2026, 11, 1))], install: date(2026, 11, 1))
        #expect(same[0].marker == .dayZero)
    }

    @Test func ordinalsAreChronologicalWhateverTheInputOrder() {
        let result = frames(
            [photo(date(2026, 11, 9)), photo(date(2026, 11, 3)), photo(date(2026, 11, 5))],
            install: date(2026, 11, 1)
        )
        #expect(result.map(\.ordinal) == [3, 2, 1])
    }

    // MARK: Sections

    @Test func weekGroupingSkipsEmptyWeeks() {
        // Weeks start Monday: Nov 2-8 (two photos), Nov 9-15 (none), Nov 16-22 (one).
        let all = frames(
            [photo(date(2026, 11, 2)), photo(date(2026, 11, 4)), photo(date(2026, 11, 18))],
            install: date(2026, 11, 1)
        )
        let sections = HallOfFameModel.sections(all, level: .week, calendar: calendar)
        #expect(sections.count == 2)
        #expect(sections.map { $0.frames.count } == [1, 2])
        #expect(sections.map(\.countText) == ["1 PHOTO", "2 PHOTOS"])
        #expect(sections.allSatisfy { $0.id.hasPrefix("w-2026-") })
        #expect(Set(sections.map(\.id)).count == 2)
    }

    @Test(.enabled(if: HallOfFameModelTests.isEnglish))
    func weekTitlesUseAPlainHyphen() {
        let all = frames(
            [photo(date(2026, 10, 27)), photo(date(2026, 11, 1)), photo(date(2026, 11, 18))],
            install: date(2026, 10, 20)
        )
        let titles = HallOfFameModel.sections(all, level: .week, calendar: calendar).compactMap(\.title)
        #expect(titles == ["NOV 16 - 22", "OCT 26 - NOV 1"])
        #expect(titles.allSatisfy { !$0.contains("\u{2013}") && !$0.contains("\u{2014}") })
    }

    @Test(.enabled(if: HallOfFameModelTests.isEnglish))
    func weekTitleIncludesYearsOnlyAcrossNewYear() {
        let all = frames([photo(date(2025, 12, 31)), photo(date(2026, 1, 2))], install: date(2025, 12, 1))
        let titles = HallOfFameModel.sections(all, level: .week, calendar: calendar).compactMap(\.title)
        #expect(titles == ["DEC 29, 2025 - JAN 4, 2026"])
    }

    @Test(.enabled(if: HallOfFameModelTests.isEnglish))
    func monthTitlesAndCounts() {
        let all = frames(
            [photo(date(2026, 10, 30)), photo(date(2026, 11, 2)), photo(date(2026, 11, 20))],
            install: date(2026, 10, 1)
        )
        let sections = HallOfFameModel.sections(all, level: .month, calendar: calendar)
        #expect(sections.map(\.title) == ["NOVEMBER 2026", "OCTOBER 2026"])
        #expect(sections.map(\.countText) == ["2 PHOTOS", "1 PHOTO"])
        #expect(sections.map(\.id) == ["m-2026-11", "m-2026-10"])
    }

    @Test func monthGroupingSkipsEmptyMonths() {
        let all = frames(
            [photo(date(2026, 8, 5)), photo(date(2026, 11, 2))],
            install: date(2026, 8, 1)
        )
        let sections = HallOfFameModel.sections(all, level: .month, calendar: calendar)
        #expect(sections.map(\.id) == ["m-2026-11", "m-2026-08"])
    }

    @Test func dayAndPhotoLevelsAreOneFramePerSectionWithoutHeaders() {
        let all = frames(
            [photo(date(2026, 11, 2)), photo(date(2026, 11, 4))],
            install: date(2026, 11, 1)
        )
        for level in [HallOfFameLevel.photo, .day] {
            let sections = HallOfFameModel.sections(all, level: level, calendar: calendar)
            #expect(sections.map(\.id) == ["d-2026-11-04", "d-2026-11-02"])
            #expect(sections.allSatisfy { $0.title == nil && $0.countText == nil && $0.frames.count == 1 })
        }
    }

    // MARK: Counter and levels

    @Test func counterTextIsOrdinalOfTotal() {
        let all = frames(
            [photo(date(2026, 11, 2)), photo(date(2026, 11, 4)), photo(date(2026, 11, 6))],
            install: date(2026, 11, 1)
        )
        #expect(HallOfFameModel.counterText(for: all[0], total: all.count) == "3 of 3")
        #expect(HallOfFameModel.counterText(for: all[2], total: all.count) == "1 of 3")
    }

    @Test func levelsStepFinerAndCoarser() {
        #expect(HallOfFameLevel.photo.finer == nil)
        #expect(HallOfFameLevel.day.finer == .photo)
        #expect(HallOfFameLevel.month.coarser == nil)
        #expect(HallOfFameLevel.week.coarser == .month)
        #expect(HallOfFameLevel.allCases.map(\.columns) == [1, 1, 2, 3])
        #expect(HallOfFameLevel.allCases.map(\.title) == ["Photo", "Day", "Week", "Month"])
    }
}
