// HomeViewModelInteractionTests — drive the mode-card taps and assert each one
// pushes the right route through an *injected* navigation binding (issue #171).
//
// `HomeViewTests` already covers the local-stub path branch. This suite adds
// the external-`Binding` branch (the real RootView wiring) so a regression that
// stopped writing through the injected path — leaving cards as no-op taps —
// would fail here.
//
// #513: extended with signed-out GC leaderboard behaviour tests.

import SwiftUI
import Testing
import GameCenterClient
@testable import SudokuUI

@MainActor
@Suite("HomeViewModel — interaction (injected path)")
struct HomeViewModelInteractionTests {

    @Test func selectDailyPushesDailyRouteThroughInjectedBinding() {
        let box = RoutePathBox()
        let viewModel = HomeViewModel(path: box.binding)

        viewModel.select(.daily)

        #expect(box.routes == [.daily])
        #expect(viewModel.path == [.daily])
    }

    @Test func selectPracticePushesPracticeRouteThroughInjectedBinding() {
        let box = RoutePathBox()
        let viewModel = HomeViewModel(path: box.binding)

        viewModel.select(.practice)

        #expect(box.routes == [.practice])
    }

    @Test func selectSettingsPushesSettingsRouteThroughInjectedBinding() {
        let box = RoutePathBox()
        let viewModel = HomeViewModel(path: box.binding)

        viewModel.select(.settings)

        #expect(box.routes == [.settings])
    }

    @Test func sequentialSelectionsAppendInOrder() {
        let box = RoutePathBox()
        let viewModel = HomeViewModel(path: box.binding)

        viewModel.select(.daily)
        viewModel.select(.practice)

        #expect(box.routes == [.daily, .practice])
    }

    // MARK: - #513: Leaderboard signed-out affordance

    // When GC is unauthenticated, `select(.leaderboard)` must NOT push a route
    // and must set `showGameCenterSignedOutAlert = true`.
    @Test func selectLeaderboardWhenUnauthenticatedSetsAlertFlag() {
        let viewModel = HomeViewModel(authState: .unauthenticated)

        viewModel.select(.leaderboard)

        #expect(viewModel.showGameCenterSignedOutAlert == true)
        #expect(viewModel.path.isEmpty, "unauthenticated leaderboard tap must not push a route")
    }

    @Test func selectLeaderboardWhenUnknownSetsAlertFlag() {
        let viewModel = HomeViewModel(authState: .unknown)

        viewModel.select(.leaderboard)

        #expect(viewModel.showGameCenterSignedOutAlert == true)
        #expect(viewModel.path.isEmpty)
    }

    @Test func selectLeaderboardWhenRestrictedSetsAlertFlag() {
        let viewModel = HomeViewModel(authState: .restricted)

        viewModel.select(.leaderboard)

        #expect(viewModel.showGameCenterSignedOutAlert == true)
        #expect(viewModel.path.isEmpty)
    }

    @Test func selectLeaderboardWhenAuthenticatedDoesNotSetAlertFlag() {
        // When authenticated, the leaderboard tap should open the GC dashboard
        // (a side-effect that is inert in the test host) and NOT show the alert.
        let player = PlayerSummary(teamPlayerId: "P001", displayName: "Tester")
        let viewModel = HomeViewModel(authState: .authenticated(player))

        viewModel.select(.leaderboard)

        #expect(viewModel.showGameCenterSignedOutAlert == false, "alert must not show when authenticated")
        #expect(viewModel.path.isEmpty, "leaderboard never pushes a route")
    }

    @Test func alertFlagDefaultsToFalse() {
        let viewModel = HomeViewModel()
        #expect(viewModel.showGameCenterSignedOutAlert == false)
    }

    // `.leaderboard` when authenticated reaches `GameCenterDashboard.present()`
    // → Apple's `GKAccessPoint.shared` singleton, which is inert in the test
    // host. The signed-out path is now fully unit-testable via the alert flag.
}
