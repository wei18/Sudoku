// MinesweeperDailyStrip — rolling 7-day completion strip + streak, pure
// model/logic. Mirrors `SudokuUI.DailyStrip` (copy-paste-adapt per the
// proposal's scope note — see the header comment there for the full
// rationale; not repeated here).
//
// #774 (adopted `docs/v2/daily-calendar-streak-proposal.md`, owner
// adjudication 2026-07-15):
//   - Rule 1: a day counts as "completed" if ANY difficulty was completed
//     that day.
//   - Rule 2 (MS-specific): a mine-hit loss does NOT count as completion but
//     also does NOT itself break the streak — this model only ever consumes
//     `MinesweeperSavedGameStore.fetchCompletedDailyIds`, never the
//     failed-ids fetch (that stays scoped to the trio card's "Failed" badge,
//     unrelated to the strip/streak). A day with a loss and no completion is
//     therefore indistinguishable here from a day nothing was played at all
//     — both are simply "not completed," which is exactly rule 2's intent:
//     losing isn't a distinct streak-breaking penalty on top of not
//     completing.

public import Foundation
public import MinesweeperEngine

/// #826: a completed daily puzzleId paired with its parsed difficulty —
/// mirrors `SudokuUI.DailyReviewChoice`. The confirmationDialog picker's row
/// when a tapped past day has more than one completed difficulty.
public struct MinesweeperDailyReviewChoice: Sendable, Equatable, Identifiable {
    public let puzzleId: String
    public let difficulty: Difficulty
    public var id: String { puzzleId }
}

public struct MinesweeperDailyStripDay: Sendable, Equatable, Identifiable {
    public let offsetFromToday: Int
    /// Local-calendar date for the VoiceOver weekday label only — the
    /// completion boundary itself stays UTC-bucketed via
    /// `MinesweeperSavedGameStore.fetchCompletedDailyIds`'s existing
    /// `UTCDay` contract.
    public let date: Date
    public let isCompleted: Bool
    /// #826: the daily puzzleIds completed on this day (empty when not
    /// completed, or when this day was hand-built without the underlying
    /// fetch). Lets a past-day dot tap derive which difficulty/difficulties
    /// to open without a second fetch — see
    /// `MinesweeperDailyHubViewModel.dayTapped`.
    public let completedPuzzleIds: Set<String>
    /// #826 (CR round 2): `true` iff at least one `completedPuzzleIds` entry
    /// parses into a known `Difficulty`. Derived IN INIT (never an
    /// independent init parameter), so a "tappable but inert" dot is
    /// unrepresentable — mirrors `SudokuUI.DailyStripDay.isReviewable`; see
    /// that doc for the malformed-ids rationale.
    public let isReviewable: Bool

    public var isToday: Bool { offsetFromToday == 0 }
    public var id: Int { offsetFromToday }

    public init(offsetFromToday: Int, date: Date, isCompleted: Bool, completedPuzzleIds: Set<String> = []) {
        self.offsetFromToday = offsetFromToday
        self.date = date
        self.isCompleted = isCompleted
        self.completedPuzzleIds = completedPuzzleIds
        self.isReviewable = !MinesweeperDailyStripLogic.reviewChoices(from: completedPuzzleIds).isEmpty
    }
}

/// `days.isEmpty` == unknown (pre-fetch skeleton or graceful CK degrade).
/// `streak == nil` whenever there's nothing worth captioning — unknown
/// state OR a genuine 0-day streak (never show "0", matches the offline
/// degrade contract for both causes uniformly).
public struct MinesweeperDailyStripSnapshot: Sendable, Equatable {
    public let days: [MinesweeperDailyStripDay]
    public let streak: Int?

    public init(days: [MinesweeperDailyStripDay], streak: Int?) {
        self.days = days
        self.streak = streak
    }

    public static let unknown = MinesweeperDailyStripSnapshot(days: [], streak: nil)
}

/// Pure streak-computation + presentation helpers — identical algorithm to
/// `SudokuUI.DailyStripLogic`, duplicated per the proposal's no-shared-
/// widget scope note. Deliberately separate from `MinesweeperDailyStreakMath`
/// (#700): that one computes calendar-anchored consecutive streaks over full
/// completion history for Game Center achievements; this one only reads the
/// 7-day fetch window behind the strip UI. Don't unify — different inputs,
/// different consumers.
public enum MinesweeperDailyStripLogic {

    /// `days` MUST be ordered oldest → newest (today last).
    public static func computeStreak(days: [MinesweeperDailyStripDay]) -> Int {
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
    /// (`MinesweeperDaily.puzzleId(day:difficulty:)`'s format, e.g.
    /// "daily-2026-07-16-beginner") and sorts beginner → intermediate →
    /// expert for a stable picker order. No reverse-parser exists in
    /// `MinesweeperEngine` (only a day-extractor,
    /// `MinesweeperSavedGameStore.dailyDay(fromRecordName:)`). An id whose
    /// suffix isn't a known `Difficulty` is silently dropped — the SINGLE
    /// parse both `MinesweeperDailyStripDay.isReviewable` (the view's
    /// tappable gate) and `MinesweeperDailyHubViewModel.dayTapped` (the open
    /// path) are built on, so the two can never disagree (CR round 2).
    public static func reviewChoices(from puzzleIds: Set<String>) -> [MinesweeperDailyReviewChoice] {
        puzzleIds
            .compactMap { puzzleId -> MinesweeperDailyReviewChoice? in
                guard let token = puzzleId.split(separator: "-").last,
                      let difficulty = Difficulty(rawValue: String(token)) else { return nil }
                return MinesweeperDailyReviewChoice(puzzleId: puzzleId, difficulty: difficulty)
            }
            .sorted { lhs, rhs in
                let order = Difficulty.allCases
                return (order.firstIndex(of: lhs.difficulty) ?? 0) < (order.firstIndex(of: rhs.difficulty) ?? 0)
            }
    }
}
