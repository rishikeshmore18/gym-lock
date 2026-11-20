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

    /// Frames per row. Photo and Day are one tall frame at a time; the grids
    /// only start at Week.
    var columns: Int {
        switch self {
        case .photo: 1
        case .day: 1
        case .week: 2
        case .month: 3
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

/// A run of frames under one header, or a single frame at the finer levels.
nonisolated struct HallOfFameSection: Identifiable, Hashable, Sendable {
    /// Stable across rebuilds so scroll anchoring survives a level change:
    /// `d-yyyy-mm-dd`, `w-yyyy-ww`, `m-yyyy-mm` or `all`.
    let id: String
    /// Week range or month name; nil where the frame's own print says it all.
    let title: String?
    /// "3 PHOTOS"; nil where there is no header.
    let countText: String?
    /// Newest first.
    let frames: [HallOfFameFrame]
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

    /// Groups frames for a level, keeping their newest-first order.
    ///
    /// Groups are built from the frames that exist, so a week or month with
    /// no photo never appears as an empty header. Demo frames have no dates to
    /// group by, so week and month fall back to one untitled section.
    static func sections(
        _ frames: [HallOfFameFrame],
        level: HallOfFameLevel,
        calendar: Calendar = .current
    ) -> [HallOfFameSection] {
        guard !frames.isEmpty else { return [] }

        switch level {
        case .photo, .day:
            return singleFrameSections(frames, calendar: calendar)
        case .week, .month:
            guard frames.allSatisfy({ $0.date != nil }) else {
                return [HallOfFameSection(id: "all", title: nil, countText: nil, frames: frames)]
            }
            return level == .week
                ? weekSections(frames, calendar: calendar)
                : monthSections(frames, calendar: calendar)
        }
    }

    /// The Week and Month levels need real dates, so demo offers only the two
    /// finer ones.
    static func availableLevels(isDemo: Bool) -> [HallOfFameLevel] {
        isDemo ? [.photo, .day] : HallOfFameLevel.allCases
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

    private static func weekSections(
        _ frames: [HallOfFameFrame],
        calendar: Calendar
    ) -> [HallOfFameSection] {
        var sections: [HallOfFameSection] = []
        var currentStart: Date?
        var bucket: [HallOfFameFrame] = []
        var bucketID = ""
        var bucketTitle = ""

        func flush() {
            guard !bucket.isEmpty else { return }
            sections.append(HallOfFameSection(
                id: bucketID,
                title: bucketTitle,
                countText: countText(bucket.count),
                frames: bucket
            ))
            bucket = []
        }

        for frame in frames {
            guard let date = frame.date,
                  let interval = calendar.dateInterval(of: .weekOfYear, for: date)
            else { continue }
            if currentStart != interval.start {
                flush()
                currentStart = interval.start
                let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: interval.start)
                bucketID = "w-\(pad(c.yearForWeekOfYear, 4))-\(pad(c.weekOfYear))"
                bucketTitle = weekTitle(interval: interval, calendar: calendar)
            }
            bucket.append(frame)
        }
        flush()
        return sections
    }

    private static func monthSections(
        _ frames: [HallOfFameFrame],
        calendar: Calendar
    ) -> [HallOfFameSection] {
        var sections: [HallOfFameSection] = []
        var currentKey: DateComponents?
        var bucket: [HallOfFameFrame] = []
        var bucketID = ""
        var bucketTitle = ""

        func flush() {
            guard !bucket.isEmpty else { return }
            sections.append(HallOfFameSection(
                id: bucketID,
                title: bucketTitle,
                countText: countText(bucket.count),
                frames: bucket
            ))
            bucket = []
        }

        for frame in frames {
            guard let date = frame.date else { continue }
            let key = calendar.dateComponents([.year, .month], from: date)
            if currentKey != key {
                flush()
                currentKey = key
                bucketID = "m-\(pad(key.year, 4))-\(pad(key.month))"
                bucketTitle = date.formatted(format(calendar).month(.wide).year()).uppercased()
            }
            bucket.append(frame)
        }
        flush()
        return sections
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
