// DailyStrip — rolling 7-day completion strip + streak, pure model/logic.
//
// #774 (adopted `docs/v2/daily-calendar-streak-proposal.md`, owner
// adjudication 2026-07-15): a day counts as "completed" if ANY difficulty was
// completed that day (rule 1) — MS's mine-hit loss is deliberately absent
// from this model entirely (see `DailyHubViewModel.fetchWeekWindow` — the
// week strip only ever consumes `fetchCompletedDailyIds`, never a
// failed/loss signal, so "did you complete something" is the only axis this
// type models).
//
// Scope note (proposal §7 / issue #774): no shared Sudoku/Minesweeper
// streak-widget abstraction — this type is intentionally duplicated (not
// exported) in `MinesweeperUI.MinesweeperDailyStrip`, copy-paste-adapt.
//
// Window anchor (owner adjudication 2026-07-15, item 3): ROLLING 7 days,
// today rightmost — no calendar-week anchoring. Every `DailyStripDay` in a
// `DailyStripSnapshot.days` array is therefore either today or a past day;
// the proposal's "future day" dot state is unreachable under this anchor
// (kept as a defensive View-layer case, never actually produced here).

public import Foundation

/// One day's dot state within the rolling 7-day strip. `offsetFromToday == 0`
/// is always today (the rightmost dot); `6` is the oldest (leftmost) day.
public struct DailyStripDay: Sendable, Equatable, Identifiable {
    public let offsetFromToday: Int
    /// The calendar date this dot represents, in the device's local
    /// calendar — used only for the VoiceOver weekday label (§3.4 of the
    /// proposal). The completion boundary itself stays UTC-bucketed (via
    /// `PersistenceProtocol.fetchCompletedDailyIds`'s existing `UTCDay`
    /// contract) — this `date` never re-derives that boundary, it only
    /// carries the `Date` used to fetch this slot for display purposes.
    public let date: Date
    public let isCompleted: Bool

    public var isToday: Bool { offsetFromToday == 0 }
    public var id: Int { offsetFromToday }

    public init(offsetFromToday: Int, date: Date, isCompleted: Bool) {
        self.offsetFromToday = offsetFromToday
        self.date = date
        self.isCompleted = isCompleted
    }
}

/// The week strip's full render state. `days.isEmpty` means "unknown" —
/// covers both the brief pre-fetch skeleton and a graceful CK-fetch
/// degrade (offline / signed-out); the view renders the same subdued
/// placeholder for both, matching the hub's existing degrade philosophy
/// (never show a false "streak broken" reading, just show "not yet known").
///
/// `streak` is `nil` whenever there is nothing worth captioning: unknown
/// state, OR a genuine 0-day streak. Showing "0-day streak" would read as a
/// broken-streak signal in exactly the same way an offline "0" would — the
/// proposal's degrade contract ("no streak number rather than '0'") is
/// applied uniformly to both causes rather than distinguishing them.
public struct DailyStripSnapshot: Sendable, Equatable {
    public let days: [DailyStripDay]
    public let streak: Int?

    public init(days: [DailyStripDay], streak: Int?) {
        self.days = days
        self.streak = streak
    }

    public static let unknown = DailyStripSnapshot(days: [], streak: nil)
}

/// Pure streak-computation + presentation helpers. No CloudKit, no
/// `@MainActor` — testable in isolation (see `DailyStripLogicTests`).
public enum DailyStripLogic {

    /// `days` MUST be ordered oldest → newest (today last) — the same order
    /// `DailyHubViewModel.fetchWeekWindow` produces and the strip renders
    /// left-to-right.
    ///
    /// Walks backward from today if today is completed, else from
    /// yesterday — today's own incompleteness must never zero out an
    /// otherwise-alive streak that ended yesterday (dispatch spec, matrix
    /// case "chain-ending-yesterday-today-incomplete"). Stops at the first
    /// gap. The result is therefore capped at `days.count` — a maxed-out
    /// 7-day window renders as "7+" (`DailyStripView`'s caption keys): the
    /// window is also the fetch budget, so nothing beyond it was ever
    /// fetched and a longer exact count can't be proven.
    public static func computeStreak(days: [DailyStripDay]) -> Int {
        guard let lastIndex = days.indices.last else { return 0 }
        var index = lastIndex
        if !days[index].isCompleted {
            index -= 1
        }
        var streak = 0
        while index >= days.startIndex, days[index].isCompleted {
            streak += 1
            index -= 1
        }
        return streak
    }
}
