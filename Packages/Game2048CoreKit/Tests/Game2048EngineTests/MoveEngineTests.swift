// swiftlint:disable identifier_name file_length
// `r`, `c`, `i` are idiomatic for tight grid traversal. Comprehensive rule
// coverage drives file > 400 lines — test fixture, both rules disabled.

import Testing
import Foundation
@testable import Game2048Engine

// MARK: - Helpers

/// Build a Board from a 4×4 nested array (nil = empty, Int = tile value).
private func board(_ rows: [[Int?]]) -> Board {
    precondition(rows.count == 4 && rows.allSatisfy { $0.count == 4 })
    var tiles: [Int?] = []
    for row in rows { tiles.append(contentsOf: row) }
    return Board(tiles: tiles)
}

/// Extract rows as [[Int?]] for readable assertions.
private func rows(_ brd: Board) -> [[Int?]] {
    (0..<Board.size).map { row in
        (0..<Board.size).map { col in brd[row, col] }
    }
}

// MARK: - BoardTests

@Suite struct BoardTests {
    @Test func emptyBoardHas16Nils() {
        let brd = Board()
        #expect(brd.tiles.count == Board.cellCount)
        #expect(brd.tiles.allSatisfy { $0 == nil })
    }

    @Test func emptyIndicesAreAll16() {
        let brd = Board()
        #expect(brd.emptyIndices.count == 16)
        #expect(brd.emptyIndices == Array(0..<16))
    }

    @Test func subscriptReadWrite() {
        var brd = Board()
        brd[0, 0] = 2
        brd[3, 3] = 1024
        #expect(brd[0, 0] == 2)
        #expect(brd[3, 3] == 1024)
        #expect(brd[0, 1] == nil)
    }

    @Test func inBoundsCheck() {
        let brd = Board()
        #expect(brd.inBounds(row: 0, col: 0))
        #expect(brd.inBounds(row: 3, col: 3))
        #expect(!brd.inBounds(row: 4, col: 0))
        #expect(!brd.inBounds(row: 0, col: 4))
        #expect(!brd.inBounds(row: -1, col: 0))
    }

    @Test func containsTargetFalseWhenBelow2048() {
        let brd = board([[1024, nil, nil, nil], [nil, nil, nil, nil], [nil, nil, nil, nil], [nil, nil, nil, nil]])
        #expect(brd.containsTarget == false)
    }

    @Test func containsTargetTrueAt2048() {
        let brd = board([[2048, nil, nil, nil], [nil, nil, nil, nil], [nil, nil, nil, nil], [nil, nil, nil, nil]])
        #expect(brd.containsTarget == true)
    }

    @Test func containsTargetTrueAbove2048() {
        let brd = board([[4096, nil, nil, nil], [nil, nil, nil, nil], [nil, nil, nil, nil], [nil, nil, nil, nil]])
        #expect(brd.containsTarget == true)
    }

    @Test func codableRoundTrip() throws {
        var brd = Board()
        brd[0, 0] = 2; brd[1, 1] = 4; brd[2, 2] = 8; brd[3, 3] = 16
        let data = try JSONEncoder().encode(brd)
        let decoded = try JSONDecoder().decode(Board.self, from: data)
        #expect(decoded == brd)
    }

    @Test func indexIsRowMajor() {
        let brd = Board()
        #expect(brd.index(row: 0, col: 0) == 0)
        #expect(brd.index(row: 0, col: 3) == 3)
        #expect(brd.index(row: 1, col: 0) == 4)
        #expect(brd.index(row: 3, col: 3) == 15)
    }
}

// MARK: - SlideLineTests

@Suite struct SlideLineTests {

    // MARK: Left direction (slide toward index 0)

    @Test func allNilLineIsUnchanged() {
        let (result, delta) = MoveEngine.slideLine([nil, nil, nil, nil])
        #expect(result == [nil, nil, nil, nil])
        #expect(delta == 0)
    }

    @Test func singleTileSlides() {
        let (result, delta) = MoveEngine.slideLine([nil, 2, nil, nil])
        #expect(result == [2, nil, nil, nil])
        #expect(delta == 0)
    }

    @Test func equalPairMerges() {
        let (result, delta) = MoveEngine.slideLine([2, 2, nil, nil])
        #expect(result == [4, nil, nil, nil])
        #expect(delta == 4)
    }

    @Test func doubleMergeProhibition_2_2_4_8() {
        // [2,2,4,8] left → [4,4,8,nil] NOT [8,8,nil,nil]
        let (result, delta) = MoveEngine.slideLine([2, 2, 4, 8])
        #expect(result == [4, 4, 8, nil])
        #expect(delta == 4)
    }

    @Test func doubleMergeProhibition_4_4_4_4() {
        // [4,4,4,4] left → [8,8,nil,nil]
        let (result, delta) = MoveEngine.slideLine([4, 4, 4, 4])
        #expect(result == [8, 8, nil, nil])
        #expect(delta == 16)
    }

    @Test func leadingNonPairThenPair() {
        // [4,2,2,nil] left → [4,4,nil,nil] (CR #490 F2 — pair behind a
        // non-matching leader still merges; no chain into the leader)
        let (result, delta) = MoveEngine.slideLine([4, 2, 2, nil])
        #expect(result == [4, 4, nil, nil])
        #expect(delta == 4)
    }

    @Test func threeOfSame() {
        // [2,2,2,nil] left → [4,2,nil,nil] (first pair merges; third slides)
        let (result, delta) = MoveEngine.slideLine([2, 2, 2, nil])
        #expect(result == [4, 2, nil, nil])
        #expect(delta == 4)
    }

    @Test func nonEqualPairDoesNotMerge() {
        let (result, delta) = MoveEngine.slideLine([2, 4, nil, nil])
        #expect(result == [2, 4, nil, nil])
        #expect(delta == 0)
    }

    @Test func gapsCompact() {
        let (result, delta) = MoveEngine.slideLine([nil, 2, nil, 4])
        #expect(result == [2, 4, nil, nil])
        #expect(delta == 0)
    }

    @Test func mergeAndCompact() {
        // [nil,2,nil,2] → compact to [2,2] → merge to [4,nil,nil,nil]
        let (result, delta) = MoveEngine.slideLine([nil, 2, nil, 2])
        #expect(result == [4, nil, nil, nil])
        #expect(delta == 4)
    }

    @Test func allSame_1024() {
        // [1024,1024,1024,1024] → [2048,2048,nil,nil]
        let (result, delta) = MoveEngine.slideLine([1024, 1024, 1024, 1024])
        #expect(result == [2048, 2048, nil, nil])
        #expect(delta == 4096)
    }

    @Test func fullyPackedDistinct() {
        // [2,4,8,16] → no merge, no move
        let (result, delta) = MoveEngine.slideLine([2, 4, 8, 16])
        #expect(result == [2, 4, 8, 16])
        #expect(delta == 0)
    }
}

// MARK: - MoveEngineDirectionTests

@Suite struct MoveEngineDirectionTests {

    // MARK: Left

    @Test func slideLeftBasic() {
        let brd = board([
            [nil, 2, nil, 2],
            [nil, nil, nil, nil],
            [nil, nil, nil, nil],
            [nil, nil, nil, nil],
        ])
        let result = MoveEngine.apply(.left, to: brd)
        #expect(result != nil)
        #expect(result!.board[0, 0] == 4)
        #expect(result!.board[0, 1] == nil)
        #expect(result!.scoreDelta == 4)
    }

    @Test func slideLeftDoubleMergeProhibition() {
        let brd = board([
            [2, 2, 4, 8],
            [nil, nil, nil, nil],
            [nil, nil, nil, nil],
            [nil, nil, nil, nil],
        ])
        let result = MoveEngine.apply(.left, to: brd)
        #expect(result != nil)
        let row0 = rows(result!.board)[0]
        #expect(row0 == [4, 4, 8, nil])
        #expect(result!.scoreDelta == 4)
    }

    @Test func slideLeftFourSame() {
        let brd = board([
            [4, 4, 4, 4],
            [nil, nil, nil, nil],
            [nil, nil, nil, nil],
            [nil, nil, nil, nil],
        ])
        let result = MoveEngine.apply(.left, to: brd)
        #expect(result != nil)
        let row0 = rows(result!.board)[0]
        #expect(row0 == [8, 8, nil, nil])
        #expect(result!.scoreDelta == 16)
    }

    // MARK: Right

    @Test func slideRightBasic() {
        let brd = board([
            [2, 2, nil, nil],
            [nil, nil, nil, nil],
            [nil, nil, nil, nil],
            [nil, nil, nil, nil],
        ])
        let result = MoveEngine.apply(.right, to: brd)
        #expect(result != nil)
        let row0 = rows(result!.board)[0]
        #expect(row0 == [nil, nil, nil, 4])
        #expect(result!.scoreDelta == 4)
    }

    @Test func slideRightDoubleMergeProhibition() {
        // [8,4,2,2] right → [nil,8,4,4] NOT [nil,nil,8,8]
        let brd = board([
            [8, 4, 2, 2],
            [nil, nil, nil, nil],
            [nil, nil, nil, nil],
            [nil, nil, nil, nil],
        ])
        let result = MoveEngine.apply(.right, to: brd)
        #expect(result != nil)
        let row0 = rows(result!.board)[0]
        #expect(row0 == [nil, 8, 4, 4])
        #expect(result!.scoreDelta == 4)
    }

    @Test func slideRightFourSame() {
        let brd = board([
            [4, 4, 4, 4],
            [nil, nil, nil, nil],
            [nil, nil, nil, nil],
            [nil, nil, nil, nil],
        ])
        let result = MoveEngine.apply(.right, to: brd)
        #expect(result != nil)
        let row0 = rows(result!.board)[0]
        #expect(row0 == [nil, nil, 8, 8])
        #expect(result!.scoreDelta == 16)
    }

    // MARK: Up

    @Test func slideUpBasic() {
        let brd = board([
            [nil, nil, nil, nil],
            [2, nil, nil, nil],
            [nil, nil, nil, nil],
            [2, nil, nil, nil],
        ])
        let result = MoveEngine.apply(.up, to: brd)
        #expect(result != nil)
        #expect(result!.board[0, 0] == 4)
        #expect(result!.board[1, 0] == nil)
        #expect(result!.scoreDelta == 4)
    }

    @Test func slideUpDoubleMergeProhibition() {
        // col0: [2,2,4,8] up → [4,4,8,nil]
        let brd = board([
            [2, nil, nil, nil],
            [2, nil, nil, nil],
            [4, nil, nil, nil],
            [8, nil, nil, nil],
        ])
        let result = MoveEngine.apply(.up, to: brd)
        #expect(result != nil)
        let col0 = (0..<Board.size).map { result!.board[$0, 0] }
        #expect(col0 == [4, 4, 8, nil])
    }

    // MARK: Down

    @Test func slideDownBasic() {
        let brd = board([
            [2, nil, nil, nil],
            [2, nil, nil, nil],
            [nil, nil, nil, nil],
            [nil, nil, nil, nil],
        ])
        let result = MoveEngine.apply(.down, to: brd)
        #expect(result != nil)
        #expect(result!.board[3, 0] == 4)
        #expect(result!.board[2, 0] == nil)
    }

    @Test func slideDownDoubleMergeProhibition() {
        // col0: [8,4,2,2] down → reverse=[2,2,4,8] → slide=[4,4,8,nil] → reverse=[nil,8,4,4]
        let brd = board([
            [8, nil, nil, nil],
            [4, nil, nil, nil],
            [2, nil, nil, nil],
            [2, nil, nil, nil],
        ])
        let result = MoveEngine.apply(.down, to: brd)
        #expect(result != nil)
        let col0 = (0..<Board.size).map { result!.board[$0, 0] }
        #expect(col0 == [nil, 8, 4, 4])
    }

    // MARK: Illegal moves

    @Test func illegalMoveReturnsNil_noChange() {
        // Already compacted left, no merges possible.
        let brd = board([
            [2, 4, 8, 16],
            [nil, nil, nil, nil],
            [nil, nil, nil, nil],
            [nil, nil, nil, nil],
        ])
        let result = MoveEngine.apply(.left, to: brd)
        #expect(result == nil)
    }

    @Test func illegalMoveUpWhenAlreadyPackedTop() {
        let brd = board([
            [2, 4, 8, 16],
            [nil, nil, nil, nil],
            [nil, nil, nil, nil],
            [nil, nil, nil, nil],
        ])
        #expect(MoveEngine.apply(.up, to: brd) == nil)
    }

    @Test func scoreDeltaAccumulatesAcrossRows() {
        // Each row merges: row0=[2,2,nil,nil], row1=[4,4,nil,nil]
        let brd = board([
            [2, 2, nil, nil],
            [4, 4, nil, nil],
            [nil, nil, nil, nil],
            [nil, nil, nil, nil],
        ])
        let result = MoveEngine.apply(.left, to: brd)
        #expect(result != nil)
        #expect(result!.scoreDelta == 4 + 8)
    }
}

// MARK: - StuckDetectionTests

@Suite struct StuckDetectionTests {

    @Test func fullBoardWithNoMergesIsStuck() {
        // Checkerboard pattern — no adjacent equal tiles.
        let brd = board([
            [2, 4, 2, 4],
            [4, 2, 4, 2],
            [2, 4, 2, 4],
            [4, 2, 4, 2],
        ])
        #expect(MoveEngine.hasLegalMove(on: brd) == false)
    }

    @Test func emptyBoardHasLegalMoves() {
        let brd = Board()
        #expect(MoveEngine.hasLegalMove(on: brd) == true)
    }

    @Test func boardWithOneEmptyCellHasLegalMoves() {
        let brd = board([
            [2, 4, 2, 4],
            [4, 2, 4, 2],
            [2, 4, 2, 4],
            [4, 2, 4, nil],
        ])
        #expect(MoveEngine.hasLegalMove(on: brd) == true)
    }

    @Test func fullBoardWithAdjacentEqualHorizHasLegalMoves() {
        let brd = board([
            [2, 2, 4, 8],
            [4, 8, 16, 32],
            [64, 128, 256, 512],
            [1024, 2048, 4096, 8192],
        ])
        #expect(MoveEngine.hasLegalMove(on: brd) == true)
    }

    @Test func fullBoardWithAdjacentEqualVertHasLegalMoves() {
        let brd = board([
            [2, 4, 8, 16],
            [2, 8, 16, 32],
            [4, 16, 32, 64],
            [8, 32, 64, 128],
        ])
        #expect(MoveEngine.hasLegalMove(on: brd) == true)
    }

    @Test func allSameTileHasLegalMoves() {
        let brd = board([
            [2, 2, 2, 2],
            [2, 2, 2, 2],
            [2, 2, 2, 2],
            [2, 2, 2, 2],
        ])
        #expect(MoveEngine.hasLegalMove(on: brd) == true)
    }
}

// MARK: - SpawnTests

@Suite struct SpawnTests {

    @Test func spawnLandsOnEmptyCell() {
        var rng = SplitMix64(seed: 0)
        let brd = Board()
        let (updated, index, value) = Spawn.spawnTile(onto: brd, rng: &rng)
        #expect(updated.tiles[index] == value)
        #expect(value == 2 || value == 4)
        #expect(updated.emptyIndices.count == 15)
    }

    @Test func spawnValueIs2Or4() {
        // Run 100 spawns and assert all values are 2 or 4.
        var rng = SplitMix64(seed: 99)
        for _ in 0..<100 {
            var brd = Board()
            brd[0, 0] = 8  // keep one non-empty so we always have 15 empty
            let (_, _, value) = Spawn.spawnTile(onto: brd, rng: &rng)
            #expect(value == 2 || value == 4)
        }
    }

    @Test func spawnDistributionApproximately90_10() {
        // With 1000 draws the ratio should be within ±5% of 90/10.
        var rng = SplitMix64(seed: 42)
        var twos = 0
        var fours = 0
        for _ in 0..<1_000 {
            var brd = Board()
            brd[0, 0] = 8
            let (_, _, value) = Spawn.spawnTile(onto: brd, rng: &rng)
            if value == 2 { twos += 1 } else { fours += 1 }
        }
        #expect(twos > 850 && twos < 950, "expected ~90% twos, got \(twos)/1000")
        #expect(fours > 50 && fours < 150, "expected ~10% fours, got \(fours)/1000")
    }

    @Test func sameSeedSameSpawnSequence() {
        var rngA = SplitMix64(seed: 12345)
        var rngB = SplitMix64(seed: 12345)
        for _ in 0..<10 {
            var brd = Board()
            brd[0, 0] = 8
            let (_, idxA, valA) = Spawn.spawnTile(onto: brd, rng: &rngA)
            let (_, idxB, valB) = Spawn.spawnTile(onto: brd, rng: &rngB)
            #expect(idxA == idxB)
            #expect(valA == valB)
        }
    }

    // MARK: - Frozen seed vectors (determinism-critical contract)
    //
    // These vectors lock the spawn sequence for 3 fixed seeds.
    // They MUST NEVER CHANGE — altering them breaks Daily replays and
    // any persisted session that referenced these seed values.
    // If the spawn algorithm changes, bump Game2048Daily.generatorVersion
    // and re-derive new frozen vectors with the updated algorithm.

    /// Frozen vectors: (posIdx, value) for the first 6 spawns from each seed.
    /// posIdx = index into the current empty cell list (full board = all 16 cells).
    static let frozenVectors: [UInt64: [(posIdx: Int, value: Int)]] = [
        // Seed 0: positions + values derived from SplitMix64(seed:0).
        // Verified on macOS arm64 2026-06-12. MUST NOT CHANGE.
        0: [
            (posIdx: 15, value: 2),
            (posIdx: 4, value: 2),
            (posIdx: 9, value: 2),
            (posIdx: 10, value: 2),
            (posIdx: 11, value: 2),
            (posIdx: 4, value: 2),
        ],
        // Seed 1. MUST NOT CHANGE.
        1: [
            (posIdx: 1, value: 4),
            (posIdx: 0, value: 2),
            (posIdx: 5, value: 2),
            (posIdx: 4, value: 2),
            (posIdx: 0, value: 2),
            (posIdx: 7, value: 2),
        ],
        // Seed 42. MUST NOT CHANGE.
        42: [
            (posIdx: 5, value: 2),
            (posIdx: 3, value: 2),
            (posIdx: 6, value: 2),
            (posIdx: 10, value: 2),
            (posIdx: 1, value: 2),
            (posIdx: 2, value: 2),
        ],
    ]

    @Test func frozenVectorsMatchSeed0() {
        var rng = SplitMix64(seed: 0)
        var brd = Board()
        let expected = Self.frozenVectors[0]!
        for (i, exp) in expected.enumerated() {
            let empty = brd.emptyIndices
            let posIdx = rng.nextInt(upperBound: empty.count)
            let typeRoll = rng.nextInt(upperBound: 10)
            let value = typeRoll < 9 ? 2 : 4
            #expect(posIdx == exp.posIdx, "seed=0 spawn[\(i)]: expected posIdx=\(exp.posIdx) got \(posIdx)")
            #expect(value == exp.value, "seed=0 spawn[\(i)]: expected value=\(exp.value) got \(value)")
            brd.setTile(at: empty[posIdx], value: value)
        }
    }

    @Test func frozenVectorsMatchSeed1() {
        var rng = SplitMix64(seed: 1)
        var brd = Board()
        let expected = Self.frozenVectors[1]!
        for (i, exp) in expected.enumerated() {
            let empty = brd.emptyIndices
            let posIdx = rng.nextInt(upperBound: empty.count)
            let typeRoll = rng.nextInt(upperBound: 10)
            let value = typeRoll < 9 ? 2 : 4
            #expect(posIdx == exp.posIdx, "seed=1 spawn[\(i)]: expected posIdx=\(exp.posIdx) got \(posIdx)")
            #expect(value == exp.value, "seed=1 spawn[\(i)]: expected value=\(exp.value) got \(value)")
            brd.setTile(at: empty[posIdx], value: value)
        }
    }

    @Test func frozenVectorsMatchSeed42() {
        var rng = SplitMix64(seed: 42)
        var brd = Board()
        let expected = Self.frozenVectors[42]!
        for (i, exp) in expected.enumerated() {
            let empty = brd.emptyIndices
            let posIdx = rng.nextInt(upperBound: empty.count)
            let typeRoll = rng.nextInt(upperBound: 10)
            let value = typeRoll < 9 ? 2 : 4
            #expect(posIdx == exp.posIdx, "seed=42 spawn[\(i)]: expected posIdx=\(exp.posIdx) got \(posIdx)")
            #expect(value == exp.value, "seed=42 spawn[\(i)]: expected value=\(exp.value) got \(value)")
            brd.setTile(at: empty[posIdx], value: value)
        }
    }
}

// MARK: - DailyTests

@Suite struct DailyTests {

    @Test func sameDaySameSeed() {
        // Two timestamps in the same UTC day must yield the same seed.
        #expect(
            Game2048Daily.seed(forUTCDay: "2026-06-12")
            == Game2048Daily.seed(forUTCDay: "2026-06-12")
        )
    }

    @Test func differentDaysYieldDifferentSeeds() {
        let day1 = Game2048Daily.seed(forUTCDay: "2026-06-12")
        let day2 = Game2048Daily.seed(forUTCDay: "2026-06-13")
        #expect(day1 != day2)
    }

    @Test func seedIsNonZero() {
        // FNV-1a over non-empty input must not produce 0 for reasonable inputs.
        let seed = Game2048Daily.seed(forUTCDay: "2026-01-01")
        #expect(seed != 0)
    }

    @Test func puzzleIdFormat() {
        let id = Game2048Daily.puzzleId(forUTCDay: "2026-06-12")
        #expect(id == "daily-2048-2026-06-12")
    }

    @Test func generatorVersionIsOne() {
        #expect(Game2048Daily.generatorVersion == 1)
    }
}

// swiftlint:enable identifier_name file_length
