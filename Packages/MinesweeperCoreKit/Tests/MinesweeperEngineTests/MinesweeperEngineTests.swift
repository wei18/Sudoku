// swiftlint:disable identifier_name file_length
// `r`, `c`, `e`, `d`, etc. are idiomatic for tight test code (row / col /
// engine / difficulty); the comprehensive 9-suite engine coverage drives
// file > 400 lines. Test fixture — both rules disabled at file scope.

import Foundation
import Testing
@testable import MinesweeperEngine

// MARK: - Helpers

private func freshEngine(_ difficulty: Difficulty = .beginner, seed: UInt64 = 0xDEAD_BEEF) -> MinesweeperEngine {
    MinesweeperEngine(difficulty: difficulty, seed: seed)
}

private func revealAllSafe(_ engine: inout MinesweeperEngine) throws {
    for r in 0..<engine.rows {
        for c in 0..<engine.columns {
            let cell = try engine.cell(at: r, col: c)
            if !cell.isMine && cell.state == .hidden {
                try engine.reveal(row: r, col: c)
            }
        }
    }
}

// MARK: - DifficultyTests

@Suite struct DifficultyTests {
    @Test func beginnerDimensions() {
        #expect(Difficulty.beginner.rows == 9)
        #expect(Difficulty.beginner.columns == 9)
        #expect(Difficulty.beginner.mineCount == 10)
        #expect(Difficulty.beginner.cellCount == 81)
    }
    @Test func intermediateDimensions() {
        #expect(Difficulty.intermediate.rows == 16)
        #expect(Difficulty.intermediate.columns == 16)
        #expect(Difficulty.intermediate.mineCount == 40)
        #expect(Difficulty.intermediate.cellCount == 256)
    }
    @Test func expertDimensions() {
        #expect(Difficulty.expert.rows == 16)
        #expect(Difficulty.expert.columns == 30)
        #expect(Difficulty.expert.mineCount == 99)
        #expect(Difficulty.expert.cellCount == 480)
    }
    @Test func allCasesPresent() {
        #expect(Difficulty.allCases.count == 3)
        #expect(Set(Difficulty.allCases) == [.beginner, .intermediate, .expert])
    }
    @Test func codableRoundTrip() throws {
        for d in Difficulty.allCases {
            let data = try JSONEncoder().encode(d)
            let decoded = try JSONDecoder().decode(Difficulty.self, from: data)
            #expect(decoded == d)
        }
    }
    @Test func capacityLeavesRoomForSafeRegion() {
        for d in Difficulty.allCases {
            #expect(d.mineCount <= d.cellCount - 9)
        }
    }
}

// MARK: - InitTests

@Suite struct InitTests {
    @Test func startsWithNoMinesPlaced() {
        let e = freshEngine()
        #expect(e.minesPlaced == false)
        #expect(e.isLost == false)
        #expect(e.isWon == false)
        #expect(e.moves.isEmpty)
        #expect(e.cells.count == Difficulty.beginner.cellCount)
        for c in e.cells {
            #expect(c.isMine == false)
            #expect(c.neighborMineCount == 0)
            #expect(c.state == .hidden)
        }
    }
    @Test func indexingIsRowMajor() {
        let e = freshEngine(.intermediate)
        #expect(e.index(row: 0, col: 0) == 0)
        #expect(e.index(row: 0, col: 15) == 15)
        #expect(e.index(row: 1, col: 0) == 16)
        #expect(e.index(row: 15, col: 15) == 255)
    }
    @Test func inBoundsCheck() {
        let e = freshEngine()
        #expect(e.inBounds(row: 0, col: 0))
        #expect(e.inBounds(row: 8, col: 8))
        #expect(!e.inBounds(row: 9, col: 0))
        #expect(!e.inBounds(row: 0, col: 9))
        #expect(!e.inBounds(row: -1, col: 0))
        #expect(!e.inBounds(row: 0, col: -1))
    }
}

// MARK: - MinePlacementTests

@Suite struct MinePlacementTests {
    @Test func sameSeedAndFirstClickProducesSameLayout() throws {
        var a = freshEngine(.intermediate, seed: 42)
        var b = freshEngine(.intermediate, seed: 42)
        try a.reveal(row: 5, col: 5)
        try b.reveal(row: 5, col: 5)
        let aMines = a.cells.map { $0.isMine }
        let bMines = b.cells.map { $0.isMine }
        #expect(aMines == bMines)
    }
    @Test func differentSeedsProduceDifferentLayouts() throws {
        var a = freshEngine(.intermediate, seed: 1)
        var b = freshEngine(.intermediate, seed: 2)
        try a.reveal(row: 5, col: 5)
        try b.reveal(row: 5, col: 5)
        #expect(a.cells.map(\.isMine) != b.cells.map(\.isMine))
    }
    @Test func differentFirstClicksProduceDifferentLayouts() throws {
        var a = freshEngine(.intermediate, seed: 42)
        var b = freshEngine(.intermediate, seed: 42)
        try a.reveal(row: 0, col: 0)
        try b.reveal(row: 10, col: 10)
        #expect(a.cells.map(\.isMine) != b.cells.map(\.isMine))
    }
    @Test func minePlacementHonorsMineCount() throws {
        for d in Difficulty.allCases {
            var e = MinesweeperEngine(difficulty: d, seed: 7)
            try e.reveal(row: 0, col: 0)
            let mines = e.cells.filter(\.isMine).count
            #expect(mines == d.mineCount)
        }
    }
    @Test func firstClickAndNeighborsAreMineFree_corner() throws {
        var e = freshEngine(.beginner, seed: 123)
        try e.reveal(row: 0, col: 0)
        for (nr, nc) in e.neighborCoords(row: 0, col: 0) + [(0, 0)] {
            #expect(e.cells[e.index(row: nr, col: nc)].isMine == false)
        }
    }
    @Test func firstClickAndNeighborsAreMineFree_center() throws {
        var e = freshEngine(.intermediate, seed: 456)
        try e.reveal(row: 8, col: 8)
        for (nr, nc) in e.neighborCoords(row: 8, col: 8) + [(8, 8)] {
            #expect(e.cells[e.index(row: nr, col: nc)].isMine == false)
        }
    }
    @Test func firstClickSafetyAcrossManySeeds() throws {
        for seed in (UInt64(0)..<50) {
            var e = freshEngine(.expert, seed: seed)
            try e.reveal(row: 7, col: 14)
            for (nr, nc) in e.neighborCoords(row: 7, col: 14) + [(7, 14)] {
                #expect(e.cells[e.index(row: nr, col: nc)].isMine == false,
                        "seed=\(seed) had mine in safe region at (\(nr),\(nc))")
            }
        }
    }
    @Test func minesPlacedFlagFlipsAfterFirstReveal() throws {
        var e = freshEngine()
        #expect(e.minesPlaced == false)
        try e.reveal(row: 4, col: 4)
        #expect(e.minesPlaced == true)
    }
    @Test func flagBeforeFirstRevealDoesNotPlaceMines() throws {
        var e = freshEngine()
        try e.toggleFlag(row: 0, col: 0)
        #expect(e.minesPlaced == false)
    }
}

// MARK: - FixedLayoutTests (#841)

/// #841 "daily retry after loss generates a different board per first click
/// — daily must be one fixed game": `MinesweeperEngine.init(difficulty:seed:
/// fixedMineIndices:)` places mines immediately, decoupled from any click —
/// the mechanism the daily-replay loader uses to reproduce the exact board
/// a player already lost on, regardless of where the retry's first tap
/// lands. These tests cover the engine contract directly (no CloudKit /
/// SwiftUI involved); `MinesweeperDailyReplayLoaderView` in MinesweeperKit
/// covers the end-to-end persisted-record recovery.
@Suite struct FixedLayoutTests {
    @Test func placesMinesExactlyAtGivenIndices() throws {
        let indices: Set<Int> = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
        let e = try MinesweeperEngine(difficulty: .beginner, seed: 42, fixedMineIndices: indices)
        #expect(e.minesPlaced == true)
        let actualMineIndices = Set(e.cells.indices.filter { e.cells[$0].isMine })
        #expect(actualMineIndices == indices)
    }

    /// The core #841 acceptance criterion: a fixed-layout engine reveals the
    /// IDENTICAL mine layout no matter which cell is clicked first — unlike
    /// the deferred/salted path (`differentFirstClicksProduceDifferentLayouts`
    /// above), the layout is already baked in at construction.
    @Test func sameFixedIndicesProduceSameLayoutRegardlessOfFirstClick() throws {
        let indices: Set<Int> = [5, 17, 33, 44, 55, 61, 70, 72, 80, 12]
        var a = try MinesweeperEngine(difficulty: .beginner, seed: 1, fixedMineIndices: indices)
        var b = try MinesweeperEngine(difficulty: .beginner, seed: 2, fixedMineIndices: indices)
        // Different retries can even carry different seeds — the fixed
        // layout wins either way, matching how the replay loader threads
        // the daily's original seed but the layout is what actually matters.
        _ = try? a.reveal(row: 0, col: 0)
        _ = try? b.reveal(row: 8, col: 8)
        #expect(a.cells.map(\.isMine) == b.cells.map(\.isMine))
        #expect(a.cells.map(\.isMine).filter { $0 }.count == Difficulty.beginner.mineCount)
    }

    @Test func neighborCountsAreComputedForFixedLayout() throws {
        // A single mine at index 0 plus 9 far-away filler mines (row 8) so
        // the count stays exactly `Difficulty.beginner.mineCount` (10)
        // without disturbing the neighbor cells under test.
        let indices: Set<Int> = [0, 72, 73, 74, 75, 76, 77, 78, 79, 80]
        var e = try MinesweeperEngine(difficulty: .beginner, seed: 7, fixedMineIndices: indices)
        try e.reveal(row: 4, col: 4)
        // Cell (0,1) and (1,0) and (1,1) neighbor the mine at index 0.
        #expect(e.cells[e.index(row: 0, col: 1)].neighborMineCount == 1)
        #expect(e.cells[e.index(row: 1, col: 0)].neighborMineCount == 1)
        #expect(e.cells[e.index(row: 1, col: 1)].neighborMineCount == 1)
    }

    /// Second-attempt semantics (explicit dispatch decision): a fixed replay
    /// layout has NO first-click safety — clicking directly on a fixed mine
    /// loses immediately, same as any other reveal. No special-casing.
    @Test func firstClickOnFixedLayoutCanHitAMine() throws {
        let indices: Set<Int> = [0, 72, 73, 74, 75, 76, 77, 78, 79, 80]
        var e = try MinesweeperEngine(difficulty: .beginner, seed: 7, fixedMineIndices: indices)
        try e.reveal(row: 0, col: 0)
        #expect(e.isLost == true)
        #expect(e.cells[0].state == .revealed)
    }

    @Test func fixedLayoutWithWrongMineCountThrows() {
        let tooFew: Set<Int> = [0, 1, 2]
        #expect(throws: MinesweeperError.invalidFixedLayout(expected: Difficulty.beginner.mineCount, found: 3)) {
            _ = try MinesweeperEngine(difficulty: .beginner, seed: 1, fixedMineIndices: tooFew)
        }
    }

    @Test func fixedLayoutWithOutOfBoundsIndexThrows() {
        var indices = Set(0..<9)
        indices.insert(Difficulty.beginner.cellCount) // one past the end
        #expect(throws: MinesweeperError.self) {
            _ = try MinesweeperEngine(difficulty: .beginner, seed: 1, fixedMineIndices: indices)
        }
    }

    @Test func fixedLayoutEngineWinsNormallyWhenAllSafeRevealed() throws {
        // Mines in a corner region; reveal everything else via the flood
        // fill from an opposite corner.
        var e = try MinesweeperEngine(difficulty: .beginner, seed: 1, fixedMineIndices: [0, 1, 2, 3, 4, 5, 6, 7, 8, 17])
        try e.reveal(row: 8, col: 8)
        for r in 0..<e.rows {
            for c in 0..<e.columns {
                let cell = try e.cell(at: r, col: c)
                if !cell.isMine && cell.state == .hidden {
                    try e.reveal(row: r, col: c)
                }
            }
        }
        #expect(e.isWon == true)
    }
}

// MARK: - NeighborCountTests

@Suite struct NeighborCountTests {
    @Test func neighborCountMatchesActualMines() throws {
        for seed in (UInt64(0)..<10) {
            var e = freshEngine(.intermediate, seed: seed)
            try e.reveal(row: 0, col: 0)
            for r in 0..<e.rows {
                for c in 0..<e.columns {
                    let i = e.index(row: r, col: c)
                    if e.cells[i].isMine { continue }
                    let actual = e.neighborIndices(row: r, col: c).filter { e.cells[$0].isMine }.count
                    #expect(e.cells[i].neighborMineCount == actual,
                            "(\(r),\(c)) seed=\(seed): stored=\(e.cells[i].neighborMineCount) actual=\(actual)")
                }
            }
        }
    }
    @Test func neighborCountInRange0to8() throws {
        var e = freshEngine(.expert, seed: 99)
        try e.reveal(row: 0, col: 0)
        for c in e.cells where !c.isMine {
            #expect((0...8).contains(c.neighborMineCount))
        }
    }
    @Test func cornerNeighborsCountThree() {
        let e = freshEngine()
        #expect(e.neighborCoords(row: 0, col: 0).count == 3)
        #expect(e.neighborCoords(row: 0, col: 8).count == 3)
        #expect(e.neighborCoords(row: 8, col: 0).count == 3)
        #expect(e.neighborCoords(row: 8, col: 8).count == 3)
    }
    @Test func edgeNeighborsCountFive() {
        let e = freshEngine()
        #expect(e.neighborCoords(row: 0, col: 4).count == 5)
        #expect(e.neighborCoords(row: 4, col: 0).count == 5)
        #expect(e.neighborCoords(row: 8, col: 4).count == 5)
        #expect(e.neighborCoords(row: 4, col: 8).count == 5)
    }
    @Test func interiorNeighborsCountEight() {
        let e = freshEngine()
        #expect(e.neighborCoords(row: 4, col: 4).count == 8)
    }
}

// MARK: - FloodFillTests

@Suite struct FloodFillTests {
    @Test func revealingZeroCellCascades() throws {
        for seed in (UInt64(0)..<20) {
            var e = freshEngine(.beginner, seed: seed)
            try e.reveal(row: 4, col: 4)
            let revealed = e.cells.filter { $0.state == .revealed }.count
            #expect(revealed >= 9, "seed=\(seed) revealed=\(revealed)")
            if e.cells[e.index(row: 4, col: 4)].neighborMineCount == 0 {
                #expect(revealed > 9)
            }
        }
    }
    @Test func cascadeStopsAtNonzeroBorder() throws {
        var e = freshEngine(.intermediate, seed: 12345)
        try e.reveal(row: 8, col: 8)
        for r in 0..<e.rows {
            for c in 0..<e.columns {
                let cell = e.cells[e.index(row: r, col: c)]
                guard cell.state == .revealed, cell.neighborMineCount == 0, !cell.isMine else { continue }
                for (nr, nc) in e.neighborCoords(row: r, col: c) {
                    let n = e.cells[e.index(row: nr, col: nc)]
                    #expect(n.state == .revealed || n.state == .flagged,
                            "zero-cell at (\(r),\(c)) has non-revealed neighbor (\(nr),\(nc)) state=\(n.state)")
                }
            }
        }
    }
    @Test func cascadeNeverRevealsMines() throws {
        for seed in (UInt64(0)..<10) {
            var e = freshEngine(.intermediate, seed: seed)
            try e.reveal(row: 5, col: 5)
            for cell in e.cells where cell.isMine {
                #expect(cell.state != .revealed)
            }
        }
    }
    @Test func cascadeSkipsFlaggedCells() throws {
        var e = freshEngine(.beginner, seed: 7)
        try e.reveal(row: 0, col: 0)
        var flagged: (Int, Int)?
        for r in 0..<e.rows {
            for c in 0..<e.columns {
                let cell = try e.cell(at: r, col: c)
                if cell.state == .hidden && !cell.isMine {
                    try e.toggleFlag(row: r, col: c)
                    flagged = (r, c)
                    break
                }
            }
            if flagged != nil { break }
        }
        guard let (fr, fc) = flagged else {
            Issue.record("could not find a hidden non-mine cell to flag")
            return
        }
        for r in 0..<e.rows {
            for c in 0..<e.columns where (r, c) != (fr, fc) {
                let cell = try e.cell(at: r, col: c)
                if !cell.isMine && cell.state == .hidden {
                    try e.reveal(row: r, col: c)
                }
            }
        }
        #expect(e.cells[e.index(row: fr, col: fc)].state == .flagged)
    }
    @Test func revealOnFlaggedCellIsNoop() throws {
        var e = freshEngine()
        try e.reveal(row: 0, col: 0)
        var target: (Int, Int)?
        for r in 0..<e.rows {
            for c in 0..<e.columns where e.cells[e.index(row: r, col: c)].state == .hidden {
                target = (r, c)
                break
            }
            if target != nil { break }
        }
        let (r, c) = target!
        try e.toggleFlag(row: r, col: c)
        let beforeMoves = e.moves.count
        try e.reveal(row: r, col: c)
        #expect(e.cells[e.index(row: r, col: c)].state == .flagged)
        #expect(e.moves.count == beforeMoves)
    }
    @Test func revealOnAlreadyRevealedIsNoop() throws {
        var e = freshEngine()
        try e.reveal(row: 4, col: 4)
        let snapshot = e.cells
        let movesBefore = e.moves.count
        try e.reveal(row: 4, col: 4)
        #expect(e.cells == snapshot)
        #expect(e.moves.count == movesBefore)
    }
}

// MARK: - WinLoseTests

@Suite struct WinLoseTests {
    @Test func winWhenAllSafeRevealed() throws {
        var e = freshEngine(.beginner, seed: 13)
        try e.reveal(row: 4, col: 4)
        try revealAllSafe(&e)
        #expect(e.isWon == true)
        #expect(e.isLost == false)
    }
    @Test func loseWhenMineRevealed() throws {
        var e = freshEngine(.beginner, seed: 13)
        try e.reveal(row: 4, col: 4)
        var minePos: (Int, Int)?
        for r in 0..<e.rows {
            for c in 0..<e.columns where e.cells[e.index(row: r, col: c)].isMine {
                minePos = (r, c); break
            }
            if minePos != nil { break }
        }
        let (mr, mc) = minePos!
        try e.reveal(row: mr, col: mc)
        #expect(e.isLost == true)
        #expect(e.isWon == false)
        #expect(e.cells[e.index(row: mr, col: mc)].state == .revealed)
    }
    @Test func revealAfterLossIsNoop() throws {
        var e = freshEngine(.beginner, seed: 13)
        try e.reveal(row: 4, col: 4)
        var minePos: (Int, Int)?
        for r in 0..<e.rows {
            for c in 0..<e.columns where e.cells[e.index(row: r, col: c)].isMine {
                minePos = (r, c); break
            }
            if minePos != nil { break }
        }
        try e.reveal(row: minePos!.0, col: minePos!.1)
        let snapshot = e.cells
        try e.reveal(row: 0, col: 0)
        #expect(e.cells == snapshot)
    }
    @Test func freshEngineIsNotWon() {
        let e = freshEngine()
        #expect(e.isWon == false)
        #expect(e.isLost == false)
    }
    @Test func flaggingNonMinesDoesNotBlockWin() throws {
        var e = freshEngine(.beginner, seed: 13)
        try e.reveal(row: 4, col: 4)
        var flagged: [(Int, Int)] = []
        for r in 0..<e.rows {
            for c in 0..<e.columns {
                let cell = e.cells[e.index(row: r, col: c)]
                if cell.state == .hidden && !cell.isMine && flagged.count < 3 {
                    try e.toggleFlag(row: r, col: c)
                    flagged.append((r, c))
                }
            }
        }
        for (r, c) in flagged { try e.toggleFlag(row: r, col: c) }
        try revealAllSafe(&e)
        #expect(e.isWon == true)
    }
}

// MARK: - FlagTests

@Suite struct FlagTests {
    @Test func toggleFlagHiddenToFlagged() throws {
        var e = freshEngine()
        let s = try e.toggleFlag(row: 3, col: 3)
        #expect(s == .flagged)
        #expect(e.cells[e.index(row: 3, col: 3)].state == .flagged)
        #expect(e.moves == [.flag(row: 3, col: 3)])
    }
    @Test func toggleFlagFlaggedToHidden() throws {
        var e = freshEngine()
        try e.toggleFlag(row: 3, col: 3)
        let s = try e.toggleFlag(row: 3, col: 3)
        #expect(s == .hidden)
        #expect(e.cells[e.index(row: 3, col: 3)].state == .hidden)
        #expect(e.moves == [.flag(row: 3, col: 3), .unflag(row: 3, col: 3)])
    }
    @Test func toggleFlagIdempotentAfterEvenToggles() throws {
        var e = freshEngine()
        for _ in 0..<6 { try e.toggleFlag(row: 2, col: 2) }
        #expect(e.cells[e.index(row: 2, col: 2)].state == .hidden)
    }
    @Test func toggleFlagOnRevealedIsNoop() throws {
        var e = freshEngine()
        try e.reveal(row: 4, col: 4)
        var revealedPos: (Int, Int)?
        for r in 0..<e.rows {
            for c in 0..<e.columns where e.cells[e.index(row: r, col: c)].state == .revealed {
                revealedPos = (r, c); break
            }
            if revealedPos != nil { break }
        }
        let (r, c) = revealedPos!
        let movesBefore = e.moves.count
        let s = try e.toggleFlag(row: r, col: c)
        #expect(s == .revealed)
        #expect(e.cells[e.index(row: r, col: c)].state == .revealed)
        #expect(e.moves.count == movesBefore)
    }
    @Test func flagDoesNotPlaceMines() throws {
        var e = freshEngine()
        try e.toggleFlag(row: 0, col: 0)
        try e.toggleFlag(row: 0, col: 0)
        #expect(e.minesPlaced == false)
        #expect(e.cells.allSatisfy { !$0.isMine })
    }
}

// MARK: - OutOfBoundsTests

@Suite struct OutOfBoundsTests {
    @Test func revealNegativeRow() {
        var e = freshEngine()
        #expect(throws: MinesweeperError.outOfBounds(row: -1, col: 0)) {
            try e.reveal(row: -1, col: 0)
        }
    }
    @Test func revealNegativeCol() {
        var e = freshEngine()
        #expect(throws: MinesweeperError.outOfBounds(row: 0, col: -1)) {
            try e.reveal(row: 0, col: -1)
        }
    }
    @Test func revealRowEqualsRows() {
        var e = freshEngine()
        #expect(throws: MinesweeperError.outOfBounds(row: 9, col: 0)) {
            try e.reveal(row: 9, col: 0)
        }
    }
    @Test func revealColEqualsColumns() {
        var e = freshEngine()
        #expect(throws: MinesweeperError.outOfBounds(row: 0, col: 9)) {
            try e.reveal(row: 0, col: 9)
        }
    }
    @Test func flagOutOfBoundsThrows() {
        var e = freshEngine()
        #expect(throws: MinesweeperError.self) { try e.toggleFlag(row: -1, col: 0) }
        #expect(throws: MinesweeperError.self) { try e.toggleFlag(row: 0, col: 100) }
    }
    @Test func cellAtOutOfBoundsThrows() {
        let e = freshEngine()
        #expect(throws: MinesweeperError.self) { _ = try e.cell(at: -1, col: 0) }
        #expect(throws: MinesweeperError.self) { _ = try e.cell(at: 9, col: 9) }
    }
}

// MARK: - DeterminismTests

@Suite struct DeterminismTests {
    @Test func replayFromMoveLogProducesIdenticalState() throws {
        var original = freshEngine(.intermediate, seed: 0xCAFE)
        try original.reveal(row: 5, col: 5)
        try original.toggleFlag(row: 0, col: 0)
        try original.toggleFlag(row: 0, col: 1)
        try original.reveal(row: 10, col: 10)
        try original.toggleFlag(row: 0, col: 0)
        try original.reveal(row: 1, col: 1)

        var replay = freshEngine(.intermediate, seed: 0xCAFE)
        for move in original.moves {
            switch move {
            case .reveal(let r, let c):
                try replay.reveal(row: r, col: c)
            case .flag(let r, let c), .unflag(let r, let c):
                try replay.toggleFlag(row: r, col: c)
            }
        }
        #expect(original.cells == replay.cells)
        #expect(original.moves == replay.moves)
        #expect(original.isLost == replay.isLost)
        #expect(original.isWon == replay.isWon)
    }
    @Test func splitMix64BitIdentical() {
        var a = SplitMix64(seed: 0x1234_5678)
        var b = SplitMix64(seed: 0x1234_5678)
        for _ in 0..<1_000 {
            #expect(a.next() == b.next())
        }
    }
    @Test func splitMix64DifferentSeeds() {
        var a = SplitMix64(seed: 0)
        var b = SplitMix64(seed: 1)
        var same = 0
        for _ in 0..<100 where a.next() == b.next() { same += 1 }
        #expect(same < 5)
    }
    @Test func moveLogContainsExpectedEntries() throws {
        var e = freshEngine()
        try e.reveal(row: 4, col: 4)
        try e.toggleFlag(row: 0, col: 0)
        try e.toggleFlag(row: 0, col: 0)
        #expect(e.moves.count == 3)
        #expect(e.moves[0] == .reveal(row: 4, col: 4))
        #expect(e.moves[1] == .flag(row: 0, col: 0))
        #expect(e.moves[2] == .unflag(row: 0, col: 0))
    }
    @Test func cellCodableRoundTrip() throws {
        let c = Cell(isMine: true, neighborMineCount: 5, state: .flagged)
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(Cell.self, from: data)
        #expect(decoded == c)
    }
    @Test func moveCodableRoundTrip() throws {
        let moves: [Move] = [.reveal(row: 1, col: 2), .flag(row: 3, col: 4), .unflag(row: 5, col: 6)]
        let data = try JSONEncoder().encode(moves)
        let decoded = try JSONDecoder().decode([Move].self, from: data)
        #expect(decoded == moves)
    }
}

// swiftlint:enable identifier_name file_length
