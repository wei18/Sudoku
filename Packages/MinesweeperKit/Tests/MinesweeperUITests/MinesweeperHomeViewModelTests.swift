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
//
// #983 briefly gave Leaderboard a route (`.dailyRank`) so every mode-card tap
// pushed unconditionally; that direction was reverted (see #983 follow-up).
// Leaderboard is back to a `presentLeaderboard` side-effect gated by
// `GameRootViewModel.presentGameCenterOrAlert` — no route, no push.

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
    .leaderboard: HomeModeContent<AppRoute>(subtitleKey: "Global / friends"),
    .settings: HomeModeContent<AppRoute>(subtitleKey: "Purchases / about", route: .settings)
]

/// Build VMs with a given auth state. `leaderboardPresented()` reports
/// whether the injected `presentLeaderboard` side-effect fired, so the
/// leaderboard matrix can assert the real dashboard presenter ran
/// (authenticated) or didn't (every other auth state).
@MainActor
private func makeVMs(
    authResult: Result<GameCenterAuthState, GameCenterError>? = nil
) async -> (rootVM: MinesweeperRootViewModel, homeVM: GameHomeViewModel<AppRoute>, leaderboardPresented: () -> Bool) {
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
    var didPresentLeaderboard = false
    let homeVM = GameHomeViewModel<AppRoute>(
        rootViewModel: rootVM,
        homeModes: minesweeperHomeModes,
        presentLeaderboard: { didPresentLeaderboard = true },
        // #773: mirrors MinesweeperAppComposition.live()'s statsRoute.
        statsRoute: .stats
    )
    return (rootVM, homeVM, { didPresentLeaderboard })
}

@MainActor
@Suite("MinesweeperHomeViewModel — interaction")
struct MinesweeperHomeViewModelTests {

    @Test func selectDailyPushesDailyRoute() async {
        let (rootVM, homeVM, _) = await makeVMs()
        homeVM.select(.daily)
        #expect(rootVM.path == [.daily])
    }

    @Test func selectPracticePushesPracticeRoute() async {
        let (rootVM, homeVM, _) = await makeVMs()
        homeVM.select(.practice)
        #expect(rootVM.path == [.practice])
    }

    @Test func selectSettingsPushesSettingsRoute() async {
        let (rootVM, homeVM, _) = await makeVMs()
        homeVM.select(.settings)
        #expect(rootVM.path == [.settings])
    }

    // #773: the secondary-weight Statistics entry pushes `.stats`.
    @Test func selectStatsPushesStatsRoute() async {
        let (rootVM, homeVM, _) = await makeVMs()
        #expect(homeVM.showsStatsEntry)
        homeVM.selectStats()
        #expect(rootVM.path == [.stats])
    }

    // MARK: - #513: Leaderboard is a side-effect, not a route

    @Test func selectLeaderboardWhenUnknownSetsAlertFlag() async {
        // No bootstrap — authState stays .unknown (the default).
        let (rootVM, homeVM, leaderboardPresented) = await makeVMs()
        homeVM.select(.leaderboard)
        #expect(rootVM.showGameCenterSignedOutAlert == true)
        #expect(rootVM.path.isEmpty)
        #expect(leaderboardPresented() == false)
    }

    @Test func selectLeaderboardWhenUnauthenticatedSetsAlertFlag() async {
        let (rootVM, homeVM, leaderboardPresented) = await makeVMs(
            authResult: .failure(.notAuthenticated)
        )
        homeVM.select(.leaderboard)
        #expect(rootVM.showGameCenterSignedOutAlert == true)
        #expect(rootVM.path.isEmpty, "unauthenticated leaderboard tap must not push a route")
        #expect(leaderboardPresented() == false)
    }

    @Test func selectLeaderboardWhenAuthenticatedPresentsLeaderboard() async {
        let player = PlayerSummary(teamPlayerId: "P001", displayName: "Sweeper")
        let (rootVM, homeVM, leaderboardPresented) = await makeVMs(
            authResult: .success(.authenticated(player))
        )
        homeVM.select(.leaderboard)
        #expect(rootVM.showGameCenterSignedOutAlert == false, "alert must not show when authenticated")
        #expect(rootVM.path.isEmpty, "leaderboard never pushes a route")
        #expect(leaderboardPresented() == true, "authenticated tap must present the native GC dashboard")
    }

    @Test func sequentialSelectionsAppendInOrder() async {
        let (rootVM, homeVM, _) = await makeVMs()
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
        let (_, homeVM, _) = await makeVMs()
        let ids = homeVM.modeItems.map(\.id)
        #expect(ids == ["daily", "practice", "leaderboard", "settings"])
        #expect(!ids.contains("newGame"))
    }
}
