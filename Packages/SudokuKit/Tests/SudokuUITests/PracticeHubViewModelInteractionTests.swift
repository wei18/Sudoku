// PracticeHubViewModelInteractionTests — difficulty pick → draw → play, asserting
// service call shape and navigation through an injected binding (issue #171).
//
// `PracticeHubViewTests` covers the local-stub `playTapped` branch and the
// shimmer/draw state machine. This suite adds (1) the external-`Binding`
// navigation branch and (2) behavioral provider call-shape assertions — draw
// must fetch the *selected* difficulty, and play must push the *drawn* puzzle —
// so a regression in either coupling would fail here.

import Foundation
import Testing
@testable import SudokuUI

import SudokuPersistence
import SudokuEngine
import SudokuKitTesting

@MainActor
@Suite("PracticeHubViewModel — interaction (services + injected path)")
struct PracticeHubViewModelInteractionTests {

    @Test func drawFetchesSelectedDifficulty() async {
        let provider = FakePuzzleProvider()
        let viewModel = PracticeHubViewModel(provider: provider, path: RoutePathBox().binding)

        viewModel.selectDifficulty(.hard)
        await viewModel.drawPuzzle()

        let ops = await provider.operations
        #expect(ops == [.fetchPracticePool(difficulty: .hard)])
    }

    @Test func selectDifficultyDoesNotFetch() async {
        let provider = FakePuzzleProvider()
        let viewModel = PracticeHubViewModel(provider: provider, path: RoutePathBox().binding)

        viewModel.selectDifficulty(.easy)

        // Picking a segment must not trigger a draw — the CTA stays primary.
        let ops = await provider.operations
        #expect(ops.isEmpty)
        #expect(viewModel.difficulty == .easy)
    }

    @Test func playTappedPushesDrawnPuzzleThroughInjectedBinding() async {
        let provider = FakePuzzleProvider()
        let box = RoutePathBox()
        let viewModel = PracticeHubViewModel(provider: provider, path: box.binding)
        await viewModel.drawPuzzle()

        guard case .drawn(let envelope) = viewModel.loadingState else {
            Issue.record("expected drawn state, got \(viewModel.loadingState)")
            return
        }

        viewModel.playTapped()

        #expect(box.routes == [.board(puzzleId: envelope.identity.puzzleId)])
    }

    @Test func playTappedBeforeDrawDoesNotNavigate() {
        let box = RoutePathBox()
        let viewModel = PracticeHubViewModel(provider: FakePuzzleProvider(), path: box.binding)

        // No puzzle drawn yet — Play is guarded and must be a no-op.
        viewModel.playTapped()

        #expect(box.routes.isEmpty)
    }
}
