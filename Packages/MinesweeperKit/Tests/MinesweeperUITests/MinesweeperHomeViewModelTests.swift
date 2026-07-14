// MinesweeperHomeViewModelTests — drive the mode-card taps and assert each one
// pushes the right route through the shared `GameHomeViewModel` / `GameRootViewModel`.
//
// #572 SDD-005 Pillar C: `MinesweeperHomeViewModel` retired; tests migrated to
// `GameHomeViewModel<AppRoute>`. `GameHomeViewModel` routes through
// `GameRootViewModel.path`; assertions compare `rootVM.path` (same semantics).
// The `MinesweeperHomeMode` typealias (`= HomeMode`) stays available from
// `@testable import MinesweeperUI` for the mode-enum assertion tests.
//
// #513: signed-out GC leaderboard behaviour preserved — alert flag lives on the
// stable `GameRootViewModel.showGameCenterSignedOutAlert` (not a transient VM).

import GameAppKit
import GameCenterClient
import GameCenterTesting
import GameShellUI
import PersistenceTesting
import SwiftUI
import Testing
@testable import MinesweeperUI

// MS per-mode subtitle copy — byte-identical to the former subtitleKey extension.
@MainActor
private let minesweeperHomeModes: [HomeMode: HomeModeContent<AppRoute>] = [
    .daily: HomeModeContent<AppRoute>(subtitleKey: "3 boards today", route: .daily),
    .practice: HomeModeContent<AppRoute>(subtitleKey: "All difficulties", route: .practice),
    .leaderboard: HomeModeContent<AppRoute>(subtitleKey: "Best times"),
    .settings: HomeModeContent<AppRoute>(subtitleKey: "Purchases / about", route: .settings)
]

/// Build VMs with a given auth state.
@MainActor
private func makeVMs(
    authResult: Result<GameCenterAuthState, GameCenterError>? = nil
) async -> (rootVM: MinesweeperRootViewModel, homeVM: GameHomeViewModel<AppRoute>) {
    let gameCenter = FakeGameCenterClient()
    if let result = authResult {
        await gameCenter.setAuthResult(result)
    }
    let rootVM = MinesweeperRootViewModel(
        gameCenter: gameCenter,
        persistence: FakePersistence()
    )
    if authResult != nil {
        await rootVM.bootstrap()
    }
    let homeVM = GameHomeViewModel<AppRoute>(
        rootViewModel: rootVM,
        homeModes: minesweeperHomeModes,
        presentLeaderboard: { GameCenterDashboard.present(leaderboardId: nil) },
        // #773: mirrors MinesweeperAppComposition.live()'s statsRoute.
        statsRoute: .stats
    )
    return (rootVM, homeVM)
}

@MainActor
@Suite("MinesweeperHomeViewModel — interaction")
struct MinesweeperHomeViewModelTests {

    @Test func selectDailyPushesDailyRoute() async {
        let (rootVM, homeVM) = await makeVMs()
        homeVM.select(.daily)
        #expect(rootVM.path == [.daily])
    }

    @Test func selectPracticePushesPracticeRoute() async {
        let (rootVM, homeVM) = await makeVMs()
        homeVM.select(.practice)
        #expect(rootVM.path == [.practice])
    }

    @Test func selectSettingsPushesSettingsRoute() async {
        let (rootVM, homeVM) = await makeVMs()
        homeVM.select(.settings)
        #expect(rootVM.path == [.settings])
    }

    // #773: the secondary-weight Statistics entry pushes `.stats`.
    @Test func selectStatsPushesStatsRoute() async {
        let (rootVM, homeVM) = await makeVMs()
        #expect(homeVM.showsStatsEntry)
        homeVM.selectStats()
        #expect(rootVM.path == [.stats])
    }

    // Leaderboard presents the native GC dashboard as a modal side-effect
    // (#291 / #49) — it must NOT push a route.
    @Test func selectLeaderboardPushesNoRoute() async {
        let (rootVM, homeVM) = await makeVMs()
        homeVM.select(.leaderboard)
        #expect(rootVM.path.isEmpty)
    }

    // MARK: - #513: Leaderboard signed-out affordance

    @Test func selectLeaderboardWhenUnauthenticatedSetsAlertFlag() async {
        let (rootVM, homeVM) = await makeVMs(
            authResult: .failure(.notAuthenticated)
        )
        homeVM.select(.leaderboard)
        #expect(rootVM.showGameCenterSignedOutAlert == true)
        #expect(rootVM.path.isEmpty, "unauthenticated leaderboard tap must not push a route")
    }

    @Test func selectLeaderboardWhenAuthenticatedDoesNotSetAlertFlag() async {
        let player = PlayerSummary(teamPlayerId: "P001", displayName: "Sweeper")
        let (rootVM, homeVM) = await makeVMs(
            authResult: .success(.authenticated(player))
        )
        homeVM.select(.leaderboard)
        #expect(rootVM.showGameCenterSignedOutAlert == false, "alert must not show when authenticated")
        #expect(rootVM.path.isEmpty, "leaderboard never pushes a route")
    }

    @Test func sequentialSelectionsAppendInOrder() async {
        let (rootVM, homeVM) = await makeVMs()
        homeVM.select(.daily)
        homeVM.select(.practice)
        homeVM.select(.settings)
        #expect(rootVM.path == [.daily, .practice, .settings])
    }

    // #410: the mode set is the 4 shared modes (Daily / Practice / Leaderboard /
    // Settings) — no New Game. Guards against accidental shrinkage.
    // #572: MinesweeperHomeMode typealias deleted; use shared HomeMode directly.
    @Test func allModesAreEnumeratedWithoutNewGame() {
        #expect(HomeMode.allCases == [
            .daily, .practice, .leaderboard, .settings,
        ])
        #expect(!HomeMode.allCases.contains { $0.id == "newGame" })
    }

    // #410: the Home mode-items list carries no New Game entry.
    @Test func modeItemsHaveNoNewGameEntry() async {
        let (_, homeVM) = await makeVMs()
        let ids = homeVM.modeItems.map(\.id)
        #expect(ids == ["daily", "practice", "leaderboard", "settings"])
        #expect(!ids.contains("newGame"))
    }
}
