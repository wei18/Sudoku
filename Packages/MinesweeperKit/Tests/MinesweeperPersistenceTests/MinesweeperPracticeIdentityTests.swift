// MinesweeperPracticeIdentityTests — #705.
//
// Two things pinned here:
//   1. `MinesweeperCrockfordBase32.encode` is byte-identical to Sudoku's
//      `SudokuPersistence.PuzzleIdentity.CrockfordBase32.encode` for shared
//      vectors — the two are hand-duplicated (SudokuPersistence isn't a
//      dependency of MinesweeperPersistence), so drift would silently produce
//      differently-shaped ids across the two apps. Vectors + expected outputs
//      were computed once from the shared algorithm (0 → "0", then a spread
//      of small/boundary/large UInt64 values) and are reproduced verbatim in
//      both suites.
//   2. `MinesweeperPracticeIdentity.puzzleId` derives the same id from a
//      snapshot's `seed` before and after a JSON encode/decode round-trip —
//      the id-survives-resume contract without needing a dedicated
//      persisted field (see MinesweeperPracticeIdentity.swift's doc comment).

import Foundation
import Testing
import MinesweeperEngine
import MinesweeperGameState
@testable import MinesweeperPersistence

@Suite("MinesweeperCrockfordBase32 — vector parity with SudokuPersistence")
struct MinesweeperCrockfordBase32Tests {

    /// Shared vectors, byte-equal to Sudoku's `CrockfordBase32.encode` for
    /// the same inputs (Crockford's own alphabet is a public spec, so any
    /// correct implementation agrees — this pins OUR duplicate against it).
    @Test(
        "encode(value) matches SudokuPersistence's CrockfordBase32 output",
        arguments: [
            (UInt64(0), "0"),
            (UInt64(1), "1"),
            (UInt64(31), "Z"),
            (UInt64(32), "10"),
            (UInt64(12345), "C1S"),
            (UInt64(42), "1A"),
            (UInt64.max, "FZZZZZZZZZZZZ"),
        ]
    )
    func encodeMatchesSharedVectors(value: UInt64, expected: String) {
        #expect(MinesweeperCrockfordBase32.encode(value) == expected)
    }
}

@Suite("MinesweeperPracticeIdentity — #705")
struct MinesweeperPracticeIdentityTests {

    @Test func puzzleIdFormatIsPracticeCrockfordDifficulty() {
        let id = MinesweeperPracticeIdentity.puzzleId(seed: 42, difficulty: .beginner)
        #expect(id == "practice-1A-beginner")
    }

    @Test func differentSeedsProduceDifferentIds() {
        let idOne = MinesweeperPracticeIdentity.puzzleId(seed: 1, difficulty: .beginner)
        let idTwo = MinesweeperPracticeIdentity.puzzleId(seed: 2, difficulty: .beginner)
        #expect(idOne != idTwo)
    }

    @Test func sameSeedDifferentDifficultyProducesDifferentIds() {
        let beginnerId = MinesweeperPracticeIdentity.puzzleId(seed: 42, difficulty: .beginner)
        let expertId = MinesweeperPracticeIdentity.puzzleId(seed: 42, difficulty: .expert)
        #expect(beginnerId != expertId)
    }

    /// The id-survives-resume contract: derive the id from a snapshot's
    /// `seed` before encoding, then again after a JSON round-trip — must
    /// match, because `seed` is a required (non-optional) field that already
    /// round-trips exactly (mirrors the coverage in
    /// MinesweeperSessionRestoreTests.jsonRoundTripPreservesSnapshot).
    @Test func puzzleIdSurvivesSnapshotJSONRoundTrip() throws {
        let snapshot = MinesweeperSessionSnapshot(
            difficulty: .intermediate,
            seed: 0xDEAD_BEEF,
            cells: Array(repeating: Cell(), count: Difficulty.intermediate.cellCount),
            status: .playing,
            elapsedSeconds: 12,
            mineCount: Difficulty.intermediate.mineCount,
            flagCount: 0
        )
        let before = MinesweeperPracticeIdentity.puzzleId(seed: snapshot.seed, difficulty: snapshot.difficulty)

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(MinesweeperSessionSnapshot.self, from: data)
        let after = MinesweeperPracticeIdentity.puzzleId(seed: decoded.seed, difficulty: decoded.difficulty)

        #expect(before == after)
    }
}
