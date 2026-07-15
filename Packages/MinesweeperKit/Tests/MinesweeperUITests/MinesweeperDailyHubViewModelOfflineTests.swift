// MinesweeperDailyHubViewModelOfflineTests — #530 offline / iCloud-signed-out
// regression.
//
// Split out of MinesweeperDailyHubViewTests to keep each file under the
// 400-line SwiftLint ceiling. Covers the two-phase render: the MS Daily Hub
// must reach `.loaded([3 cards])` even when the completed-ids fetch hangs
// forever (iCloud signed out — CK never throws, never returns) or throws
// immediately. Mirrors `DailyHubViewModelOfflineTests` (#526 Sudoku).
//
// #816: the completed-ids fetch moved from `PersistenceProtocol` to
// `MinesweeperSavedGameStore` (a concrete actor, no protocol seam) — so the
// hang/throw fakes below no longer implement `PersistenceProtocol`. Instead
// they implement the underlying `PrivateCKGateway` seam that
// `MinesweeperSavedGameStore` is built over (same technique
// `MinesweeperSavedGameStoreTests.ThrowingQueryGateway` uses) and get
// wrapped in a real `MinesweeperSavedGameStore` passed as `savedGameStore:`.

import Foundation
import Testing
import MinesweeperEngine
import MinesweeperGameState
import MinesweeperPersistence
import Persistence
import PersistenceTesting
@testable import MinesweeperUI

@MainActor
@Suite("MinesweeperDailyHubViewModel — offline / iCloud-signed-out (#530)")
struct MinesweeperDailyHubViewModelOfflineTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    /// Verifies the fix for #530: when the completed/failed-ids fetch hangs
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
        let hangingStore = MinesweeperSavedGameStore(
            gateway: HangingQueryGateway(),
            clock: { Self.fixedDate }
        )
        let viewModel = MinesweeperDailyHubViewModel(
            path: .constant([]),
            savedGameStore: hangingStore,
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

    /// Fast-fail path: when the saved-game store throws `iCloudNotSignedIn`
    /// immediately, bootstrap still reaches `.loaded` with 3 un-completed cards.
    @Test func bootstrapReachesLoadedWhenCompletedIdsFetchThrowsImmediately() async {
        let throwingStore = MinesweeperSavedGameStore(
            gateway: ThrowingQueryGateway(error: PersistenceError.iCloudNotSignedIn),
            clock: { Self.fixedDate }
        )
        let viewModel = MinesweeperDailyHubViewModel(
            path: .constant([]),
            savedGameStore: throwingStore,
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

    /// Happy-path regression: when the saved-game store works, completion
    /// overlays still render after Phase 2 fills in — guards that the
    /// two-phase fix didn't break the normal completion-marking flow.
    @Test func bootstrapMarksCompletedCardsWhenSavedGameStoreReturnsIds() async {
        let date = Self.fixedDate
        let provider = LiveMinesweeperDailyProvider()
        let trio = provider.dailyTrio(date: date)
        let completedId = trio[0].puzzleId
        let gateway = FakePrivateCKGateway()
        await gateway.seed(
            RecordPayload(
                recordType: PrivateCKConstants.savedGameRecordType,
                recordName: completedId,
                fields: [
                    "difficulty": .string("beginner"),
                    "seed": .int(0),
                    "mode": .string("daily"),
                    "elapsedSeconds": .int(30),
                    "status": .string("completed"),
                    "lastModifiedAt": .date(date),
                    "schemaVersion": .int(1),
                    "stateBlob": .data(Data()),
                ]
            )
        )
        let store = MinesweeperSavedGameStore(gateway: gateway, clock: { date })
        let viewModel = MinesweeperDailyHubViewModel(
            path: .constant([]),
            provider: provider,
            savedGameStore: store,
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
// Minimal `PrivateCKGateway` conformers wrapped in a real
// `MinesweeperSavedGameStore` — the store is a concrete actor (no protocol
// seam of its own), so injection happens one layer down, at the gateway it
// is built over. Mirrors `MinesweeperSavedGameStoreTests.ThrowingQueryGateway`.

/// Gateway fake whose `query` suspends indefinitely — simulates a
/// signed-out iCloud session where CloudKit never throws and never returns.
/// Uses `Task.sleep` for a very long duration; the enclosing `Task`
/// cancellation in the test unblocks it via structured concurrency.
private actor HangingQueryGateway: PrivateCKGateway {
    func provisionZone() async throws {}
    func installSubscriptionIfNeeded() async throws {}
    func fetch(recordName: String) async throws -> RecordPayload? { nil }
    func save(_ payload: RecordPayload, policy: RecordSavePolicy) async throws {}
    func delete(recordName: String) async throws {}

    func query(_ predicate: RecordPredicate) async throws -> [RecordPayload] {
        try await Task.sleep(for: .seconds(3_600))
        return []
    }
}

/// Gateway fake whose `query` throws immediately.
private actor ThrowingQueryGateway: PrivateCKGateway {
    private let error: any Error & Sendable

    init(error: any Error & Sendable) { self.error = error }

    func provisionZone() async throws {}
    func installSubscriptionIfNeeded() async throws {}
    func fetch(recordName: String) async throws -> RecordPayload? { nil }
    func save(_ payload: RecordPayload, policy: RecordSavePolicy) async throws {}
    func delete(recordName: String) async throws {}

    func query(_ predicate: RecordPredicate) async throws -> [RecordPayload] {
        throw error
    }
}
