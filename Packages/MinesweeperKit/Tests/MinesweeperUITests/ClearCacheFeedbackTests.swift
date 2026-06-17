// ClearCacheFeedbackTests — #284 user feedback for Minesweeper's Settings
// "Clear cache" action (mirrors Sudoku's `SettingsViewModel.clearCache`).
//
// Drives `LiveRouteFactory.clearCache(persistence:errorReporter:toastController:)`
// directly (MS has no Settings ViewModel — the action is a static func on the
// route factory) over a scripted `PersistenceProtocol` fake:
//   - success  → a success toast, no error-funnel call.
//   - delete throws → the error funnels through `ErrorReporter` AND a failure
//     toast is shown (MS does not claim "cleared" when the delete failed).
//
// Lives in its own file (NOT alongside `LiveRouteFactoryTests`) because the
// `PersistenceProtocol` fake must name `SudokuEngine.Mode` / `Difficulty` (the
// shared persistence wire format), and `import SudokuEngine` collides with
// `MinesweeperEngine.Difficulty` that `LiveRouteFactoryTests` imports. Keeping
// the SudokuEngine import isolated here sidesteps the ambiguity.

import Foundation
import Testing
@testable import MinesweeperAppComposition
import MonetizationUI
import Persistence
import Telemetry
import SudokuGameState
import SudokuEngine

@MainActor
@Suite struct ClearCacheFeedbackTests {

    @Test func clearCacheSuccessShowsSuccessToast() async {
        let toast = ToastController()
        let reporter = FakeErrorReporter()
        let persistence = Self.fake(deleteThrows: false)

        await LiveRouteFactory.clearCache(
            persistence: persistence,
            errorReporter: reporter,
            toastController: toast
        )

        #expect(toast.current?.style == .success)
        let received = await reporter.received
        #expect(received.isEmpty)
    }

    @Test func clearCacheErrorReportsAndShowsFailureToast() async {
        let toast = ToastController()
        let reporter = FakeErrorReporter()
        let persistence = Self.fake(deleteThrows: true)

        await LiveRouteFactory.clearCache(
            persistence: persistence,
            errorReporter: reporter,
            toastController: toast
        )

        #expect(toast.current?.style == .failure)
        let received = await reporter.received
        #expect(received.count == 1)
        #expect(received.first?.source == "LiveRouteFactory.clearCache")
    }

    private static func fake(deleteThrows: Bool) -> ClearCacheFakePersistence {
        let candidate = SavedGameSummary(
            recordName: "ms-saved",
            puzzleId: "2026-06-09-beginner",
            mode: .daily,
            difficulty: .easy,
            lastModifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            elapsedSeconds: 30,
            status: "inProgress",
            generatorVersion: 1
        )
        return ClearCacheFakePersistence(candidate: candidate, deleteThrows: deleteThrows)
    }
}

/// Minimal `PersistenceProtocol` fake: `latestInProgress()` returns a scripted
/// candidate (so the delete path runs — the shared
/// `PersistenceTesting.FakePersistence` returns nil, never exercising it) and
/// `deleteAbandoned(_:)` optionally throws to drive the error branch. Every
/// other method is an unused no-op / default.
private actor ClearCacheFakePersistence: PersistenceProtocol {
    struct DeleteFailed: Error {}

    private let candidate: SavedGameSummary
    private let deleteThrows: Bool

    init(candidate: SavedGameSummary, deleteThrows: Bool) {
        self.candidate = candidate
        self.deleteThrows = deleteThrows
    }

    func bootstrap() async throws {}

    func latestInProgress() async throws -> SavedGameSummary? { candidate }

    func loadOrCreate(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> GameSessionSnapshot {
        throw DeleteFailed()
    }

    func save(
        _ snapshot: GameSessionSnapshot,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws {}

    func markCompleted(_ summary: SavedGameSummary) async throws {}

    func deleteAbandoned(recordName: String) async throws {
        if deleteThrows { throw DeleteFailed() }
    }

    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> { [] }

    func fetchPersonalRecord(
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> PersonalRecord {
        PersonalRecord(
            recordName: "",
            mode: .daily,
            difficulty: .easy,
            bestTimeSeconds: nil,
            totalTimeSeconds: 0,
            completedCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 0),
            completedPuzzleIds: []
        )
    }

    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}
