import Testing
@testable import DeterminismKit

/// Frozen reference vectors for `StableHash` (#627). Computed by an INDEPENDENT
/// FNV-1a reimplementation (length-framed, little-endian) — not by the Swift type
/// under test — so these pin the byte layout to the spec, not to itself. If the
/// hoist (or any future edit) shifts the offset basis / prime / length framing /
/// absorb order, these break. They MUST NOT be re-recorded to make a change pass —
/// a move that shifts them changes every game's daily seeds.
@Suite("StableHash — frozen FNV-1a vectors (#627)")
struct StableHashTests {

    @Test func emptyIsOffsetBasis() {
        #expect(StableHash().value == 0xCBF2_9CE4_8422_2325)
    }

    @Test func combineString() {
        var hash = StableHash()
        hash.combine("daily")
        #expect(hash.value == 0x65A3_925E_EDF7_AFA1)
    }

    @Test func combineWord() {
        var hash = StableHash()
        hash.combine(UInt64(1))
        #expect(hash.value == 0xE116_06F0_EEB8_DC4C)
    }

    /// A representative daily-seed recipe ordering (word + two strings).
    @Test func recipeOrderIsStable() {
        var hash = StableHash()
        hash.combine(UInt64(1))
        hash.combine("daily")
        hash.combine("2026-06-12")
        #expect(hash.value == 0xAAAF_9E40_9705_AE09)
    }

    /// Length framing makes equal-concatenation inputs distinct.
    @Test func lengthFramingDisambiguates() {
        var abThenC = StableHash(); abThenC.combine("ab"); abThenC.combine("c")
        var aThenBc = StableHash(); aThenBc.combine("a"); aThenBc.combine("bc")
        #expect(abThenC.value != aThenBc.value)
    }
}
