// HomeViewModelInteractionTests — drive the mode-card taps and assert each one
// pushes the right route through the shared `GameHomeViewModel` / `GameRootViewModel`.
//
// #557: HomeViewModel retired; tests migrated to GameHomeViewModel<AppRoute>.
// GameHomeViewModel routes through GameRootViewModel.path instead of an injected
// Binding<[Route]>; assertions compare rootVM.path (same semantics).
//
// #513: signed-out GC leaderboard behaviour preserved — alert flag lives on the
// stable `GameRootViewModel.showGameCenterSignedOutAlert` (not a transient VM).
//
// #983: Leaderboard is no longer a `presentLeaderboard` side-effect gated by
// `presentGameCenterOrAlert` — it now has a route (`.dailyRank`) like every
// other mode, so `GameHomeViewModel.select` pushes it unconditionally. The
// not-signed-in explainer moved INSIDE `DailyRankView` (state 1 of the #983
// spec) instead of gating the Home tap itself.

import GameAppKit
import GameCenterClient
import GameCenterTesting
import GameShellUI
import Persistence
import SudokuKitTesting
import SwiftUI
import Testing
@testable import SudokuUI

// Helper: Sudoku home mode config (same literals as Live.swift / HomeViewTests).
@MainActor
private let sudokuHomeModes: [HomeMode: HomeModeContent<AppRoute>] = [
    .daily: HomeModeContent<AppRoute>(subtitleKey: "3 puzzles today", route: .daily),
    .practice: HomeModeContent<AppRoute>(subtitleKey: "Mixed difficulty pool", route: .practice),
    .leaderboard: HomeModeContent<AppRoute>(subtitleKey: "Global / friends", route: .dailyRank),
    .settings: HomeModeContent<AppRoute>(subtitleKey: "Account / language", route: .settings)
]

/// Build VMs with a given auth state.
/// Tests needing a specific auth state bootstrap against a pre-configured fake.
/// Tests that only care about routing (not auth) skip bootstrap and use `.unknown`.
@MainActor
private func makeVMs(
    authResult: Result<GameCenterAuthState, GameCenterError>? = nil
) async -> (rootVM: RootViewModel, homeVM: GameHomeViewModel<AppRoute>) {
    let gameCenter = FakeGameCenterClient()
    if let result = authResult {
        await gameCenter.setAuthResult(result)
    }
    let rootVM = RootViewModel(
        gameCenter: gameCenter,
        persistence: FakePersistence()
    )
    if authResult != nil {
        await rootVM.bootstrap()
    }
    let homeVM = GameHomeViewModel<AppRoute>(
        rootViewModel: rootVM,
        homeModes: sudokuHomeModes,
        presentLeaderboard: {}
    )
    return (rootVM, homeVM)
}

@MainActor
@Suite("HomeViewModel — interaction (GameHomeViewModel)")
struct HomeViewModelInteractionTests {

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

    @Test func sequentialSelectionsAppendInOrder() async {
        let (rootVM, homeVM) = await makeVMs()
        homeVM.select(.daily)
        homeVM.select(.practice)
        #expect(rootVM.path == [.daily, .practice])
    }

    // MARK: - #513/#983: Leaderboard push is unconditional (no signed-out gate)

    @Test func selectLeaderboardWhenUnauthenticatedStillPushesRoute() async {
        let (rootVM, homeVM) = await makeVMs(authResult: .failure(.cancelled))
        homeVM.select(.leaderboard)
        #expect(rootVM.showGameCenterSignedOutAlert == false)
        #expect(rootVM.path == [.dailyRank])
    }

    @Test func selectLeaderboardWhenUnknownStillPushesRoute() async {
        // No bootstrap — authState stays .unknown (the default).
        let (rootVM, homeVM) = await makeVMs()
        homeVM.select(.leaderboard)
        #expect(rootVM.showGameCenterSignedOutAlert == false)
        #expect(rootVM.path == [.dailyRank])
    }

    @Test func selectLeaderboardWhenRestrictedStillPushesRoute() async {
        let (rootVM, homeVM) = await makeVMs(authResult: .success(.restricted))
        homeVM.select(.leaderboard)
        #expect(rootVM.showGameCenterSignedOutAlert == false)
        #expect(rootVM.path == [.dailyRank])
    }

    @Test func selectLeaderboardWhenAuthenticatedPushesRoute() async {
        let player = PlayerSummary(teamPlayerId: "P001", displayName: "Tester")
        let (rootVM, homeVM) = await makeVMs(authResult: .success(.authenticated(player)))
        homeVM.select(.leaderboard)
        #expect(rootVM.showGameCenterSignedOutAlert == false, "alert must not show when authenticated")
        #expect(rootVM.path == [.dailyRank])
    }

    @Test func alertFlagDefaultsToFalse() async {
        let (rootVM, _) = await makeVMs()
        #expect(rootVM.showGameCenterSignedOutAlert == false)
    }
}
