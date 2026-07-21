// DailyHubViewModelInteractionTests — bootstrap fetch + card-tap navigation,
// asserting service call shape and navigation through an injected binding
// (issue #171).
//
// `DailyHubViewTests.cardTapAppendsBoardRoute` covers the local-stub branch.
// This suite adds (1) the external-`Binding` navigation branch and (2)
// behavioral service-call assertions via the fakes' recorded `operations`, so a
// regression that stopped calling the provider/persistence on bootstrap — or
// stopped pushing through the injected path on tap — would fail here.

import Foundation
import Testing
@testable import SudokuUI

import SudokuGameState
import Persistence
import SudokuPersistence
import SudokuEngine
import SudokuKitTesting
import Telemetry

@MainActor
@Suite("DailyHubViewModel — interaction (services + injected path)")
struct DailyHubViewModelInteractionTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    private func makeViewModel(
        provider: FakePuzzleProvider,
        persistence: FakePersistence,
        box: RoutePathBox
    ) -> DailyHubViewModel {
        DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            dateProvider: { Self.fixedDate },
            path: box.binding
        )
    }

    @Test func bootstrapCallsProviderAndPersistenceExactlyOnce() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        let persistence = FakePersistence()
        let viewModel = makeViewModel(provider: provider, persistence: persistence, box: RoutePathBox())

        await viewModel.bootstrap()

        let providerOps = await provider.operations
        let persistenceOps = await persistence.operations
        #expect(providerOps == [.fetchDailyTrio(date: Self.fixedDate)])
        // #921: 1 call (`fetchCompletedDailyIdsByDay`, the whole 7-day
        // week-strip window in a single query) — not 7 per-day calls (#774).
        // #886: runs concurrently with 3 `fetchPersonalRecord` calls
        // (`async let`), so relative order ACROSS the two kinds isn't
        // guaranteed — assert each kind's own sub-sequence + total count
        // instead of one flat array.
        let completedIdsOps = persistenceOps.filter { if case .fetchCompletedDailyIdsByDay = $0 { true } else { false } }
        let personalRecordOps = persistenceOps.filter { if case .fetchPersonalRecord = $0 { true } else { false } }
        #expect(completedIdsOps == [.fetchCompletedDailyIdsByDay])
        #expect(Set(personalRecordOps) == Set([
            FakePersistence.Operation.fetchPersonalRecord(mode: .daily, difficulty: .easy),
            .fetchPersonalRecord(mode: .daily, difficulty: .medium),
            .fetchPersonalRecord(mode: .daily, difficulty: .hard)
        ]))
        #expect(persistenceOps.count == completedIdsOps.count + personalRecordOps.count)
    }

    @Test func bootstrapIsIdempotent() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        let viewModel = makeViewModel(provider: provider, persistence: persistence, box: RoutePathBox())

        await viewModel.bootstrap()
        await viewModel.bootstrap()

        let providerOps = await provider.operations
        // The `hasBootstrapped` latch must keep the second call from re-fetching.
        #expect(providerOps.count == 1)
    }

    @Test func cardTapPushesBoardRouteThroughInjectedBinding() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        let box = RoutePathBox()
        let viewModel = makeViewModel(provider: provider, persistence: persistence, box: box)
        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        let tapped = cards[1]

        viewModel.cardTapped(tapped)

        #expect(box.routes == [.board(puzzleId: tapped.envelope.identity.puzzleId)])
    }

    // MARK: - #379: completed card routes to Completion

    /// Builds a completed-status snapshot whose `elapsedSeconds` is the
    /// frozen solve time we expect to surface on the Completion route.
    private func completedSnapshot(elapsedSeconds: Int) -> GameSessionSnapshot {
        let puzzle = FakePuzzleProvider.defaultPuzzle(difficulty: .easy, seed: 1)
        return GameSessionSnapshot(
            puzzle: puzzle,
            currentBoard: puzzle.solution,
            status: .completed,
            elapsedSeconds: elapsedSeconds,
            undoMoves: [],
            redoMoves: [],
            notes: NotesGrid()
        )
    }

    @Test func tappingCompletedCardRoutesToCompletionWithSavedTime() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        await persistence.setLoadOrCreateSnapshot(completedSnapshot(elapsedSeconds: 742))
        let box = RoutePathBox()
        let viewModel = makeViewModel(provider: provider, persistence: persistence, box: box)
        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        // Mark the tapped card completed (bootstrap fixture leaves all un-completed).
        let base = cards[1]
        let completedCard = DailyCard(envelope: base.envelope, isCompleted: true)

        await viewModel.openCompleted(
            puzzleId: completedCard.envelope.identity.puzzleId,
            difficulty: completedCard.difficulty
        )

        #expect(box.routes == [
            .completion(puzzleId: base.envelope.identity.puzzleId, elapsedSeconds: 742, mistakeCount: 0)
        ])
    }

    // MARK: - #385: cardTapped (sync entry) routes + double-tap latch

    /// Drains the MainActor queue until `box.routes` reaches `count` or the
    /// bounded yield budget is exhausted. `cardTapped`'s completed branch
    /// spawns a detached `Task { await openCompleted(_:) }`; the fake's
    /// `loadOrCreate` resolves without real I/O, so a bounded `Task.yield()`
    /// poll lets that Task run to completion deterministically — no real time
    /// elapses and no sleep is needed.
    private func waitForRouteCount(_ box: RoutePathBox, atLeast count: Int) async {
        for _ in 0..<1_000 {
            if box.routes.count >= count { return }
            await Task.yield()
        }
    }

    @Test func tappingCompletedCardViaCardTappedRoutesToCompletionWithSavedTime() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        await persistence.setLoadOrCreateSnapshot(completedSnapshot(elapsedSeconds: 742))
        let box = RoutePathBox()
        let viewModel = makeViewModel(provider: provider, persistence: persistence, box: box)
        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        let base = cards[1]
        let completedCard = DailyCard(envelope: base.envelope, isCompleted: true)

        // Drive the *sync* entry point (#384's previously-untested branch).
        viewModel.cardTapped(completedCard)
        await waitForRouteCount(box, atLeast: 1)

        #expect(box.routes == [
            .completion(puzzleId: base.envelope.identity.puzzleId, elapsedSeconds: 742, mistakeCount: 0)
        ])
    }

    @Test func rapidDoubleTapOnCompletedCardRoutesToCompletionExactlyOnce() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        await persistence.setLoadOrCreateSnapshot(completedSnapshot(elapsedSeconds: 742))
        let box = RoutePathBox()
        let viewModel = makeViewModel(provider: provider, persistence: persistence, box: box)
        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        let base = cards[1]
        let completedCard = DailyCard(envelope: base.envelope, isCompleted: true)

        // Two synchronous taps back-to-back: the second must hit the in-flight
        // latch before the first Task's `await` resolves. Both run on the
        // MainActor with no suspension between them, so the latch set in the
        // first `cardTapped` short-circuits the second.
        viewModel.cardTapped(completedCard)
        viewModel.cardTapped(completedCard)
        await waitForRouteCount(box, atLeast: 1)
        // Give any erroneously-spawned second Task a chance to push.
        await Task.yield()
        await Task.yield()

        #expect(box.routes == [
            .completion(puzzleId: base.envelope.identity.puzzleId, elapsedSeconds: 742, mistakeCount: 0)
        ])
    }

    @Test func latchResetsSoLaterTapRoutesAgain() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        await persistence.setLoadOrCreateSnapshot(completedSnapshot(elapsedSeconds: 742))
        let box = RoutePathBox()
        let viewModel = makeViewModel(provider: provider, persistence: persistence, box: box)
        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        let base = cards[1]
        let completedCard = DailyCard(envelope: base.envelope, isCompleted: true)

        viewModel.cardTapped(completedCard)
        await waitForRouteCount(box, atLeast: 1)

        // After the first open resolves the latch must clear so a re-tap
        // (e.g. returning to the hub and tapping again) works.
        viewModel.cardTapped(completedCard)
        await waitForRouteCount(box, atLeast: 2)

        let expected: AppRoute = .completion(
            puzzleId: base.envelope.identity.puzzleId, elapsedSeconds: 742, mistakeCount: 0
        )
        #expect(box.routes == [expected, expected])
    }

    @Test func tappingUncompletedCardStillRoutesToBoard() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        let box = RoutePathBox()
        let viewModel = makeViewModel(provider: provider, persistence: persistence, box: box)
        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        let tapped = cards[0]
        #expect(tapped.isCompleted == false)

        viewModel.cardTapped(tapped)

        #expect(box.routes == [.board(puzzleId: tapped.envelope.identity.puzzleId)])
    }

    /// #830: `openCompleted` now calls `persistence.loadIfExists`, not
    /// `loadOrCreate` — a fetch failure here is `loadIfExists` THROWING
    /// (never swallowed into a virgin snapshot). Falls back to `.board`,
    /// same #379 contract as before.
    @Test func completedCardLoadFailureReportsAndFallsBackToBoard() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        await persistence.setLoadOrCreateError(.zoneNotProvisioned)
        let reporter = RecordingErrorReporter()
        let box = RoutePathBox()
        let viewModel = DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            errorReporter: reporter,
            dateProvider: { Self.fixedDate },
            path: box.binding
        )
        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        let completedCard = DailyCard(envelope: cards[2].envelope, isCompleted: true)

        await viewModel.openCompleted(
            puzzleId: completedCard.envelope.identity.puzzleId,
            difficulty: completedCard.difficulty
        )

        // Never worse than today's behavior: still navigates to the board.
        #expect(box.routes == [.board(puzzleId: cards[2].envelope.identity.puzzleId)])
        let count = await reporter.reportCount
        #expect(count == 1)
    }

    /// #830: `loadIfExists` returning `nil` (confirmed absence — no error,
    /// no scripted snapshot) must ALSO fall back to `.board`, not synthesize
    /// a virgin `.completion(elapsedSeconds: 0, mistakeCount: 0)`. Unlike the
    /// error case above this does NOT report through the funnel — nil is not
    /// an error, just "nothing to review".
    @Test func completedCardConfirmedAbsentFallsBackToBoardWithoutReporting() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        let reporter = RecordingErrorReporter()
        let box = RoutePathBox()
        let viewModel = DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            errorReporter: reporter,
            dateProvider: { Self.fixedDate },
            path: box.binding
        )
        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        let completedCard = DailyCard(envelope: cards[2].envelope, isCompleted: true)

        await viewModel.openCompleted(
            puzzleId: completedCard.envelope.identity.puzzleId,
            difficulty: completedCard.difficulty
        )

        #expect(box.routes == [.board(puzzleId: cards[2].envelope.identity.puzzleId)])
        let count = await reporter.reportCount
        #expect(count == 0)
    }

    // MARK: - #686: `.exhausted` alert CTAs

    @Test func tryPracticeInsteadSwapsLastPathEntryFromDailyToPractice() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        let box = RoutePathBox()
        box.binding.wrappedValue = [.home, .daily]
        let viewModel = makeViewModel(provider: provider, persistence: persistence, box: box)

        viewModel.tryPracticeInstead()

        #expect(box.routes == [.home, .practice])
    }

    @Test func tryPracticeInsteadAppendsWhenPathIsEmpty() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        let box = RoutePathBox()
        let viewModel = makeViewModel(provider: provider, persistence: persistence, box: box)

        viewModel.tryPracticeInstead()

        #expect(box.routes == [.practice])
    }

    @Test func dismissExhaustedPopsBackToHome() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        let box = RoutePathBox()
        box.binding.wrappedValue = [.home, .daily]
        let viewModel = makeViewModel(provider: provider, persistence: persistence, box: box)

        viewModel.dismissExhausted()

        #expect(box.routes == [.home])
    }

    @Test func dismissExhaustedIsNoOpWhenPathIsAlreadyEmpty() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        let box = RoutePathBox()
        let viewModel = makeViewModel(provider: provider, persistence: persistence, box: box)

        viewModel.dismissExhausted()

        #expect(box.routes == [])
    }

}

/// Records `report(_:underlying:source:)` calls so the failure-path test can
/// assert the error was funneled rather than silently swallowed.
private actor RecordingErrorReporter: ErrorReporter {
    private(set) var reportCount = 0

    func report(_ error: UserFacingError, underlying: any Error, source: String) {
        reportCount += 1
    }
}
