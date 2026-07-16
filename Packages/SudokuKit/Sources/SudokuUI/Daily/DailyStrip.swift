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
public import SudokuEngine

/// #826: a completed daily puzzleId paired with its parsed difficulty —
/// the confirmationDialog picker's row when a tapped past day has more than
/// one completed difficulty. `Identifiable` on `puzzleId` (unique per day)
/// so `DailyHubView` can drive the dialog straight off `ForEach`.
public struct DailyReviewChoice: Sendable, Equatable, Identifiable {
    public let puzzleId: String
    public let difficulty: Difficulty
    public var id: String { puzzleId }
}

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
    /// #826: the daily puzzleIds completed on this day (empty when not
    /// completed, or when this `DailyStripDay` was hand-built without the
    /// underlying fetch — e.g. `DailyStripLogicTests`'s pure streak matrix).
    /// Lets a past-day dot tap derive which difficulty/difficulties to open
    /// without a second fetch — see `DailyHubViewModel.dayTapped`.
    public let completedPuzzleIds: Set<String>
    /// #826 (CR round 2): `true` iff at least one `completedPuzzleIds` entry
    /// parses into a known `Difficulty` — i.e. a tap can actually open a
    /// review. Derived IN INIT (never an independent init parameter), so a
    /// "tappable but inert" dot is unrepresentable: a day whose ids are ALL
    /// malformed (legacy schema / format drift) is simply not reviewable and
    /// never renders as a button. `isCompleted` alone still drives the dot's
    /// fill + streak math — a malformed-id day stays visually completed.
    public let isReviewable: Bool

    public var isToday: Bool { offsetFromToday == 0 }
    public var id: Int { offsetFromToday }

    public init(offsetFromToday: Int, date: Date, isCompleted: Bool, completedPuzzleIds: Set<String> = []) {
        self.offsetFromToday = offsetFromToday
        self.date = date
        self.isCompleted = isCompleted
        self.completedPuzzleIds = completedPuzzleIds
        self.isReviewable = !DailyStripLogic.reviewChoices(from: completedPuzzleIds).isEmpty
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

    /// #826: parses each puzzleId's trailing `-{difficulty}` segment
    /// (`PuzzleIdentity.daily`'s format, e.g. "2026-07-16-hard") and sorts
    /// easy → medium → hard for a stable picker order. `PuzzleStore.parse`
    /// does the same job with fuller shape validation but is `internal` to
    /// `SudokuPersistence`; this trivial suffix read avoids widening that
    /// visibility. An id whose suffix isn't a known `Difficulty` is silently
    /// dropped — the SINGLE parse both `DailyStripDay.isReviewable` (the
    /// views' tappable gate) and `DailyHubViewModel.dayTapped` (the open
    /// path) are built on, so the two can never disagree (CR round 2).
    public static func reviewChoices(from puzzleIds: Set<String>) -> [DailyReviewChoice] {
        puzzleIds
            .compactMap { puzzleId -> DailyReviewChoice? in
                guard let token = puzzleId.split(separator: "-").last,
                      let difficulty = Difficulty(rawValue: String(token)) else { return nil }
                return DailyReviewChoice(puzzleId: puzzleId, difficulty: difficulty)
            }
            .sorted { lhs, rhs in
                let order = Difficulty.allCases
                return (order.firstIndex(of: lhs.difficulty) ?? 0) < (order.firstIndex(of: rhs.difficulty) ?? 0)
            }
    }
}
