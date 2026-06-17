// MinesweeperDailyHubViewModelOfflineTests — #530 offline / iCloud-signed-out
// regression.
//
// Split out of MinesweeperDailyHubViewTests to keep each file under the
// 400-line SwiftLint ceiling. Covers the two-phase render: the MS Daily Hub
// must reach `.loaded([3 cards])` even when the completed-ids fetch hangs
// forever (iCloud signed out — CK never throws, never returns) or throws
// immediately. Mirrors `DailyHubViewModelOfflineTests` (#526 Sudoku).
//
// Note: `savedGameStore` is typed as the concrete `MinesweeperSavedGameStore`
// actor (no protocol seam), so the hang-under-failed-ids path cannot be
// injected here. The two-phase guarantee is fully proven by the
// completed-ids hang test below: Phase 1 fires before Phase 2 regardless
// of which Phase-2 fetch hangs.

import Foundation
import Testing
@testable import MinesweeperUI
import SudokuGameState
import MinesweeperEngine
import Persistence
import PersistenceTesting
import SudokuEngine  // for Mode, GameSessionSnapshot, PersonalRecord used in PersistenceProtocol stubs

@MainActor
@Suite("MinesweeperDailyHubViewModel — offline / iCloud-signed-out (#530)")
struct MinesweeperDailyHubViewModelOfflineTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    /// Verifies the fix for #530: when `fetchCompletedDailyIds` hangs
    /// (e.g. iCloud signed out — CK never throws, never returns), the
    /// hub must still reach `.loaded([3 cards])` promptly rather than
    /// staying in `.loading` forever.
    ///
    /// Technique: run `bootstrap()` in a fire-and-forget `Task` (matching
    /// the `.onAppear { Task { await viewModel.bootstrap() } }` production
    /// pattern). Because the fix sets `state = .loaded(cards)` before calling
    /// `fillCompletionAndFailureOverlay`, the state is observable via
    /// `Task.yield()` polling even while the fill is still suspended.
    /// After verifying state the test cancels the bootstrap task, which
    /// unblocks the continuation so the test finishes without leaking.
    @Test func bootstrapReachesLoadedEvenWhenCompletedIdsFetchHangsForever() async {
        let hangingPersistence = HangingMSPersistence()
        let viewModel = MinesweeperDailyHubViewModel(
            path: .constant([]),
            persistence: hangingPersistence,
            dateProvider: { Self.fixedDate }
        )

        // Fire-and-forget, exactly as `.onAppear { Task { await ... } }` does.
        let bootstrapTask = Task { @MainActor in
            await viewModel.bootstrap()
        }

        // Yield cooperatively until `.loaded` or the budget runs out.
        for _ in 0..<1_000 {
            if case .loaded = viewModel.state { break }
            await Task.yield()
        }

        // Cancel so the hanging continuation resumes and the test can exit.
        bootstrapTask.cancel()
        _ = await bootstrapTask.result  // drain

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected .loaded after trio resolved, got \(viewModel.state)")
            return
        }
        #expect(cards.count == 3)
        // All cards must be un-completed (graceful-degrade: completion unknown
        // while CK hangs, not a fatal error or a blocking spinner).
        #expect(cards.allSatisfy { !$0.isCompleted })
        #expect(cards.allSatisfy { !$0.isFailed })
    }

    /// Fast-fail path: when persistence throws `iCloudNotSignedIn` immediately,
    /// bootstrap still reaches `.loaded` with 3 un-completed cards.
    @Test func bootstrapReachesLoadedWhenCompletedIdsFetchThrowsImmediately() async {
        let throwingPersistence = ThrowingMSPersistence(error: PersistenceError.iCloudNotSignedIn)
        let viewModel = MinesweeperDailyHubViewModel(
            path: .constant([]),
            persistence: throwingPersistence,
            dateProvider: { Self.fixedDate }
        )

        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(cards.count == 3)
        #expect(cards.allSatisfy { !$0.isCompleted })
    }

    /// Happy-path regression: when persistence works, completion overlays still
    /// render after Phase 2 fills in — guards that the two-phase fix didn't
    /// break the normal completion-marking flow.
    @Test func bootstrapMarksCompletedCardsWhenPersistenceReturnsIds() async {
        let date = Self.fixedDate
        let provider = LiveMinesweeperDailyProvider()
        let trio = provider.dailyTrio(date: date)
        let completedId = trio[0].puzzleId
        let returningPersistence = ReturningMSPersistence(completed: [completedId])
        let viewModel = MinesweeperDailyHubViewModel(
            path: .constant([]),
            provider: provider,
            persistence: returningPersistence,
            dateProvider: { date }
        )

        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(cards.count == 3)
        #expect(cards.filter(\.isCompleted).count == 1)
        #expect(cards.first?.isCompleted == true)
    }
}

// MARK: - Fakes
//
// Each fake is a minimal `PersistenceProtocol` conformer. The boilerplate
// stubs below match the shape of `PersistenceTesting.FakePersistence` (actors
// cannot inherit, so we repeat the safe defaults rather than subclassing).

/// Persistence fake whose `fetchCompletedDailyIds` suspends indefinitely —
/// simulates a signed-out iCloud session where CloudKit never throws and
/// never returns. Uses `Task.sleep` for a very long duration; the enclosing
/// `Task` cancellation in the test unblocks it via structured concurrency.
private actor HangingMSPersistence: PersistenceProtocol {

    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> {
        try await Task.sleep(for: .seconds(3_600))
        return []
    }

    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(puzzleId: String, mode: Mode, difficulty: SudokuEngine.Difficulty) async throws -> GameSessionSnapshot {
        throw PersistenceError.zoneNotProvisioned
    }
    func save(_ snapshot: GameSessionSnapshot, puzzleId: String, mode: Mode, difficulty: SudokuEngine.Difficulty) async throws {}
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func fetchPersonalRecord(mode: Mode, difficulty: SudokuEngine.Difficulty) async throws -> PersonalRecord {
        PersonalRecord(recordName: "", mode: .daily, difficulty: .easy, bestTimeSeconds: nil,
                       totalTimeSeconds: 0, completedCount: 0,
                       lastUpdatedAt: Date(timeIntervalSince1970: 0), completedPuzzleIds: [])
    }
    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}

/// Persistence fake whose `fetchCompletedDailyIds` throws immediately.
private actor ThrowingMSPersistence: PersistenceProtocol {

    private let error: any Error

    init(error: any Error) { self.error = error }

    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> { throw error }

    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(puzzleId: String, mode: Mode, difficulty: SudokuEngine.Difficulty) async throws -> GameSessionSnapshot {
        throw PersistenceError.zoneNotProvisioned
    }
    func save(_ snapshot: GameSessionSnapshot, puzzleId: String, mode: Mode, difficulty: SudokuEngine.Difficulty) async throws {}
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func fetchPersonalRecord(mode: Mode, difficulty: SudokuEngine.Difficulty) async throws -> PersonalRecord {
        PersonalRecord(recordName: "", mode: .daily, difficulty: .easy, bestTimeSeconds: nil,
                       totalTimeSeconds: 0, completedCount: 0,
                       lastUpdatedAt: Date(timeIntervalSince1970: 0), completedPuzzleIds: [])
    }
    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}

/// Persistence fake that returns a fixed set of completed daily ids.
private actor ReturningMSPersistence: PersistenceProtocol {

    private let completed: Set<String>

    init(completed: Set<String>) { self.completed = completed }

    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> { completed }

    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(puzzleId: String, mode: Mode, difficulty: SudokuEngine.Difficulty) async throws -> GameSessionSnapshot {
        throw PersistenceError.zoneNotProvisioned
    }
    func save(_ snapshot: GameSessionSnapshot, puzzleId: String, mode: Mode, difficulty: SudokuEngine.Difficulty) async throws {}
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func fetchPersonalRecord(mode: Mode, difficulty: SudokuEngine.Difficulty) async throws -> PersonalRecord {
        PersonalRecord(recordName: "", mode: .daily, difficulty: .easy, bestTimeSeconds: nil,
                       totalTimeSeconds: 0, completedCount: 0,
                       lastUpdatedAt: Date(timeIntervalSince1970: 0), completedPuzzleIds: [])
    }
    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}
