// BoardDismissFlushTests — issue #413.
//
// ROOT CAUSE: BoardView never flushed the GameViewModel when the board was
// dismissed (Home tap = NavigationStack pop → `.onDisappear`) or when the app
// went to the background (`scenePhase != .active`). `scheduleSave()` is
// debounced (500 ms) and its Task holds `[weak self]`; when the board tears
// down before the debounce fires, the VM deallocates, the pending save sees
// `self == nil`, and the most-recent moves + accrued elapsed are SILENTLY
// DROPPED. On the next Home → Resume, `latestInProgress()` returns the stale
// earlier autosave (or the fresh idle seed written by `loadOrCreate`), so the
// board comes back wrong/fresh and the timer shows the wrong elapsed.
//
// `dropPendingSaveOnTeardownLosesState` reproduces the data-loss mechanism:
// a pending debounced save evaporates when the VM is released. The dismiss
// flush (the BoardView fix) is the only thing that persists the latest state
// before teardown — `flushPersistsLatestSnapshotBeforeDebounceFires` pins
// that contract.

import Foundation
import SudokuGameState
import Persistence
import PersistenceTesting
import SudokuPersistence
import SudokuEngine
import Testing
@testable import SudokuUI

@MainActor
@Suite("GameViewModel — dismiss flush persists latest state (#413)")
struct BoardDismissFlushTests {

    private static let identity = PuzzleIdentity.practice(salt: 413, difficulty: .easy)

    private func makeViewModel(
        persistence: RecordingPersistence,
        debounceNanos: UInt64
    ) async -> GameViewModel {
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let session = GameSession(puzzle: puzzle)
        let viewModel = GameViewModel(
            identity: Self.identity,
            session: session,
            initialBoard: puzzle.clues,
            initialStatus: .idle,
            persistence: persistence,
            saveDebounceNanos: debounceNanos
        )
        await viewModel.startOrResume()
        return viewModel
    }

    /// Reproduces the bug's data-loss mechanism: a debounced save still in its
    /// debounce window is lost when the board tears down (VM released), because
    /// the save Task holds `[weak self]`. Without a dismiss flush, the move
    /// never reaches persistence.
    @Test func dropPendingSaveOnTeardownLosesState() async throws {
        let persistence = RecordingPersistence()
        // Long debounce so the autosave is guaranteed still pending at teardown.
        var viewModel: GameViewModel? = await makeViewModel(
            persistence: persistence,
            debounceNanos: 10_000_000_000
        )
        viewModel?.selection = GridCoordinate(row: 0, column: 0)
        await viewModel?.placeDigit(2) // schedules a debounced save (not fired)

        // Tear the board down WITHOUT flushing (current Home-tap behavior).
        viewModel = nil

        // Give the (now-orphaned, weak-self) save Task a chance to run.
        try? await Task.sleep(nanoseconds: 50_000_000)

        // BUG: the move was dropped — nothing persisted.
        #expect(await persistence.lastSavedBoard == nil)
    }

    /// The fix's contract: an explicit flush (what BoardView must call on
    /// dismiss / background) persists the latest snapshot regardless of the
    /// pending debounce window — so the next resume reads the real state.
    @Test func flushPersistsLatestSnapshotBeforeDebounceFires() async throws {
        let persistence = RecordingPersistence()
        let viewModel = await makeViewModel(persistence: persistence, debounceNanos: 10_000_000_000)
        viewModel.selection = GridCoordinate(row: 0, column: 0)
        await viewModel.placeDigit(2)

        #expect(await persistence.lastSavedBoard == nil) // debounce still pending

        await viewModel.flush() // dismiss / background hook

        let saved = try #require(await persistence.lastSavedBoard)
        #expect(saved.digit(atRow: 0, column: 0) == 2)
    }
}

/// Round-tripping fake that captures the most recent saved snapshot so the
/// test can assert what would survive to the next Home → Resume.
private actor RecordingPersistence: PersistenceProtocol {
    private(set) var lastSaved: GameSessionSnapshot?
    var lastSavedBoard: Board? { lastSaved?.currentBoard }

    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(puzzleId: String, mode: Mode, difficulty: Difficulty) async throws -> GameSessionSnapshot {
        throw PersistenceError.zoneNotProvisioned
    }
    func save(_ snapshot: GameSessionSnapshot, puzzleId: String, mode: Mode, difficulty: Difficulty) async throws {
        lastSaved = snapshot
    }
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> { [] }
    func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>] { [:] }
    func fetchPersonalRecord(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        PersonalRecord(
            recordName: "", mode: .daily, difficulty: .easy,
            bestTimeSeconds: nil, totalTimeSeconds: 0, completedCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 0), completedPuzzleIds: []
        )
    }
    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}
