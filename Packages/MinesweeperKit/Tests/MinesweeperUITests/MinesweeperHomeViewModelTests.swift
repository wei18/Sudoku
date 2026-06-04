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

    @Test func selectNewGamePushesNewGameRouteLocalStub() {
        let viewModel = MinesweeperHomeViewModel()
        viewModel.select(.newGame)
        #expect(viewModel.path == [.newGame])
    }

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

        viewModel.select(.newGame)
        viewModel.select(.daily)
        viewModel.select(.practice)

        #expect(box.routes == [.newGame, .daily, .practice])
    }

    @Test func allModesAreEnumerated() {
        // Guards the card list against accidental shrinkage — the grid renders
        // `MinesweeperHomeMode.allCases`, so the entry surface depends on this.
        #expect(MinesweeperHomeMode.allCases == [
            .newGame, .daily, .practice, .leaderboard, .settings,
        ])
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
