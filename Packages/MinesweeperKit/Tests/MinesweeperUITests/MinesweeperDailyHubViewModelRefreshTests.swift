// MinesweeperDailyHubViewModelRefreshTests — #761 hub-state-never-refreshes
// regression. Mirrors `DailyHubViewModelRefreshTests` (Sudoku).
//
// Split out to keep files under the 400-line SwiftLint ceiling. Covers
// `refresh()`: the phase-2-only re-fetch that bypasses the `hasBootstrapped`
// one-shot latch so a just-solved daily's card flips to completed on
// return-to-hub, without a full hub remount.

import Foundation
import Testing
@testable import MinesweeperUI
import SudokuGameState
import MinesweeperEngine
import Persistence
import SudokuEngine  // for Mode, GameSessionSnapshot, PersonalRecord used in PersistenceProtocol stubs

@MainActor
@Suite("MinesweeperDailyHubViewModel — refresh (#761)")
struct MinesweeperDailyHubViewModelRefreshTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    /// Sanity re-check: `refresh()` is additive — `bootstrap()`'s own
    /// idempotency latch must be unaffected.
    @Test func bootstrapIsStillIdempotentAfterAddingRefresh() async {
        let persistence = MutableMSPersistence()
        let viewModel = MinesweeperDailyHubViewModel(
            path: .constant([]),
            persistence: persistence,
            dateProvider: { Self.fixedDate }
        )

        await viewModel.bootstrap()
        await viewModel.bootstrap()

        let fetchCount = await persistence.fetchCount
        #expect(fetchCount == 1)
    }

    /// `refresh()` called before any `bootstrap()` has landed must be a
    /// complete no-op: no persistence traffic, state stays `.idle`. This is
    /// what makes it safe to fire `refresh()` from any external trigger — the
    /// production `.onChange(of: gameSessionTeardownCount)` included — no
    /// matter how it interleaves with `.task { bootstrap() }` around first mount.
    @Test func refreshBeforeBootstrapIsNoOp() async {
        let persistence = MutableMSPersistence()
        let viewModel = MinesweeperDailyHubViewModel(
            path: .constant([]),
            persistence: persistence,
            dateProvider: { Self.fixedDate }
        )

        await viewModel.refresh()

        #expect(viewModel.state == .idle)
        let fetchCount = await persistence.fetchCount
        #expect(fetchCount == 0)
    }

    /// The regression itself: after `bootstrap()` renders 3 un-completed
    /// cards, a puzzle gets completed (e.g. via a Completion overlay close
    /// popping back onto this same, un-destroyed hub instance) — simulated
    /// here by flipping the mutable fake persistence's completed set.
    /// `refresh()` must pick that up and flip the matching card, WITHOUT
    /// re-fetching the trio (today's boards never change).
    @Test func refreshAfterBootstrapPicksUpNewlyCompletedPuzzle() async {
        let date = Self.fixedDate
        let provider = LiveMinesweeperDailyProvider()
        let trio = provider.dailyTrio(date: date)
        let persistence = MutableMSPersistence()
        let viewModel = MinesweeperDailyHubViewModel(
            path: .constant([]),
            provider: provider,
            persistence: persistence,
            dateProvider: { date }
        )

        await viewModel.bootstrap()
        guard case .loaded(let initialCards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(initialCards.allSatisfy { !$0.isCompleted })
        let justSolved = trio[0]

        // Simulate the puzzle being completed between bootstrap and the hub
        // reappearing (e.g. the board/Completion flow persisting the win).
        await persistence.setCompleted([justSolved.puzzleId])

        await viewModel.refresh()

        guard case .loaded(let refreshedCards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        let refreshedCard = refreshedCards.first { $0.id == justSolved.puzzleId }
        #expect(refreshedCard?.isCompleted == true)
        #expect(refreshedCards.filter(\.isCompleted).count == 1)

        // Phase-2 (completed ids) must have re-run exactly twice (bootstrap +
        // refresh); the trio itself has no fetch counter to assert against
        // since `dailyTrio` is a pure synchronous call, not a service seam.
        let fetchCount = await persistence.fetchCount
        #expect(fetchCount == 2)
    }

    /// A `refresh()` with no completion changes must be a harmless re-fetch:
    /// state stays `.loaded` with the same (still un-completed) cards.
    @Test func refreshWithNoChangeLeavesCardsUncompleted() async {
        let date = Self.fixedDate
        let provider = LiveMinesweeperDailyProvider()
        let persistence = MutableMSPersistence()
        let viewModel = MinesweeperDailyHubViewModel(
            path: .constant([]),
            provider: provider,
            persistence: persistence,
            dateProvider: { date }
        )

        await viewModel.bootstrap()
        await viewModel.refresh()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(cards.count == 3)
        #expect(cards.allSatisfy { !$0.isCompleted })
    }
}

/// Persistence fake whose completed-ids set can be mutated AFTER
/// construction (unlike `ReturningMSPersistence`, which bakes it in at
/// `init`) — needed to simulate "completed between bootstrap and refresh".
/// Tracks a fetch count so tests can assert `refresh()` re-queries phase-2.
private actor MutableMSPersistence: PersistenceProtocol {

    private(set) var fetchCount = 0
    private var completed: Set<String> = []

    func setCompleted(_ ids: Set<String>) {
        self.completed = ids
    }

    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> {
        fetchCount += 1
        return completed
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
