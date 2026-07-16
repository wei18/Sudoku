// MinesweeperDailyHubViewModelRefreshTests — #761 hub-state-never-refreshes
// regression. Mirrors `DailyHubViewModelRefreshTests` (Sudoku).
//
// Split out to keep files under the 400-line SwiftLint ceiling. Covers
// `refresh()`: the phase-2-only re-fetch that bypasses the `hasBootstrapped`
// one-shot latch so a just-solved daily's card flips to completed on
// return-to-hub, without a full hub remount.
//
// #816: the completed-ids half of phase-2 moved from `PersistenceProtocol`
// to `MinesweeperSavedGameStore` (the generic Sudoku-shaped completed-ids
// query assumes a `puzzleId` field MS's schema doesn't have). These tests
// now seed completed/failed daily records on a `FakePrivateCKGateway`-backed
// `MinesweeperSavedGameStore` instead of a `PersistenceProtocol` fake, and
// count phase-2 fetches via the gateway's recorded `.query` operations.

import Foundation
import Testing
import MinesweeperEngine
import MinesweeperGameState
import MinesweeperPersistence
import Persistence
import PersistenceTesting
@testable import MinesweeperUI

@MainActor
@Suite("MinesweeperDailyHubViewModel — refresh (#761)")
struct MinesweeperDailyHubViewModelRefreshTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    private func dailyRecordPayload(
        recordName: String,
        status: String,
        mode: String = "daily",
        difficulty: String = "beginner"
    ) -> RecordPayload {
        RecordPayload(
            recordType: PrivateCKConstants.savedGameRecordType,
            recordName: recordName,
            fields: [
                "difficulty": .string(difficulty),
                "seed": .int(0),
                "mode": .string(mode),
                "elapsedSeconds": .int(30),
                "status": .string(status),
                "lastModifiedAt": .date(Self.fixedDate),
                "schemaVersion": .int(1),
                "stateBlob": .data(Data()),
            ]
        )
    }

    private func queryOpCount(_ gateway: FakePrivateCKGateway) async -> Int {
        await gateway.operations.filter { $0 == .query }.count
    }

    /// Sanity re-check: `refresh()` is additive — `bootstrap()`'s own
    /// idempotency latch must be unaffected.
    @Test func bootstrapIsStillIdempotentAfterAddingRefresh() async {
        let gateway = FakePrivateCKGateway()
        let store = MinesweeperSavedGameStore(gateway: gateway, clock: { Self.fixedDate })
        let viewModel = MinesweeperDailyHubViewModel(
            path: .constant([]),
            savedGameStore: store,
            dateProvider: { Self.fixedDate }
        )

        await viewModel.bootstrap()
        await viewModel.bootstrap()

        // One phase-2 run == 8 queries (7 week-strip window days (#774)
        // + 1 failed); a second `bootstrap()` call must be a no-op
        // (`hasBootstrapped` latch).
        #expect(await queryOpCount(gateway) == 8)
    }

    /// `refresh()` called before any `bootstrap()` has landed must be a
    /// complete no-op: no CK traffic, state stays `.idle`. This is
    /// what makes it safe to fire `refresh()` from any external trigger — the
    /// production `.onChange(of: gameSessionTeardownCount)` included — no
    /// matter how it interleaves with `.task { bootstrap() }` around first mount.
    @Test func refreshBeforeBootstrapIsNoOp() async {
        let gateway = FakePrivateCKGateway()
        let store = MinesweeperSavedGameStore(gateway: gateway, clock: { Self.fixedDate })
        let viewModel = MinesweeperDailyHubViewModel(
            path: .constant([]),
            savedGameStore: store,
            dateProvider: { Self.fixedDate }
        )

        await viewModel.refresh()

        #expect(viewModel.state == .idle)
        #expect(await queryOpCount(gateway) == 0)
    }

    /// The regression itself: after `bootstrap()` renders 3 un-completed
    /// cards, a puzzle gets completed (e.g. via a Completion overlay close
    /// popping back onto this same, un-destroyed hub instance) — simulated
    /// here by seeding a completed record on the gateway between bootstrap
    /// and refresh. `refresh()` must pick that up and flip the matching
    /// card, WITHOUT re-fetching the trio (today's boards never change).
    @Test func refreshAfterBootstrapPicksUpNewlyCompletedPuzzle() async {
        let date = Self.fixedDate
        let provider = LiveMinesweeperDailyProvider()
        let trio = provider.dailyTrio(date: date)
        let gateway = FakePrivateCKGateway()
        let store = MinesweeperSavedGameStore(gateway: gateway, clock: { date })
        let viewModel = MinesweeperDailyHubViewModel(
            path: .constant([]),
            provider: provider,
            savedGameStore: store,
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
        await gateway.seed(dailyRecordPayload(recordName: justSolved.puzzleId, status: "completed"))

        await viewModel.refresh()

        guard case .loaded(let refreshedCards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        let refreshedCard = refreshedCards.first { $0.id == justSolved.puzzleId }
        #expect(refreshedCard?.isCompleted == true)
        #expect(refreshedCards.filter(\.isCompleted).count == 1)

        // Phase-2 (7-day week-strip window + failed ids, #774) must have
        // re-run exactly twice (bootstrap + refresh) — 8 queries per run
        // == 16 total; the trio itself has no fetch counter to assert
        // against since `dailyTrio` is a pure synchronous call, not a
        // service seam.
        #expect(await queryOpCount(gateway) == 16)
    }

    /// A `refresh()` with no completion changes must be a harmless re-fetch:
    /// state stays `.loaded` with the same (still un-completed) cards.
    @Test func refreshWithNoChangeLeavesCardsUncompleted() async {
        let date = Self.fixedDate
        let provider = LiveMinesweeperDailyProvider()
        let gateway = FakePrivateCKGateway()
        let store = MinesweeperSavedGameStore(gateway: gateway, clock: { date })
        let viewModel = MinesweeperDailyHubViewModel(
            path: .constant([]),
            provider: provider,
            savedGameStore: store,
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

    /// #816 pin: a single `bootstrap()` must mark BOTH a completed AND a
    /// failed card from `savedGameStore`-sourced ids — the repointed read
    /// path (completed moved off `PersistenceProtocol`) and the
    /// already-working failed path both feed `mergeCards`.
    @Test func bootstrapMarksBothCompletedAndFailedCardsFromSavedGameStore() async {
        let date = Self.fixedDate
        let provider = LiveMinesweeperDailyProvider()
        let trio = provider.dailyTrio(date: date)
        let gateway = FakePrivateCKGateway()
        await gateway.seed(dailyRecordPayload(recordName: trio[0].puzzleId, status: "completed"))
        await gateway.seed(dailyRecordPayload(recordName: trio[1].puzzleId, status: "failed"))
        let store = MinesweeperSavedGameStore(gateway: gateway, clock: { date })
        let viewModel = MinesweeperDailyHubViewModel(
            path: .constant([]),
            provider: provider,
            savedGameStore: store,
            dateProvider: { date }
        )

        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        let completedCard = cards.first { $0.id == trio[0].puzzleId }
        let failedCard = cards.first { $0.id == trio[1].puzzleId }
        let untouchedCard = cards.first { $0.id == trio[2].puzzleId }
        #expect(completedCard?.isCompleted == true)
        #expect(failedCard?.isFailed == true)
        #expect(untouchedCard?.isCompleted == false)
        #expect(untouchedCard?.isFailed == false)
    }
}
