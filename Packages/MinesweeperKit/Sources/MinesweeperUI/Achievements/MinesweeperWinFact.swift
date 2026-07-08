// MinesweeperWinFact — pure input to `MinesweeperAchievementEvaluator` (#700).
//
// Deliberately decoupled from any IO: the ViewModel call site
// (`MinesweeperGameViewModel+EvaluateAchievements.swift`) gathers these facts
// (personal-best store reads, the local win-count tally) and hands them to
// the evaluator as a value, so the evaluator itself stays a synchronous, pure
// function — trivially unit-testable without a fake CloudKit gateway.

public import MinesweeperEngine

public struct MinesweeperWinFact: Sendable, Equatable {
    public let mode: GameMode
    public let difficulty: Difficulty
    public let elapsedSeconds: Int
    /// Count of flag PLACEMENTS at any point during this game (not the flag
    /// count at the moment of the win — a placed-then-removed flag still
    /// counts, and still disqualifies "No Flags Needed"). Only zero vs
    /// non-zero matters to the evaluator.
    public let flagsPlaced: Int
    /// Completed-game count across BOTH modes, INCLUDING this win.
    public let cumulativeWinCount: Int
    /// Difficulties with at least one daily win, INCLUDING this win if
    /// `mode == .daily`. Always empty for a practice win (daily-only fact).
    public let dailyWinDifficulties: Set<Difficulty>
    /// Consecutive UTC days (ending today) with at least one daily win,
    /// INCLUDING today if this win is a daily win. Always 0 for a practice win.
    public let consecutiveDailyStreak: Int

    public init(
        mode: GameMode,
        difficulty: Difficulty,
        elapsedSeconds: Int,
        flagsPlaced: Int,
        cumulativeWinCount: Int,
        dailyWinDifficulties: Set<Difficulty> = [],
        consecutiveDailyStreak: Int = 0
    ) {
        self.mode = mode
        self.difficulty = difficulty
        self.elapsedSeconds = elapsedSeconds
        self.flagsPlaced = flagsPlaced
        self.cumulativeWinCount = cumulativeWinCount
        self.dailyWinDifficulties = dailyWinDifficulties
        self.consecutiveDailyStreak = consecutiveDailyStreak
    }
}
