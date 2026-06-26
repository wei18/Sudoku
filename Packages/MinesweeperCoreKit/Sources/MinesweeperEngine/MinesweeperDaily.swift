// MinesweeperDaily — date-seeded daily board model (#290).
//
// Mirrors Sudoku's daily mechanism (`PuzzleStore.dailySeed` +
// `fetchDailyTrio`): a UTC calendar day deterministically maps to a seed,
// and the seed + difficulty deterministically build a `MinesweeperEngine`
// board. Same date → same board for everyone; rolls over at UTC midnight.
//
// Difficulty policy: a TRIO — one board per difficulty (beginner /
// intermediate / expert) per day, mirroring Sudoku's three daily cards.
//
// Seed recipe mirrors Sudoku's `dailySeed`: an FNV-1a `StableHash` over
// (generatorVersion, "daily", utcDayString, difficulty.rawValue). NOT
// `Swift.Hasher` (process-randomized) — `StableHash` is bit-identical across
// runs and architectures, which is what makes the daily board replayable.

public import Foundation
internal import TimeKit

public enum MinesweeperDaily {

    /// Bumped if the seed→board derivation changes in a way that should roll
    /// every day's board (mirrors Sudoku's `generatorVersion` framing element).
    public static let generatorVersion: UInt64 = 1

    /// All daily difficulties, in display order. The daily "trio".
    public static let dailyDifficulties: [Difficulty] = [.beginner, .intermediate, .expert]

    /// Deterministic seed for `(date, difficulty)`, keyed by the UTC day.
    public static func seed(date: Date, difficulty: Difficulty) -> UInt64 {
        seed(day: UTCDay.string(from: date), difficulty: difficulty)
    }

    /// Deterministic seed for `(utcDayString, difficulty)`.
    public static func seed(day: String, difficulty: Difficulty) -> UInt64 {
        var hash = StableHash()
        hash.combine(generatorVersion)
        hash.combine("daily")
        hash.combine(day)
        hash.combine(difficulty.rawValue)
        return hash.value
    }

    /// The daily board for `(date, difficulty)`. Fully determined by the
    /// UTC-day-derived seed (mine layout resolves on first reveal, as with any
    /// MS board).
    public static func board(date: Date, difficulty: Difficulty) -> MinesweeperEngine {
        MinesweeperEngine(difficulty: difficulty, seed: seed(date: date, difficulty: difficulty))
    }

    /// Stable per-day, per-difficulty identifier used for completion matching
    /// (`PersistenceProtocol.fetchCompletedDailyIds`) and as the card id.
    /// Format: `daily-<YYYY-MM-DD>-<difficulty>`.
    public static func puzzleId(date: Date, difficulty: Difficulty) -> String {
        puzzleId(day: UTCDay.string(from: date), difficulty: difficulty)
    }

    /// `daily-<utcDayString>-<difficulty>`.
    public static func puzzleId(day: String, difficulty: Difficulty) -> String {
        "daily-\(day)-\(difficulty.rawValue)"
    }
}
