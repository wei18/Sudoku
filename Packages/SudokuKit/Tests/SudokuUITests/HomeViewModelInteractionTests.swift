// HomeViewModelInteractionTests — drive the mode-card taps and assert each one
// pushes the right route through an *injected* navigation binding (issue #171).
//
// `HomeViewTests` already covers the local-stub path branch. This suite adds
// the external-`Binding` branch (the real RootView wiring) so a regression that
// stopped writing through the injected path — leaving cards as no-op taps —
// would fail here.

import SwiftUI
import Testing
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

    // `.leaderboard` is intentionally NOT exercised here: `select(.leaderboard)`
    // reaches `GameCenterDashboard.present()` → Apple's `GKAccessPoint.shared`
    // singleton, which can't be faked from unit-test scope without a UI host.
    // Same precedent as CompletionViewTests (issue #49). The invariant we *can*
    // assert is that the four push-modes never present GC and that the
    // leaderboard branch performs no path push — but asserting the latter
    // requires invoking the singleton, so it stays a manual-validation item.
}
