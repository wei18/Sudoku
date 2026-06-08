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

import GameState
import Persistence
import PuzzleStore
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
        #expect(persistenceOps == [.fetchCompletedDailyIds(date: Self.fixedDate)])
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

        await viewModel.openCompleted(completedCard)

        #expect(box.routes == [
            .completion(puzzleId: base.envelope.identity.puzzleId, elapsedSeconds: 742)
        ])
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

        await viewModel.openCompleted(completedCard)

        // Never worse than today's behavior: still navigates to the board.
        #expect(box.routes == [.board(puzzleId: cards[2].envelope.identity.puzzleId)])
        let count = await reporter.reportCount
        #expect(count == 1)
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
