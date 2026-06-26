// StableHash — deterministic FNV-1a 64-bit hash, length-framed, little-endian.
//
// Hoisted into DeterminismKit (#627) from three byte-identical per-core copies
// (Game2048Engine / MinesweeperEngine / SudokuPersistence) — the copy-paste the
// mirror principle forbids. It derives DAILY SEEDS, so the byte layout is
// determinism-critical and frozen: the FNV offset basis / prime, the 8-byte
// little-endian length framing, and the absorb order MUST NOT change. Pinned by
// `StableHashTests` against independently-computed reference vectors.
//
// Sibling of `SplitMix64` (the daily seed feeds the RNG) — single source of truth.

public struct StableHash {
    private static let fnvOffsetBasis: UInt64 = 0xCBF2_9CE4_8422_2325
    private static let fnvPrime: UInt64 = 0x0000_0100_0000_01B3

    public private(set) var value: UInt64 = StableHash.fnvOffsetBasis

    public init() {}

    /// Absorb a length-framed byte run: 8 little-endian length bytes, then the
    /// bytes. Length framing makes `combine("ab") + combine("c")` distinct from
    /// `combine("a") + combine("bc")`.
    public mutating func combine(_ bytes: [UInt8]) {
        let length = UInt64(bytes.count)
        absorb(length.littleEndianBytes)
        absorb(bytes)
    }

    public mutating func combine(_ string: String) {
        combine(Array(string.utf8))
    }

    public mutating func combine(_ word: UInt64) {
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
