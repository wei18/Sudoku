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
// #983 briefly gave Leaderboard a route (`.dailyRank`) so every mode-card tap
// pushed unconditionally; that direction was reverted (see #983 follow-up).
// Leaderboard is back to a `presentLeaderboard` side-effect gated by
// `GameRootViewModel.presentGameCenterOrAlert` — no route, no push.

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
    .leaderboard: HomeModeContent<AppRoute>(subtitleKey: "Global / friends"),
    .settings: HomeModeContent<AppRoute>(subtitleKey: "Account / language", route: .settings)
]

/// Build VMs with a given auth state.
/// Tests needing a specific auth state bootstrap against a pre-configured fake.
/// Tests that only care about routing (not auth) skip bootstrap and use `.unknown`.
/// `leaderboardPresented()` reports whether the injected `presentLeaderboard`
/// side-effect fired, so the leaderboard matrix can assert the real dashboard
/// presenter ran (authenticated) or didn't (every other auth state).
@MainActor
private func makeVMs(
    authResult: Result<GameCenterAuthState, GameCenterError>? = nil
) async -> (rootVM: RootViewModel, homeVM: GameHomeViewModel<AppRoute>, leaderboardPresented: () -> Bool) {
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
    var didPresentLeaderboard = false
    let homeVM = GameHomeViewModel<AppRoute>(
        rootViewModel: rootVM,
        homeModes: sudokuHomeModes,
        presentLeaderboard: { didPresentLeaderboard = true }
    )
    return (rootVM, homeVM, { didPresentLeaderboard })
}

@MainActor
@Suite("HomeViewModel — interaction (GameHomeViewModel)")
struct HomeViewModelInteractionTests {

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

    @Test func sequentialSelectionsAppendInOrder() async {
        let (rootVM, homeVM, _) = await makeVMs()
        homeVM.select(.daily)
        homeVM.select(.practice)
        #expect(rootVM.path == [.daily, .practice])
    }

    // MARK: - #513: Leaderboard is a side-effect, not a route

    @Test func selectLeaderboardWhenUnauthenticatedSetsAlertFlag() async {
        let (rootVM, homeVM, leaderboardPresented) = await makeVMs(authResult: .failure(.cancelled))
        homeVM.select(.leaderboard)
        #expect(rootVM.showGameCenterSignedOutAlert == true)
        #expect(rootVM.path.isEmpty, "unauthenticated leaderboard tap must not push a route")
        #expect(leaderboardPresented() == false, "signed-out tap must not present the dashboard")
    }

    @Test func selectLeaderboardWhenUnknownSetsAlertFlag() async {
        // No bootstrap — authState stays .unknown (the default).
        let (rootVM, homeVM, leaderboardPresented) = await makeVMs()
        homeVM.select(.leaderboard)
        #expect(rootVM.showGameCenterSignedOutAlert == true)
        #expect(rootVM.path.isEmpty)
        #expect(leaderboardPresented() == false)
    }

    @Test func selectLeaderboardWhenRestrictedSetsAlertFlag() async {
        let (rootVM, homeVM, leaderboardPresented) = await makeVMs(authResult: .success(.restricted))
        homeVM.select(.leaderboard)
        #expect(rootVM.showGameCenterSignedOutAlert == true)
        #expect(rootVM.path.isEmpty)
        #expect(leaderboardPresented() == false)
    }

    @Test func selectLeaderboardWhenAuthenticatedPresentsLeaderboard() async {
        let player = PlayerSummary(teamPlayerId: "P001", displayName: "Tester")
        let (rootVM, homeVM, leaderboardPresented) = await makeVMs(authResult: .success(.authenticated(player)))
        homeVM.select(.leaderboard)
        #expect(rootVM.showGameCenterSignedOutAlert == false, "alert must not show when authenticated")
        #expect(rootVM.path.isEmpty, "leaderboard never pushes a route")
        #expect(leaderboardPresented() == true, "authenticated tap must present the native GC dashboard")
    }

    @Test func alertFlagDefaultsToFalse() async {
        let (rootVM, _, _) = await makeVMs()
        #expect(rootVM.showGameCenterSignedOutAlert == false)
    }
}
