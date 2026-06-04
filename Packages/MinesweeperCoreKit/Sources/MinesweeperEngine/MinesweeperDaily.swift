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

// MARK: - StableHash

/// Deterministic FNV-1a 64-bit hash with explicit per-element length framing
/// so `combine("a"), combine("b")` and `combine("ab")` produce different
/// outputs. Mirrors `SudokuKit/PuzzleStore`'s `StableHash` — NOT
/// `Swift.Hasher` (whose output is randomized per process). Bit-identical
/// across architectures.
internal struct StableHash {
    private static let fnvOffsetBasis: UInt64 = 0xCBF2_9CE4_8422_2325
    private static let fnvPrime: UInt64 = 0x0000_0100_0000_01B3

    private(set) var value: UInt64 = StableHash.fnvOffsetBasis

    mutating func combine(_ bytes: [UInt8]) {
        let length = UInt64(bytes.count)
        absorb(length.littleEndianBytes)
        absorb(bytes)
    }

    mutating func combine(_ string: String) {
        combine(Array(string.utf8))
    }

    mutating func combine(_ word: UInt64) {
        combine(word.littleEndianBytes)
    }

    private mutating func absorb(_ bytes: [UInt8]) {
        for byte in bytes {
            value ^= UInt64(byte)
            value &*= StableHash.fnvPrime
        }
    }
}

private extension UInt64 {
    var littleEndianBytes: [UInt8] {
        let lowEndian = self.littleEndian
        return [
            UInt8(truncatingIfNeeded: lowEndian),
            UInt8(truncatingIfNeeded: lowEndian >> 8),
            UInt8(truncatingIfNeeded: lowEndian >> 16),
            UInt8(truncatingIfNeeded: lowEndian >> 24),
            UInt8(truncatingIfNeeded: lowEndian >> 32),
            UInt8(truncatingIfNeeded: lowEndian >> 40),
            UInt8(truncatingIfNeeded: lowEndian >> 48),
            UInt8(truncatingIfNeeded: lowEndian >> 56)
        ]
    }
}
