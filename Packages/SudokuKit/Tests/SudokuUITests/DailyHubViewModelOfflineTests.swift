// DailyHubViewModelOfflineTests — #526 offline / iCloud-signed-out regression.
//
// Split out of DailyHubViewModelInteractionTests to keep each test file under
// the 400-line SwiftLint ceiling. Covers the two-phase render: the Daily Hub
// must reach `.loaded([3 cards])` even when the completion fetch hangs forever
// (iCloud signed out — CK never throws, never returns) or throws immediately.

import Foundation
import Testing
@testable import SudokuUI

import GameState
import Persistence
import PuzzleStore
import SudokuEngine
import SudokuKitTesting
import Telemetry

@MainActor
@Suite("DailyHubViewModel — offline / iCloud-signed-out (#526)")
struct DailyHubViewModelOfflineTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    /// Verifies the fix for #526: when `fetchCompletedDailyIds` hangs
    /// (e.g. iCloud signed out — CK never throws, never returns), the
    /// hub must still reach `.loaded([3 cards])` promptly rather than
    /// staying in `.loading` forever.
    ///
    /// Technique: run `bootstrap()` in a fire-and-forget `Task` (matching
    /// the `.onAppear { Task { await viewModel.bootstrap() } }` production
    /// pattern). Because our fix sets `state = .loaded(cards)` before calling
    /// `fillCompletionOverlay`, the state is observable via `Task.yield()`
    /// polling even while the fill is still suspended in the hanging
    /// persistence. After verifying state the test cancels the bootstrap task,
    /// which unblocks the continuation so the test finishes without leaking.
    @Test func bootstrapReachesLoadedEvenWhenCompletedIdsFetchHangsForever() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        let hangingPersistence = HangingPersistence()
        let viewModel = DailyHubViewModel(
            provider: provider,
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
    }

    /// Same as above but with a persistence that throws `iCloudNotSignedIn`
    /// immediately — verifies the fast-fail error-path degrade also works.
    @Test func bootstrapReachesLoadedWhenCompletedIdsFetchThrowsICloudNotSignedIn() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        let persistence = ThrowingCompletionPersistence(error: PersistenceError.iCloudNotSignedIn)
        let viewModel = DailyHubViewModel(
            provider: provider,
            persistence: persistence,
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
}

/// Persistence fake whose `fetchCompletedDailyIds` suspends indefinitely —
/// simulates a signed-out iCloud session where CloudKit never throws and
/// never returns (the documented #526 root cause). Uses `Task.sleep` for a
/// very long duration: the enclosing `Task` cancellation in the test unblocks
/// it via structured concurrency (CancellationError propagates), which lets
/// the test drain cleanly. Avoids the Swift 6 `@Sendable`-capture issue that
/// arises when storing a `CheckedContinuation` directly on an actor.
private actor HangingPersistence: PersistenceProtocol {

    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> {
        // Suspend for an hour — the test cancels the bootstrap Task long
        // before this expires, so CancellationError unblocks the test.
        try await Task.sleep(for: .seconds(3_600))
        return []
    }

    // MARK: - Minimal PersistenceProtocol forwarding

    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(puzzleId: String, mode: Mode, difficulty: Difficulty) async throws -> GameSessionSnapshot {
        throw PersistenceError.zoneNotProvisioned
    }
    func save(_ snapshot: GameSessionSnapshot, puzzleId: String, mode: Mode, difficulty: Difficulty) async throws {}
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func fetchPersonalRecord(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        PersonalRecord(
            recordName: "", mode: .daily, difficulty: .easy,
            bestTimeSeconds: nil, totalTimeSeconds: 0, completedCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 0), completedPuzzleIds: []
        )
    }
    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}

/// Persistence fake whose `fetchCompletedDailyIds` throws immediately with a
/// given error — covers the fast-fail degrade path (e.g. `iCloudNotSignedIn`).
private actor ThrowingCompletionPersistence: PersistenceProtocol {

    private let error: any Error

    init(error: any Error) {
        self.error = error
    }

    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> {
        throw error
    }

    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(puzzleId: String, mode: Mode, difficulty: Difficulty) async throws -> GameSessionSnapshot {
        throw PersistenceError.zoneNotProvisioned
    }
    func save(_ snapshot: GameSessionSnapshot, puzzleId: String, mode: Mode, difficulty: Difficulty) async throws {}
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func fetchPersonalRecord(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        PersonalRecord(
            recordName: "", mode: .daily, difficulty: .easy,
            bestTimeSeconds: nil, totalTimeSeconds: 0, completedCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 0), completedPuzzleIds: []
        )
    }
    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}
