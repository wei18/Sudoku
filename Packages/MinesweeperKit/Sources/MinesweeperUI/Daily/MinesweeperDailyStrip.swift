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

public struct MinesweeperDailyStripDay: Sendable, Equatable, Identifiable {
    public let offsetFromToday: Int
    /// Local-calendar date for the VoiceOver weekday label only — the
    /// completion boundary itself stays UTC-bucketed via
    /// `MinesweeperSavedGameStore.fetchCompletedDailyIds`'s existing
    /// `UTCDay` contract.
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
}
