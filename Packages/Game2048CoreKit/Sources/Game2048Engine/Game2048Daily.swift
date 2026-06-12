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

// MARK: - StableHash (FNV-1a 64-bit, length-framed)
//
// Byte-identical to MinesweeperDaily.StableHash. Kept internal here so the
// two cores don't create a cross-package coupling just for the hash helper —
// the single source of truth for the algorithm is the design.md comment in MS.

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
        let low = self.littleEndian
        return [
            UInt8(truncatingIfNeeded: low),
            UInt8(truncatingIfNeeded: low >> 8),
            UInt8(truncatingIfNeeded: low >> 16),
            UInt8(truncatingIfNeeded: low >> 24),
            UInt8(truncatingIfNeeded: low >> 32),
            UInt8(truncatingIfNeeded: low >> 40),
            UInt8(truncatingIfNeeded: low >> 48),
            UInt8(truncatingIfNeeded: low >> 56),
        ]
    }
}
