// HomeViewModelInteractionTests — drive the mode-card taps and assert each one
// pushes the right route through an *injected* navigation binding (issue #171).
//
// `HomeViewTests` already covers the local-stub path branch. This suite adds
// the external-`Binding` branch (the real RootView wiring) so a regression that
// stopped writing through the injected path — leaving cards as no-op taps —
// would fail here.
//
// #513: extended with signed-out GC leaderboard behaviour tests.
// #513 fix: alert tests now inject an external Binding<Bool> (mirroring the
// stable GameRootViewModel flag) so the assertion proves the flag is written
// to the external source, not just a local transient VM field.

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
    //
    // Tests inject a `Binding<Bool>` to mirror the stable `GameRootViewModel`
    // flag wiring in production. The fix moves alert state out of the transient
    // per-render HomeViewModel (the swiftui-interaction-footguns "computed
    // property VM" class) onto the long-lived GameRootViewModel; tests prove the
    // flag is written to the *external* binding, not just VM-local state.

    // When GC is unauthenticated, `select(.leaderboard)` must NOT push a route
    // and must set the alert flag via the injected binding.
    @Test func selectLeaderboardWhenUnauthenticatedSetsAlertFlag() {
        let alertBox = AlertFlagBox()
        let viewModel = HomeViewModel(
            authState: .unauthenticated,
            showGameCenterSignedOutAlert: alertBox.binding
        )

        viewModel.select(.leaderboard)

        #expect(alertBox.value == true)
        #expect(viewModel.showGameCenterSignedOutAlert == true)
        #expect(viewModel.path.isEmpty, "unauthenticated leaderboard tap must not push a route")
    }

    @Test func selectLeaderboardWhenUnknownSetsAlertFlag() {
        let alertBox = AlertFlagBox()
        let viewModel = HomeViewModel(
            authState: .unknown,
            showGameCenterSignedOutAlert: alertBox.binding
        )

        viewModel.select(.leaderboard)

        #expect(alertBox.value == true)
        #expect(viewModel.path.isEmpty)
    }

    @Test func selectLeaderboardWhenRestrictedSetsAlertFlag() {
        let alertBox = AlertFlagBox()
        let viewModel = HomeViewModel(
            authState: .restricted,
            showGameCenterSignedOutAlert: alertBox.binding
        )

        viewModel.select(.leaderboard)

        #expect(alertBox.value == true)
        #expect(viewModel.path.isEmpty)
    }

    @Test func selectLeaderboardWhenAuthenticatedDoesNotSetAlertFlag() {
        // When authenticated, the leaderboard tap should open the GC dashboard
        // (a side-effect that is inert in the test host) and NOT show the alert.
        let alertBox = AlertFlagBox()
        let player = PlayerSummary(teamPlayerId: "P001", displayName: "Tester")
        let viewModel = HomeViewModel(
            authState: .authenticated(player),
            showGameCenterSignedOutAlert: alertBox.binding
        )

        viewModel.select(.leaderboard)

        #expect(alertBox.value == false, "alert must not show when authenticated")
        #expect(viewModel.showGameCenterSignedOutAlert == false)
        #expect(viewModel.path.isEmpty, "leaderboard never pushes a route")
    }

    @Test func alertFlagDefaultsToFalse() {
        // No binding injected — fallback returns false (no stable source wired).
        let viewModel = HomeViewModel()
        #expect(viewModel.showGameCenterSignedOutAlert == false)
    }

    // `.leaderboard` when authenticated reaches `GameCenterDashboard.present()`
    // → Apple's `GKAccessPoint.shared` singleton, which is inert in the test
    // host. The signed-out path is fully unit-testable via the injected binding.
}

/// Mutable holder exposing a `Binding<Bool>` that records the alert flag written
/// by `HomeViewModel`. Mirrors the role of `GameRootViewModel.showGameCenterSignedOutAlert`
/// in production — the stable external flag the alert is bound to.
@MainActor
final class AlertFlagBox {
    private(set) var value: Bool = false

    var binding: Binding<Bool> {
        Binding(
            get: { self.value },
            set: { self.value = $0 }
        )
    }
}
