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

import Persistence
import PuzzleStore
import SudokuKitTesting

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
}
