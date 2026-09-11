import Foundation
import Observation

/// Holds what the Progress period card is currently showing.
///
/// The summaries are derived once and cached here rather than recomputed
/// inside a view body: the chart is redrawn on every frame of the expand
/// animation, and rebuilding a month of history underneath that would be work
/// done sixty times a second for a value that did not change.
///
/// There is no timer and no storage of its own. Everything comes from
/// `MomentumLog` and `MorningPlan`, and it recomputes only when those, or the
/// displayed month, actually change.
@Observable
final class ProgressPeriodModel {
    /// Any day inside the displayed month.
    private(set) var monthAnchor: Date
    private(set) var month: ProgressMonthSummary
    /// Index of the focused week, if the chart is at the week level.
    private(set) var selectedWeek: Int?
    /// The week the chart was last focused on.
    ///
    /// Kept after a collapse so the day bars still have a week to draw while
    /// they animate away, and so the month's bars know which column to fold
    /// back out of. Without it the zoom would have nothing to aim at on the
    /// way back and the days would simply vanish.
    private(set) var lastWeekIndex: Int = 0

    private var earliestMonth: Date
    private var latestMonth: Date
    /// Guards the expand/collapse animation against a rapid double tap
    /// starting two transitions at once.
    private var lastToggle: Date = .distantPast

    private let calendar: Calendar

    /// Roughly the length of the open/close spring.
    private static let transitionLockout: TimeInterval = 0.32

    init(now: Date = Date(), calendar: Calendar = .current) {
        self.calendar = calendar
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        monthAnchor = start
        month = .empty(monthStart: start, isCurrentMonth: true)
        earliestMonth = start
        latestMonth = start
    }

    // MARK: Derivation

    /// Rebuilds the displayed month from the ledger and the plan.
    func refresh(log: MomentumLog, plan: MorningPlan, schedule: GymSchedule, now: Date = Date()) {
        let bounds = ProgressAnalytics.monthBounds(
            log: log,
            plan: plan,
            schedule: schedule,
            now: now,
            calendar: calendar
        )
        earliestMonth = bounds.earliest
        latestMonth = bounds.latest

        // A month that has scrolled out of range — the last record was deleted,
        // say — is pulled back rather than left showing something unreachable.
        let clamped = min(max(monthAnchor, earliestMonth), latestMonth)
        if clamped != monthAnchor {
            monthAnchor = clamped
            selectedWeek = nil
        }

        month = ProgressAnalytics.monthSummary(
            containing: monthAnchor,
            log: log,
            plan: plan,
            schedule: schedule,
            now: now,
            calendar: calendar
        )

        // The open week keeps its place if it still exists, so live data
        // arriving while the user is reading never closes the card underneath
        // them. It only closes when that week genuinely no longer exists.
        if let selectedWeek, month.week(at: selectedWeek) == nil {
            self.selectedWeek = nil
        }
    }

    // MARK: Selection

    var selectedWeekSummary: ProgressWeekSummary? {
        selectedWeek.flatMap { month.week(at: $0) }
    }

    var isWeekExpanded: Bool { selectedWeek != nil }

    /// Opens a week. Returns false when the tap was swallowed as a bounce.
    @discardableResult
    func selectWeek(_ index: Int, now: Date = Date()) -> Bool {
        guard acceptsToggle(now: now), month.week(at: index) != nil else { return false }
        lastToggle = now
        selectedWeek = index
        lastWeekIndex = index
        return true
    }

    /// Closes the expanded week. Returns false when swallowed as a bounce.
    @discardableResult
    func collapseWeek(now: Date = Date()) -> Bool {
        guard selectedWeek != nil, acceptsToggle(now: now) else { return false }
        lastToggle = now
        selectedWeek = nil
        return true
    }

    private func acceptsToggle(now: Date) -> Bool {
        now.timeIntervalSince(lastToggle) >= Self.transitionLockout
    }

    // MARK: Week navigation

    /// Whether there is another week to step to at the week level.
    ///
    /// Clamped inside the displayed month on purpose: the bars are labelled
    /// with real dates, so sliding past the edge of the month would show days
    /// the header is not describing.
    func canStepWeek(by weeks: Int) -> Bool {
        guard let selectedWeek else { return false }
        return month.week(at: selectedWeek + weeks) != nil
    }

    /// Moves the focused week sideways. Returns false when swallowed.
    @discardableResult
    func stepWeek(by weeks: Int, now: Date = Date()) -> Bool {
        guard weeks != 0, let selectedWeek, acceptsToggle(now: now) else { return false }
        let target = selectedWeek + weeks
        guard month.week(at: target) != nil else { return false }
        lastToggle = now
        self.selectedWeek = target
        lastWeekIndex = target
        return true
    }

    // MARK: Month navigation

    var canGoBack: Bool { monthAnchor > earliestMonth }
    var canGoForward: Bool { monthAnchor < latestMonth }

    /// Steps the displayed month. Any open week closes first — its dates
    /// belong to the month being left behind.
    @discardableResult
    func step(by months: Int, log: MomentumLog, plan: MorningPlan, schedule: GymSchedule, now: Date = Date()) -> Bool {
        guard months != 0 else { return false }
        guard months < 0 ? canGoBack : canGoForward else { return false }
        guard let moved = calendar.date(byAdding: .month, value: months, to: monthAnchor) else {
            return false
        }

        monthAnchor = min(max(moved, earliestMonth), latestMonth)
        selectedWeek = nil
        refresh(log: log, plan: plan, schedule: schedule, now: now)
        return true
    }
}
