// DailyHubViewModelRefreshTests — #761 hub-state-never-refreshes regression.
//
// Split out of DailyHubViewModelInteractionTests to keep each file under the
// 400-line SwiftLint ceiling. Covers `refresh()`: the phase-2-only re-fetch
// that bypasses the `hasBootstrapped` one-shot latch so a just-solved daily's
// card flips to completed on return-to-hub, without a full hub remount.

import Foundation
import Testing
@testable import SudokuUI

import Persistence
import SudokuPersistence
import SudokuEngine
import SudokuKitTesting

@MainActor
@Suite("DailyHubViewModel — refresh (#761)")
struct DailyHubViewModelRefreshTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    private func makeViewModel(
        provider: FakePuzzleProvider,
        persistence: FakePersistence
    ) -> DailyHubViewModel {
        DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            dateProvider: { Self.fixedDate }
        )
    }

    /// Sanity re-check: `refresh()` is additive — `bootstrap()`'s own
    /// idempotency latch must be unaffected.
    @Test func bootstrapIsStillIdempotentAfterAddingRefresh() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        let viewModel = makeViewModel(provider: provider, persistence: persistence)

        await viewModel.bootstrap()
        await viewModel.bootstrap()

        let providerOps = await provider.operations
        #expect(providerOps.count == 1)
    }

    /// `refresh()` called before any `bootstrap()` has landed must be a
    /// complete no-op: no persistence traffic, state stays `.idle`. This is
    /// what makes it safe to fire `refresh()` from any external trigger — the
    /// production `.onChange(of: gameSessionTeardownCount)` included — no
    /// matter how it interleaves with `.task { bootstrap() }` around first mount.
    @Test func refreshBeforeBootstrapIsNoOp() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        let viewModel = makeViewModel(provider: provider, persistence: persistence)

        await viewModel.refresh()

        #expect(viewModel.state == .idle)
        let providerOps = await provider.operations
        let persistenceOps = await persistence.operations
        #expect(providerOps.isEmpty)
        #expect(persistenceOps.isEmpty)
    }

    /// The regression itself: after `bootstrap()` renders 3 un-completed
    /// cards, a puzzle gets completed (e.g. via a Completion overlay close
    /// popping back onto this same, un-destroyed hub instance) — simulated
    /// here by flipping the fake persistence's completed set. `refresh()`
    /// must pick that up and flip the matching card, WITHOUT re-fetching the
    /// trio (today's puzzles never change).
    @Test func refreshAfterBootstrapPicksUpNewlyCompletedPuzzle() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        let persistence = FakePersistence()
        let viewModel = makeViewModel(provider: provider, persistence: persistence)

        await viewModel.bootstrap()
        guard case .loaded(let initialCards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(initialCards.allSatisfy { !$0.isCompleted })
        let justSolved = initialCards[1]

        // Simulate the puzzle being completed between bootstrap and the hub
        // reappearing (e.g. the board/Completion flow persisting the win).
        await persistence.setCompletedDailyIds([justSolved.envelope.identity.puzzleId])

        await viewModel.refresh()

        guard case .loaded(let refreshedCards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        let refreshedCard = refreshedCards.first { $0.id == justSolved.id }
        #expect(refreshedCard?.isCompleted == true)
        #expect(refreshedCards.filter(\.isCompleted).count == 1)

        // Phase-1 (the trio) must not be re-fetched by refresh() — only
        // phase-2 (completed ids) re-runs.
        let providerOps = await provider.operations
        #expect(providerOps.count == 1)
        // #774: each run fetches the 7-day week-strip window (not a single
        // "today" call) — bootstrap + refresh = 7 + 7 = 14.
        let persistenceOps = await persistence.operations
        #expect(persistenceOps.filter { if case .fetchCompletedDailyIds = $0 { true } else { false } }.count == 14)
    }

    /// A `refresh()` with no completion changes must be a harmless re-fetch:
    /// state stays `.loaded` with the same (still un-completed) cards.
    @Test func refreshWithNoChangeLeavesCardsUncompleted() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        let persistence = FakePersistence()
        let viewModel = makeViewModel(provider: provider, persistence: persistence)

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
