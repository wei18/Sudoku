// SudokuShowcaseBoard — DEBUG-only fixed showcase board (#1054).
//
// Produces a deterministic `GameSessionSnapshot` for the App Store 03-board
// marketing capture: a puzzle with several correct fills, pencil-mark
// candidates on a few blank cells, and EXACTLY ONE conflicting entry so the
// board's red error highlight is visible.
//
// Unlike `SudokuNearWinBoard` (which builds a live `GameViewModel` directly
// and is presented through a root-level modifier), this board is reached
// through the PRODUCTION `.board(puzzleId:)` route — `UITestShowcasePersistence`
// (SudokuAppComposition) intercepts `puzzleId` and hands `BoardLoaderView`
// this fixed snapshot, exactly like a real saved game. That keeps the
// captured frame's chrome (toolbar, glass) identical to what Start would
// produce, at the cost of going through the LIVE `GameSession` actor.
//
// Determinism (#1054 acceptance item 6 — two captures must hash
// byte-identical): a live, genuinely `.playing` session's `elapsedSeconds`
// advances off a real wall clock. `BoardLoaderView.mountLoaded` restores this
// board's session with `UITestFrozenMonotonicClock` (below) instead of the
// default `LiveMonotonicClock` — `elapsedSeconds` then stays pinned at the
// snapshot's value forever, no matter how long the board stays on screen.
//
// Asymmetry vs. `MinesweeperShowcaseSession` (CR round 1/2, accepted as-is):
// that builder skips the actor entirely (`MinesweeperGameViewModel(seeded:)`)
// rather than mirroring this file's live-session + frozen-clock approach.
// Two reasons: (1) Minesweeper has no route that reaches
// `MinesweeperFreshBoardLoaderView` other than a direct
// `MinesweeperGameViewModel` construction — there is no persistence-protocol
// interception point upstream of it the way Sudoku's `BoardLoaderView` has
// (every `.board(puzzleId:)` funnels through
// `PersistenceProtocol.loadIfExists`/`loadOrCreate` first), so Sudoku's
// fixture rides that existing interception point instead of adding a new
// one. (2) `MinesweeperSession.restore(from:clock:)` DOES expose a `clock:`
// parameter, but its `applySnapshot` unconditionally normalizes a restored
// `.playing` to `.paused`, and the only way back to a genuinely `.playing`
// state is an async `resume()` call on the actor —
// `MinesweeperFreshBoardLoaderView.makeViewModel(...)` (the seam the
// showcase snapshot is injected into) is a synchronous function, so wiring
// that async dance in would mean restructuring the loader's synchronous
// seam. `BoardLoaderView.mountLoaded` here is already `async`, so the same
// frozen-clock + resume approach costs nothing extra.
//
// Availability: `#if DEBUG` only — stripped from Release builds entirely.

#if DEBUG

import Foundation
public import SudokuGameState
import SudokuEngine
import SudokuPersistence

public enum SudokuShowcaseBoard {

    /// The puzzleId `UITestShowcasePersistence` matches on and
    /// `SudokuAppComposition.uitestRoute(for:)` routes to.
    public static let puzzleId = "uitest-showcase"

    /// Fixed seed for the showcase puzzle. Distinct from
    /// `SudokuNearWinBoard.nearWinSeed` (`0x5544_3322_1100_9988`) and
    /// collision-free with `PuzzleStore`'s stableHash derivation paths
    /// (those fold in "daily" / "practice" prefix strings; this does not).
    public static let seed: UInt64 = 0x1DEA_B0AD_5C0B_1054

    /// Number of non-given cells filled with their correct solution digit.
    private static let correctFillCount = 8

    /// Number of blank cells given pencil-mark candidates.
    private static let noteCellCount = 4

    /// Frozen elapsed-time value baked into the snapshot. See the header doc
    /// for why this never actually advances once mounted.
    private static let elapsedSeconds = 96

    /// Build the fixed showcase snapshot: the puzzle's givens, plus
    /// `correctFillCount` cells filled with their true solution digit, plus
    /// EXACTLY ONE cell holding a digit that conflicts with a GIVEN peer —
    /// copying a peer that is itself one of the correct fills would flag
    /// that peer too, since `GameViewModel.recomputeErrors()` only excludes
    /// givens — plus `noteCellCount` blank cells carrying legal pencil-mark
    /// candidates (computed from the actual final board, never hand-picked).
    ///
    /// The wrong cell is chosen FIRST, purely from the puzzle's givens (never
    /// from a correct fill), and every correct fill is then chosen to
    /// EXCLUDE the wrong cell's own row/column/box peers — a peer holding
    /// its true solution digit could, in principle, coincidentally equal the
    /// wrong digit (a value shared by two DIFFERENT units of the wrong cell
    /// that never conflict with each other), which would flag that peer too
    /// and break the "exactly one conflict" guarantee. Excluding all of the
    /// wrong cell's peers from the correct-fill pool removes that
    /// possibility entirely, not just the digit-collision case.
    public static func snapshot() throws -> GameSessionSnapshot {
        let generator = LivePuzzleGenerating()
        let puzzle = try generator.generate(seed: seed, difficulty: .easy, version: .v1)

        let nonGivenIndices = (0..<Board.cellCount).filter { !puzzle.clues.givenMask[$0] }

        // Exactly one wrong entry: the first non-given cell whose
        // row/column/box has a GIVEN peer — the wrong digit is that given's
        // digit, guaranteeing a conflict at the candidate without ever
        // flagging the given itself. Computed from `puzzle.clues` alone
        // (givens only), independent of which cells become correct fills.
        guard let wrongEntry = nonGivenIndices.lazy.compactMap({ index in
            givenPeerDigit(atIndex: index, board: puzzle.clues).map { (index: index, digit: $0) }
        }).first else {
            throw SudokuShowcaseBoardError.noConflictableCell
        }

        let wrongPeers = Set(peerIndices(ofIndex: wrongEntry.index))
        let correctFillIndices = Array(
            nonGivenIndices
                .filter { $0 != wrongEntry.index && !wrongPeers.contains($0) }
                .prefix(correctFillCount)
        )
        guard correctFillIndices.count == correctFillCount else {
            throw SudokuShowcaseBoardError.notEnoughBlankCells
        }

        var currentBoard = puzzle.clues
        for index in correctFillIndices {
            try currentBoard.setDigit(Int(puzzle.solution.cells[index]), atIndex: index)
        }
        try currentBoard.setDigit(wrongEntry.digit, atIndex: wrongEntry.index)

        // Pencil notes: the next blank cells (never given, never filled
        // above), each seeded with its own legal candidates under the FINAL
        // board. Notes never affect conflict detection (only placed digits
        // do), so they carry no restriction relative to the wrong cell.
        var notes = NotesGrid()
        let usedIndices = Set(correctFillIndices).union([wrongEntry.index])
        let noteIndices = nonGivenIndices.filter { !usedIndices.contains($0) }.prefix(noteCellCount)
        for index in noteIndices {
            let row = index / Board.dimension
            let col = index % Board.dimension
            for digit in legalCandidates(atIndex: index, in: currentBoard).prefix(3) {
                notes.toggle(digit: digit, row: row, col: col)
            }
        }

        return GameSessionSnapshot(
            puzzle: puzzle,
            currentBoard: currentBoard,
            status: .paused,
            elapsedSeconds: elapsedSeconds,
            undoMoves: [],
            redoMoves: [],
            notes: notes,
            startedAt: nil,
            mistakeCount: 1
        )
    }

    /// Every OTHER index sharing `index`'s row, column, or 3×3 box (the
    /// standard 20-cell Sudoku peer set). Shared helper for
    /// `givenPeerDigit(atIndex:board:)` / `legalCandidates(atIndex:in:)` and
    /// for excluding the wrong cell's peers from the correct-fill pool.
    private static func peerIndices(ofIndex index: Int) -> [Int] {
        let row = index / Board.dimension
        let col = index % Board.dimension
        var peers: [Int] = []
        for col2 in 0..<Board.dimension where col2 != col {
            peers.append(Board.index(row: row, column: col2))
        }
        for row2 in 0..<Board.dimension where row2 != row {
            peers.append(Board.index(row: row2, column: col))
        }
        let boxRowOrigin = (row / 3) * 3
        let boxColOrigin = (col / 3) * 3
        for row2 in boxRowOrigin..<boxRowOrigin + 3 {
            for col2 in boxColOrigin..<boxColOrigin + 3 where !(row2 == row && col2 == col) {
                peers.append(Board.index(row: row2, column: col2))
            }
        }
        return peers
    }

    /// The digit of a GIVEN peer of `index` in `board`, or `nil` if none of
    /// its peers are givens. Used to source a guaranteed, given-anchored
    /// conflict.
    private static func givenPeerDigit(atIndex index: Int, board: Board) -> Int? {
        for peerIndex in peerIndices(ofIndex: index) {
            if board.givenMask[peerIndex], let digit = board.digit(atIndex: peerIndex) { return digit }
        }
        return nil
    }

    /// Digits 1...9 that do not already appear among `index`'s peers in
    /// `board` — i.e. digits legal to pencil there right now.
    private static func legalCandidates(atIndex index: Int, in board: Board) -> [Int] {
        let present = Set(peerIndices(ofIndex: index).compactMap { board.digit(atIndex: $0) })
        return (1...9).filter { !present.contains($0) }
    }
}

enum SudokuShowcaseBoardError: Error {
    case notEnoughBlankCells
    case noConflictableCell
}

// MARK: - Frozen clock (determinism — #1054)

/// A `MonotonicClock` that never advances. Injected by
/// `BoardLoaderView.mountLoaded` ONLY for `SudokuShowcaseBoard.puzzleId` so
/// the mounted board's `elapsedSeconds` stays pinned at the snapshot's value
/// forever — see this file's header doc.
struct UITestFrozenMonotonicClock: MonotonicClock {
    var now: TimeInterval { 0 }
}

#endif
