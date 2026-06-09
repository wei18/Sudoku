// MinesweeperHomeViewModelTests — drive the mode-card taps and assert each one
// pushes the right route through an injected navigation binding (#288 / #289).
//
// Mirror of Sudoku's `HomeViewModelInteractionTests`. Covers both the
// local-stub branch (no binding) and the external-`Binding` branch (the real
// MinesweeperRoot wiring) so a regression that stopped writing through the
// injected path — leaving cards as no-op taps — would fail here.

import SwiftUI
import Testing
@testable import MinesweeperUI

@MainActor
@Suite("MinesweeperHomeViewModel — interaction")
struct MinesweeperHomeViewModelTests {

    // MARK: - Local-stub branch (no injected binding)

    @Test func selectDailyPushesDailyRouteLocalStub() {
        let viewModel = MinesweeperHomeViewModel()
        viewModel.select(.daily)
        #expect(viewModel.path == [.daily])
    }

    @Test func selectPracticePushesPracticeRouteLocalStub() {
        let viewModel = MinesweeperHomeViewModel()
        viewModel.select(.practice)
        #expect(viewModel.path == [.practice])
    }

    @Test func selectSettingsPushesSettingsRouteLocalStub() {
        let viewModel = MinesweeperHomeViewModel()
        viewModel.select(.settings)
        #expect(viewModel.path == [.settings])
    }

    // Leaderboard presents the native GC dashboard as a modal side-effect
    // (#291 / #49) — it must NOT push a route. The present call bottoms out in
    // GameKit / GKAccessPoint, which is inert in the test host, so we assert
    // the navigation invariant: `select(.leaderboard)` leaves the path empty.
    @Test func selectLeaderboardPushesNoRoute() {
        let viewModel = MinesweeperHomeViewModel()
        viewModel.select(.leaderboard)
        #expect(viewModel.path.isEmpty)
    }

    @Test func selectLeaderboardThroughInjectedBindingPushesNoRoute() {
        let box = RoutePathBox()
        let viewModel = MinesweeperHomeViewModel(path: box.binding)
        viewModel.select(.leaderboard)
        // Modal side-effect only — the injected nav binding stays untouched.
        #expect(box.routes.isEmpty)
        #expect(viewModel.path.isEmpty)
    }

    // MARK: - External-binding branch (real MinesweeperRoot wiring)

    @Test func selectDailyPushesDailyRouteThroughInjectedBinding() {
        let box = RoutePathBox()
        let viewModel = MinesweeperHomeViewModel(path: box.binding)

        viewModel.select(.daily)

        #expect(box.routes == [.daily])
        #expect(viewModel.path == [.daily])
    }

    @Test func selectPracticePushesPracticeRouteThroughInjectedBinding() {
        let box = RoutePathBox()
        let viewModel = MinesweeperHomeViewModel(path: box.binding)

        viewModel.select(.practice)

        #expect(box.routes == [.practice])
    }

    @Test func sequentialSelectionsAppendInOrder() {
        let box = RoutePathBox()
        let viewModel = MinesweeperHomeViewModel(path: box.binding)

        viewModel.select(.daily)
        viewModel.select(.practice)
        viewModel.select(.settings)

        #expect(box.routes == [.daily, .practice, .settings])
    }

    // #410: the erroneous "New Game" mode was removed — MS's mode set is now
    // identical to Sudoku's: Daily / Practice / Leaderboard / Settings, in that
    // order. Guards the card list against accidental shrinkage AND against the
    // New Game mode creeping back in.
    @Test func allModesAreEnumeratedWithoutNewGame() {
        #expect(MinesweeperHomeMode.allCases == [
            .daily, .practice, .leaderboard, .settings,
        ])
        // No `newGame` case exists on the shared enum at all.
        #expect(!MinesweeperHomeMode.allCases.contains { $0.id == "newGame" })
    }

    // #410: the Home mode-items list (single source for cards + sidebar) carries
    // no New Game entry, so neither the Home grid nor the sidebar can show one.
    @Test func modeItemsHaveNoNewGameEntry() {
        let viewModel = MinesweeperHomeViewModel()
        let ids = viewModel.modeItems.map(\.id)
        #expect(ids == ["daily", "practice", "leaderboard", "settings"])
        #expect(!ids.contains("newGame"))
    }
}

/// Mutable, `@MainActor`-isolated holder exposing a `Binding<[AppRoute]>` that
/// records every route the VM writes. Mirrors the role a host `NavigationStack`
/// path plays in production (parallels Sudoku's `RoutePathBox` test seam).
@MainActor
final class RoutePathBox {
    private(set) var routes: [AppRoute] = []

    var binding: Binding<[AppRoute]> {
        Binding(
            get: { self.routes },
            set: { self.routes = $0 }
        )
    }
}
