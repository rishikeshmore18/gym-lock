import Foundation

// MARK: - Levels

/// How closely the Hall of Fame is zoomed in, from one photo to a month grid.
///
/// Ordered finer to coarser so a pinch can step along the cases without a
/// lookup table, and so the capsule lists them in the order a thumb travels.
nonisolated enum HallOfFameLevel: Int, CaseIterable, Identifiable, Sendable {
    case photo, day, week, month

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .photo: "Photo"
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }

    /// Cells per row. Photo and Day are one tall frame at a time; Week is two
    /// across and Month three across, as on the reference contact sheet. The
    /// grid holds every day of the period, in calendar order.
    var columns: Int {
        switch self {
        case .photo: 1
        case .day: 1
        case .week: 2
        case .month: 3
        }
    }

    /// How far back the film reaches even with no history, so there is
    /// always a strip of dated frames to scroll through.
    var minimumSpan: (component: Calendar.Component, value: Int) {
        switch self {
        case .photo, .day: (.day, 14)
        case .week: (.weekOfYear, 7)
        case .month: (.month, 2)
        }
    }

    /// The level a pinch-out lands on, or nil at the finest.
    var finer: HallOfFameLevel? { HallOfFameLevel(rawValue: rawValue - 1) }

    /// The level a pinch-in lands on, or nil at the coarsest.
    var coarser: HallOfFameLevel? { HallOfFameLevel(rawValue: rawValue + 1) }
}

// MARK: - Frames

/// One photograph on the film, with every label already worked out.
///
/// The text is resolved once, here, with the calendar the grouping used. If
/// each view formatted its own, a frame could say one day in its print and
/// another in its section header whenever the two disagreed about time zones.
nonisolated struct HallOfFameFrame: Identifiable, Hashable, Sendable {
    enum Content: Hashable, Sendable {
        case photo(ProgressPhoto)
        /// One quarter of the bundled demonstration strip.
        case demo(index: Int)
    }

    /// Same cases and meaning as `ProgressPhotoSlide.Marker`; a separate type
    /// only so this model stays free of the card's stack.
    enum Marker: Hashable, Sendable {
        case dayZero, first, latest
    }

    /// `photo.id.uuidString`, or `demo-<i>`.
    let id: String
    let content: Content
    /// Nil for demo frames: they must never imply a real date.
    let date: Date?
    /// Whole calendar days since the install day, never negative. Nil for demo.
    let dayNumber: Int?
    let marker: Marker?
    /// 1-based position in time, oldest first, whatever order frames are shown in.
    let ordinal: Int
    var markerText: String?
    var dateText: String?
    var dayText: String?

    init(
        id: String,
        content: Content,
        date: Date?,
        dayNumber: Int?,
        marker: Marker?,
        ordinal: Int,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.content = content
        self.date = date
        self.dayNumber = dayNumber
        self.marker = marker
        self.ordinal = ordinal
        self.markerText = switch marker {
        case .dayZero: "Day 0"
        case .first: "1st"
        case .latest: "Latest"
        case nil: nil
        }
        self.dateText = date.map {
            $0.formatted(HallOfFameModel.format(calendar).month(.abbreviated).day()).uppercased()
        }
        self.dayText = dayNumber.map { "DAY \($0)" }
    }

    var isDemo: Bool {
        if case .demo = content { return true }
        return false
    }
}

/// One calendar day in a Week or Month grid.
nonisolated struct HallOfFameCell: Identifiable, Hashable, Sendable {
    /// `c-yyyy-mm-dd`, or `p-<section>-<i>` for a calendar offset slot.
    let id: String
    /// Start of the day; nil for an offset slot before the 1st of a month.
    let date: Date?
    /// The newest photo taken that day; nil draws a plain black cell.
    let frame: HallOfFameFrame?
    /// Every photo taken that day, newest first (for scroll anchoring).
    var dayFrameIDs: [String] = []
    /// "NOV 5"; nil for an offset slot.
    var dateText: String? = nil
    /// "DAY 73" counted from the install day; nil before install or unknown.
    var dayText: String? = nil

    /// An offset slot: takes up a grid position but draws nothing.
    var isPadding: Bool { date == nil }
}

/// A run of frames under one header, or a single frame at the finer levels.
nonisolated struct HallOfFameSection: Identifiable, Hashable, Sendable {
    /// Stable across rebuilds so scroll anchoring survives a level change:
    /// `d-yyyy-mm-dd`, `w-yyyy-ww` or `m-yyyy-mm`.
    let id: String
    /// Week range or month name; nil where the frame's own print says it all.
    let title: String?
    /// "3 PHOTOS"; nil where there is no header.
    let countText: String?
    /// Newest first.
    let frames: [HallOfFameFrame]
    /// Week and Month only: every day of the period in calendar order (oldest
    /// first, whatever order sections are shown in), empty days included.
    var cells: [HallOfFameCell] = []
}

// MARK: - Model

nonisolated enum HallOfFameModel {
    /// Mirrors `ProgressPhotoDemoArtwork.frameCount`, which is main-actor
    /// isolated and so cannot be read from here. A test pins the two together.
    static let demoFrameCount = 4

    /// Date.FormatStyle bound to the caller's calendar and time zone, so a
    /// test calendar and the user's calendar each get their own answer.
    fileprivate static func format(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: .current, calendar: calendar, timeZone: calendar.timeZone)
    }

    /// Every frame, newest first.
    ///
    /// Newest first because the film is read from the present backwards and
    /// ends on where it started. With no photos the bundled demo frames stand
    /// in, carrying no dates or day numbers at all.
    static func frames(
        photos: [ProgressPhoto],
        installDate: Date,
        calendar: Calendar = .current
    ) -> [HallOfFameFrame] {
        let sorted = photos.sorted { $0.createdAt < $1.createdAt }
        guard !sorted.isEmpty else { return demoFrames(calendar: calendar) }

        let installDay = calendar.startOfDay(for: installDate)
        let opening = openingMarker(for: sorted[0], installDate: installDate, calendar: calendar)
        let lastIndex = sorted.count - 1

        return sorted.enumerated().map { index, photo in
            // A single photo is the start of the journey, not the end of it,
            // so index 0 takes the opening marker before `latest` is considered.
            let marker: HallOfFameFrame.Marker? = if index == 0 {
                opening
            } else if index == lastIndex {
                .latest
            } else {
                nil
            }
            let days = calendar.dateComponents(
                [.day],
                from: installDay,
                to: calendar.startOfDay(for: photo.createdAt)
            ).day ?? 0
            return HallOfFameFrame(
                id: photo.id.uuidString,
                content: .photo(photo),
                date: photo.createdAt,
                dayNumber: max(days, 0),
                marker: marker,
                ordinal: index + 1,
                calendar: calendar
            )
        }
        .reversed()
    }

    /// Groups frames for a level, newest section first.
    ///
    /// Week and Month cover every period from the oldest photo's to the one
    /// containing `now`, empty ones included, and every day inside them, so a
    /// gap reads as black cells rather than disappearing. Demo frames carry no
    /// dates, so with no real photos those levels show the current week or
    /// month as empty days: real dates, no implied photos.
    ///
    /// Day shows one page per photo and one empty, dated page per day without
    /// one. Photo shows real photos only, and falls back to the empty day
    /// pages when there are none, so the film is never blank. Every level
    /// reaches back at least `minimumSpan` and to the install day.
    static func sections(
        _ frames: [HallOfFameFrame],
        level: HallOfFameLevel,
        calendar: Calendar = .current,
        now: Date = Date(),
        installDate: Date? = nil
    ) -> [HallOfFameSection] {
        let dated = frames.filter { $0.date != nil }
        switch level {
        case .photo:
            if !frames.isEmpty {
                return singleFrameSections(frames, calendar: calendar)
            }
            return daySections([], level: level, calendar: calendar, now: now, installDate: installDate)
        case .day:
            // Demo frames carry no dates and keep their own pages.
            if dated.isEmpty, !frames.isEmpty {
                return singleFrameSections(frames, calendar: calendar)
            }
            return daySections(dated, level: level, calendar: calendar, now: now, installDate: installDate)
        case .week, .month:
            return gridSections(dated, level: level, calendar: calendar, now: now, installDate: installDate)
        }
    }

    /// The first day the film covers for a level.
    static func rangeStart(
        oldestPhoto: Date?,
        level: HallOfFameLevel,
        calendar: Calendar,
        now: Date,
        installDate: Date?
    ) -> Date {
        let span = level.minimumSpan
        var earliest = calendar.date(byAdding: span.component, value: -span.value, to: now) ?? now
        if let oldestPhoto { earliest = min(earliest, oldestPhoto) }
        if let installDate { earliest = min(earliest, installDate) }
        return calendar.startOfDay(for: earliest)
    }

    /// Every level is always offered; Week and Month show empty days when
    /// there is nothing to put in them.
    static func availableLevels(isDemo: Bool) -> [HallOfFameLevel] {
        HallOfFameLevel.allCases
    }

    /// "12 of 26" under the title at Photo level. Nil for demo, where a
    /// position in someone else's journey would mean nothing.
    static func counterText(for frame: HallOfFameFrame, total: Int) -> String? {
        guard !frame.isDemo else { return nil }
        return "\(frame.ordinal) of \(total)"
    }

    // MARK: Markers

    /// Whether the oldest photo has earned the words "Day 0".
    ///
    /// The same rule as `ProgressPhotoSlide.openingMarker`, restated with the
    /// caller's calendar so grouping and marking can never disagree about
    /// which day a photo was taken on.
    static func openingMarker(
        for oldest: ProgressPhoto,
        installDate: Date,
        calendar: Calendar
    ) -> HallOfFameFrame.Marker {
        if oldest.isDayZero { return .dayZero }
        return calendar.isDate(oldest.createdAt, inSameDayAs: installDate) ? .dayZero : .first
    }

    // MARK: Demo

    private static func demoFrames(calendar: Calendar) -> [HallOfFameFrame] {
        (0..<demoFrameCount).map { index in
            HallOfFameFrame(
                id: "demo-\(index)",
                content: .demo(index: index),
                date: nil,
                dayNumber: nil,
                marker: index == 0 ? .dayZero : (index == demoFrameCount - 1 ? .latest : nil),
                ordinal: index + 1,
                calendar: calendar
            )
        }
        .reversed()
    }

    // MARK: Grouping

    /// One section per frame, for the levels that show a single frame at a time.
    private static func singleFrameSections(
        _ frames: [HallOfFameFrame],
        calendar: Calendar
    ) -> [HallOfFameSection] {
        var used = Set<String>()
        return frames.map { frame in
            var id = frame.id
            if let date = frame.date {
                let c = calendar.dateComponents([.year, .month, .day], from: date)
                id = "d-\(pad(c.year, 4))-\(pad(c.month))-\(pad(c.day))"
            }
            // Two photos on one day would otherwise share an id, and a
            // ForEach over duplicate ids misplaces rows.
            if !used.insert(id).inserted {
                id += "-\(frame.id)"
                used.insert(id)
            }
            return HallOfFameSection(id: id, title: nil, countText: nil, frames: [frame])
        }
    }

    /// One cell for a calendar day, with its print text resolved.
    private static func cell(
        day: Date,
        frames dayFrames: [HallOfFameFrame],
        installDay: Date?,
        calendar: Calendar
    ) -> HallOfFameCell {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        var dayText: String?
        if let installDay, day >= installDay {
            let n = calendar.dateComponents([.day], from: installDay, to: day).day ?? 0
            dayText = "DAY \(max(n, 0))"
        }
        return HallOfFameCell(
            id: "c-\(pad(c.year, 4))-\(pad(c.month))-\(pad(c.day))",
            date: day,
            frame: dayFrames.first,
            dayFrameIDs: dayFrames.map(\.id),
            dateText: day.formatted(format(calendar).month(.abbreviated).day()).uppercased(),
            dayText: dayText
        )
    }

    /// One page per photo, and one empty page per day without a photo, from
    /// the start of the range to today. Newest first. `frames` must carry dates.
    private static func daySections(
        _ frames: [HallOfFameFrame],
        level: HallOfFameLevel,
        calendar: Calendar,
        now: Date,
        installDate: Date?
    ) -> [HallOfFameSection] {
        var byDay: [Date: [HallOfFameFrame]] = [:]
        for frame in frames {
            guard let date = frame.date else { continue }
            byDay[calendar.startOfDay(for: date), default: []].append(frame)
        }
        let dates = frames.compactMap(\.date)
        let start = rangeStart(
            oldestPhoto: dates.min(), level: level, calendar: calendar, now: now, installDate: installDate
        )
        let end = calendar.startOfDay(for: max(dates.max() ?? now, now))
        let installDay = installDate.map { calendar.startOfDay(for: $0) }

        var sections: [HallOfFameSection] = []
        var used = Set<String>()
        var day = start
        var guardCount = 0
        while day <= end, guardCount < 3_000 {
            guardCount += 1
            let dayFrames = byDay[day] ?? []
            let c = calendar.dateComponents([.year, .month, .day], from: day)
            let dayID = "d-\(pad(c.year, 4))-\(pad(c.month))-\(pad(c.day))"
            if dayFrames.isEmpty {
                used.insert(dayID)
                sections.append(HallOfFameSection(
                    id: dayID,
                    title: nil,
                    countText: nil,
                    frames: [],
                    cells: [cell(day: day, frames: [], installDay: installDay, calendar: calendar)]
                ))
            } else {
                // Frames arrive newest first; pages within a day go oldest first
                // here and the whole list is reversed at the end.
                for frame in dayFrames.reversed() {
                    var id = dayID
                    if !used.insert(id).inserted {
                        id += "-\(frame.id)"
                        used.insert(id)
                    }
                    sections.append(HallOfFameSection(id: id, title: nil, countText: nil, frames: [frame]))
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        return sections.reversed()
    }

    /// Week or month sections over a continuous range of periods, each with
    /// one cell per day. `frames` must all carry dates.
    private static func gridSections(
        _ frames: [HallOfFameFrame],
        level: HallOfFameLevel,
        calendar: Calendar,
        now: Date,
        installDate: Date? = nil
    ) -> [HallOfFameSection] {
        let component: Calendar.Component = level == .week ? .weekOfYear : .month

        // Frames by day, newest first within a day (frames arrive newest first).
        var byDay: [Date: [HallOfFameFrame]] = [:]
        for frame in frames {
            guard let date = frame.date else { continue }
            byDay[calendar.startOfDay(for: date), default: []].append(frame)
        }

        let dates = frames.compactMap(\.date)
        let latest = max(dates.max() ?? now, now)
        let earliest = rangeStart(
            oldestPhoto: dates.min(), level: level, calendar: calendar, now: now, installDate: installDate
        )
        let installDay = installDate.map { calendar.startOfDay(for: $0) }
        guard let first = calendar.dateInterval(of: component, for: earliest),
              let last = calendar.dateInterval(of: component, for: latest)
        else { return [] }

        var sections: [HallOfFameSection] = []
        var periodStart = first.start
        // Hard stop so a broken calendar can never spin forever.
        var guardCount = 0
        while periodStart <= last.start, guardCount < 2_000 {
            guardCount += 1
            guard let interval = calendar.dateInterval(of: component, for: periodStart) else { break }

            let id: String
            let title: String
            if level == .week {
                let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: interval.start)
                id = "w-\(pad(c.yearForWeekOfYear, 4))-\(pad(c.weekOfYear))"
                title = weekTitle(interval: interval, calendar: calendar)
            } else {
                let c = calendar.dateComponents([.year, .month], from: interval.start)
                id = "m-\(pad(c.year, 4))-\(pad(c.month))"
                title = interval.start.formatted(format(calendar).month(.wide).year()).uppercased()
            }

            var cells: [HallOfFameCell] = []
            var periodFrames: [HallOfFameFrame] = []
            var day = interval.start
            while day < interval.end {
                let dayFrames = byDay[day] ?? []
                cells.append(cell(day: day, frames: dayFrames, installDay: installDay, calendar: calendar))
                periodFrames.append(contentsOf: dayFrames.reversed())
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = calendar.startOfDay(for: next)
            }

            sections.append(HallOfFameSection(
                id: id,
                title: title,
                countText: countText(periodFrames.count),
                // Days were walked oldest first; sections keep frames newest first.
                frames: periodFrames.reversed(),
                cells: cells
            ))
            periodStart = interval.end
        }
        return sections.reversed()
    }

    // MARK: Text

    /// "NOV 16 - 22", "OCT 27 - NOV 2", or with years when the week crosses
    /// New Year ("DEC 29, 2025 - JAN 4, 2026"). A plain hyphen, never a dash.
    private static func weekTitle(interval: DateInterval, calendar: Calendar) -> String {
        let start = interval.start
        // `end` is the first instant of the next week; the last day is a day earlier.
        let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end

        let a = calendar.dateComponents([.year, .month], from: start)
        let b = calendar.dateComponents([.year, .month], from: end)

        let text: String
        if a.year != b.year {
            let style = format(calendar).month(.abbreviated).day().year()
            text = "\(start.formatted(style)) - \(end.formatted(style))"
        } else if a.month != b.month {
            let style = format(calendar).month(.abbreviated).day()
            text = "\(start.formatted(style)) - \(end.formatted(style))"
        } else {
            let first = format(calendar).month(.abbreviated).day()
            let last = format(calendar).day()
            text = "\(start.formatted(first)) - \(end.formatted(last))"
        }
        return text.uppercased()
    }

    private static func countText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "PHOTO" : "PHOTOS")"
    }

    /// Zero-padded, so ids sort and read like dates.
    private static func pad(_ value: Int?, _ width: Int = 2) -> String {
        let text = String(value ?? 0)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}
