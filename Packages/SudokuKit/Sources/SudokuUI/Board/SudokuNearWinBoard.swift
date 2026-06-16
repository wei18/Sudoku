// SudokuNearWinBoard — DEBUG-only near-win board builder (#510 uitest hook).
//
// Produces a `GameViewModel` over a real `GameSession` where the solution is
// fully filled in except ONE empty cell. Entering that digit triggers the real
// win → completion flow so the interactive UX audit (and future XCUITest #510)
// can exercise it with a single tap.
//
// Determinism: uses `LivePuzzleGenerating` with a well-known fixed seed so
// the board is identical on every cold launch (reproducible test run).
// The seed is chosen to be well-known in logs; it does NOT move any frozen
// seed vector from PuzzleStore's deterministic generation path.
//
// Availability: compiled into DEBUG builds only (entire file inside `#if
// DEBUG`). The Release binary has zero knowledge of this type.

#if DEBUG

import Foundation
import GameState
import SudokuEngine
import PuzzleStore
import Persistence
import Telemetry

/// A fully-specified near-win scenario: the `GameViewModel` has a real live
/// session where all cells are filled in except `emptyIndex`. The caller mounts
/// `BoardView(viewModel:)` directly and a single digit entry completes the game.
@MainActor
public struct SudokuNearWinBoard {
    public let viewModel: GameViewModel
    /// The flat board index (0…80) of the ONE remaining empty cell.
    public let emptyIndex: Int
    /// The correct digit (1…9) that fills `emptyIndex` and wins the game.
    public let winningDigit: Int
}

extension SudokuNearWinBoard {

    /// Deterministic seed for the near-win puzzle. Chosen to be recognizable in
    /// logs and collision-free with PuzzleStore's stableHash seed derivation paths
    /// (those fold in "daily" / "practice" prefix strings, this does not).
    public static let nearWinSeed: UInt64 = 0x5544_3322_1100_9988

    /// Build a near-win board. Async because `GameSession.restore` is actor-
    /// isolated. Throws only if the generator produces a degenerate puzzle —
    /// not expected with the hardcoded seed below.
    public static func build() async throws -> SudokuNearWinBoard {
        let generator = LivePuzzleGenerating()
        let puzzle = try generator.generate(seed: nearWinSeed, difficulty: .easy, version: .v1)

        // Build a board that is the solution with exactly the last non-given
        // cell cleared. We pick the last non-given cell so the clue cells are
        // unaffected and the board is visually "almost done".
        var nearWinBoard = puzzle.solution
        let nonGivenIndices = (0..<Board.cellCount).filter { !puzzle.clues.givenMask[$0] }
        guard let emptyIndex = nonGivenIndices.last else {
            throw SudokuNearWinError.noEmptyCell
        }
        let winningDigit = Int(puzzle.solution.cells[emptyIndex])
        try nearWinBoard.setDigit(nil, atIndex: emptyIndex)

        // Restore a paused session from a snapshot so `BoardLoaderView` and
        // persistence are bypassed entirely — this board never touches CloudKit.
        let snapshot = GameSessionSnapshot(
            puzzle: puzzle,
            currentBoard: nearWinBoard,
            status: .paused,
            elapsedSeconds: 0,
            undoMoves: [],
            redoMoves: [],
            notes: NotesGrid()
        )
        let session = await GameSession.restore(from: snapshot)

        // Use the `.practice` puzzleId shape so the identity parses cleanly.
        // Salt 0 encodes as "0" in Crockford base32 → "practice-0-easy".
        let identity = PuzzleIdentity(puzzleId: "practice-0-easy", kind: .practice, difficulty: .easy)

        let viewModel = GameViewModel(
            identity: identity,
            session: session,
            initialBoard: nearWinBoard,
            initialStatus: .paused,
            persistence: NearWinNoopPersistence()
        )
        // Resume so digit taps pass the `.playing` guard in `GameSession`.
        await viewModel.startOrResume()

        return SudokuNearWinBoard(
            viewModel: viewModel,
            emptyIndex: emptyIndex,
            winningDigit: winningDigit
        )
    }
}

// MARK: - Errors

public struct SudokuNearWinError: Error {
    public static let noEmptyCell = SudokuNearWinError(message: "puzzle has no non-given cells")
    public let message: String
}

// MARK: - Zero-IO persistence (near-win boards must not pollute CloudKit)

/// Minimal `PersistenceProtocol` that no-ops all writes and returns empty
/// results on reads. The near-win `GameViewModel` will call `save()` on digit
/// placement; we want that to silently succeed without touching CloudKit.
private actor NearWinNoopPersistence: PersistenceProtocol {
    func bootstrap() async throws {}

    func latestInProgress() async throws -> SavedGameSummary? { nil }

    func loadOrCreate(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> GameSessionSnapshot {
        // Not called: the near-win builder restores from a snapshot directly
        // and passes the VM directly to the board view.
        throw NearWinNoopError.notSupported
    }

    func save(
        _ snapshot: GameSessionSnapshot,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws {}

    func markCompleted(_ summary: SavedGameSummary) async throws {}

    func deleteAbandoned(recordName: String) async throws {}

    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> { [] }

    func fetchPersonalRecord(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        PersonalRecord(
            recordName: "",
            mode: mode,
            difficulty: difficulty,
            bestTimeSeconds: nil,
            totalTimeSeconds: 0,
            completedCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 0),
            completedPuzzleIds: []
        )
    }

    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}

private struct NearWinNoopError: Error {
    static let notSupported = NearWinNoopError()
}

#endif
