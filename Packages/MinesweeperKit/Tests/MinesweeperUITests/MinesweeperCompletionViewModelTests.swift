// MinesweeperCompletionViewModelTests — post-game Completion surface (#292 / #698).
//
// #698: the leaderboard-slice fetch/present machine (`bootstrap()`/`.state`/
// `retry()`/`setStateForTesting()`, the `GameCenterClient` dependency) was
// deleted from `MinesweeperCompletionViewModel` — the completion popup has
// hardcoded `state: .hidden` since v2.6 and never rendered it. This file now
// just pins the remaining hero-data-exposure contract; leaderboard-id plumbing
// stays covered by `MinesweeperGameCenterSubmitTests`.

import Foundation
import Testing
@testable import MinesweeperUI
import MinesweeperEngine

@MainActor
@Suite("MinesweeperCompletionViewModel — post-game surface")
struct MinesweeperCompletionViewModelTests {

    private func makeViewModel(
        didWin: Bool = true,
        elapsedSeconds: Int = 65
    ) -> MinesweeperCompletionViewModel {
        MinesweeperCompletionViewModel(
            didWin: didWin,
            elapsedSeconds: elapsedSeconds,
            leaderboardId: MinesweeperLeaderboardID.easyDaily
        )
    }

    @Test func didWinAndElapsedAreExposedForHero() {
        let viewModel = makeViewModel(didWin: true, elapsedSeconds: 125)
        #expect(viewModel.didWin == true)
        #expect(viewModel.elapsedSeconds == 125)
    }
}
