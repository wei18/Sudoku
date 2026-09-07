// DailyHubViewModelRetryIfFailedTests — #1021 CR3b regression.
//
// Before this fix, a phase-1 daily-load failure was terminal for the whole
// app session: `refresh()` only ever re-runs phase 2 (the completion
// overlay) and is itself gated on `.loaded`, so nothing ever gave phase 1 a
// second chance. `retryIfFailed()` is the recovery entry point — covered
// here in isolation from `DailyHubView`'s wiring (that host-level proof
// lives in `DailyHubViewTabReturnRetryTests`).

import Foundation
import Testing
@testable import SudokuUI

import Persistence
import SudokuPersistence
import SudokuEngine
import SudokuKitTesting

@MainActor
@Suite("DailyHubViewModel — retryIfFailed (#1021 CR3b)")
struct DailyHubViewModelRetryIfFailedTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    private func makeViewModel(
        provider: FakePuzzleProvider,
        persistence: FakePersistence = FakePersistence()
    ) -> DailyHubViewModel {
        DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            dateProvider: { Self.fixedDate }
        )
    }

    /// The headline regression: a genuinely failed phase-1 load recovers to
    /// `.loaded` once the underlying fetch stops failing — pinning that
    /// `retryIfFailed()` re-runs the SAME phase-1 path `bootstrap()` uses,
    /// not just a phase-2 overlay re-fetch.
    @Test func retryAfterFailureRecoversToLoaded() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.failure(.malformedPuzzleId("uitest")))
        let viewModel = makeViewModel(provider: provider)

        await viewModel.bootstrap()
        guard case .failed = viewModel.state else {
            Issue.record("expected .failed, got \(viewModel.state)")
            return
        }

        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        await viewModel.retryIfFailed()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected .loaded after retry, got \(viewModel.state)")
            return
        }
        #expect(cards.count == 3)
    }

    /// A retry that fails again must land back in `.failed`, not get stuck
    /// in `.loading` or silently swallow the error.
    @Test func retryThatFailsAgainStaysFailed() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.failure(.malformedPuzzleId("uitest")))
        let viewModel = makeViewModel(provider: provider)

        await viewModel.bootstrap()
        await viewModel.retryIfFailed()

        guard case .failed = viewModel.state else {
            Issue.record("expected .failed to persist, got \(viewModel.state)")
            return
        }
        // Two calls total: bootstrap's own fetch + the one retry.
        #expect(await provider.operations.count == 2)
    }

    /// A no-op in `.loaded`: no second fetch, cards unchanged.
    @Test func retryIsNoOpWhenLoaded() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        let viewModel = makeViewModel(provider: provider)

        await viewModel.bootstrap()
        #expect(await provider.operations.count == 1)

        await viewModel.retryIfFailed()

        guard case .loaded = viewModel.state else {
            Issue.record("expected .loaded to persist, got \(viewModel.state)")
            return
        }
        #expect(await provider.operations.count == 1, "retryIfFailed must not re-fetch while already .loaded")
    }

    /// A no-op in `.exhausted` (the OTHER phase-1-error outcome) — recovery
    /// there is `tryPracticeInstead()` / `dismissExhausted()`, not a retry.
    @Test func retryIsNoOpWhenExhausted() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.failure(.generatorFailed(underlying: "uitest-forced-exhausted")))
        let viewModel = makeViewModel(provider: provider)

        await viewModel.bootstrap()
        guard case .exhausted = viewModel.state else {
            Issue.record("expected .exhausted, got \(viewModel.state)")
            return
        }

        await viewModel.retryIfFailed()

        guard case .exhausted = viewModel.state else {
            Issue.record("expected .exhausted to persist, got \(viewModel.state)")
            return
        }
        #expect(await provider.operations.count == 1, "retryIfFailed must not fetch at all while .exhausted")
    }

    /// A no-op in `.loading` — called before `bootstrap()`'s in-flight fetch
    /// has landed. Gates a retry signal firing while a plain (non-failed)
    /// fetch is already underway.
    @Test func retryIsNoOpWhileLoading() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        await provider.setArtificialDelay(nanos: 200_000_000)
        let viewModel = makeViewModel(provider: provider)

        let bootstrapTask = Task { await viewModel.bootstrap() }
        for _ in 0..<50 {
            await Task.yield()
            if case .loading = viewModel.state { break }
        }
        #expect(viewModel.state == .loading)

        // Snapshot the count rather than asserting a literal value — bootstrap's
        // OWN in-flight fetch may or may not have been recorded yet at this
        // exact instant (an actor-hop race unrelated to what this test pins);
        // what matters is that `retryIfFailed()` adds no fetch of its own.
        let operationsBeforeRetry = await provider.operations.count
        await viewModel.retryIfFailed()
        #expect(
            await provider.operations.count == operationsBeforeRetry,
            "retryIfFailed must not fetch while a plain load is in flight"
        )

        await bootstrapTask.value
    }

    /// Two overlapping retry signals (e.g. a double-fire of the tab-return
    /// `.onChange`) must not both kick off a phase-1 fetch — the second
    /// call observes `isRetrying` and no-ops instead of racing the first.
    @Test func concurrentRetriesDoNotDoubleFetch() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.failure(.malformedPuzzleId("uitest")))
        let viewModel = makeViewModel(provider: provider)

        await viewModel.bootstrap()
        guard case .failed = viewModel.state else {
            Issue.record("expected .failed, got \(viewModel.state)")
            return
        }

        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        await provider.setArtificialDelay(nanos: 50_000_000)

        async let first: Void = viewModel.retryIfFailed()
        async let second: Void = viewModel.retryIfFailed()
        _ = await (first, second)

        // One fetch for bootstrap's initial failure, exactly one more for
        // whichever retry call won the race — never two.
        #expect(await provider.operations.count == 2)
        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected .loaded once the winning retry lands, got \(viewModel.state)")
            return
        }
        #expect(cards.count == 3)
    }
}
