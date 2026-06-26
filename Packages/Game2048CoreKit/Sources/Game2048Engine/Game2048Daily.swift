// Game2048Daily — date-seeded daily board model for 2048 (SDD-004 M1).
//
// Mirrors MinesweeperDaily exactly: a UTC calendar day deterministically
// maps to a seed, which drives the SplitMix64 spawn sequence.
// Same date → same spawn sequence for everyone; rolls over at UTC midnight.
//
// Seed recipe: FNV-1a StableHash over (generatorVersion, "daily", utcDayString).
// NOT Swift.Hasher (process-randomized) — StableHash is bit-identical across
// runs and architectures, matching Minesweeper's scheme exactly.
// Source file mirrored from:
//   Packages/MinesweeperCoreKit/Sources/MinesweeperEngine/MinesweeperDaily.swift

public import Foundation
internal import TimeKit

/// Recipe note: identical StableHash (FNV-1a, length-framed) and framing as
/// MinesweeperDaily, but the inputs are (generatorVersion, "daily", utcDay) —
/// THREE inputs, not four: 2048 has no difficulty dimension (CR #490 F5).
public enum Game2048Daily {

    /// Bumped if the seed→spawn derivation changes in a way that should roll
    /// every day's sequence (mirrors MinesweeperDaily.generatorVersion).
    public static let generatorVersion: UInt64 = 1

    /// Deterministic seed for a UTC day string (e.g. "2026-06-12").
    public static func seed(forUTCDay day: String) -> UInt64 {
        var hash = StableHash()
        hash.combine(generatorVersion)
        hash.combine("daily")
        hash.combine(day)
        return hash.value
    }

    /// Deterministic seed for a given Date (keyed by the UTC day).
    public static func seed(forDate date: Date) -> UInt64 {
        seed(forUTCDay: UTCDay.string(from: date))
    }

    /// Stable per-day identifier for completion matching and card ids.
    /// Format: `daily-2048-<YYYY-MM-DD>`.
    public static func puzzleId(forDate date: Date) -> String {
        puzzleId(forUTCDay: UTCDay.string(from: date))
    }

    /// `daily-2048-<utcDayString>`.
    public static func puzzleId(forUTCDay day: String) -> String {
        "daily-2048-\(day)"
    }
}
