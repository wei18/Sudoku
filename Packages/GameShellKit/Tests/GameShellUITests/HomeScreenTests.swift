import SwiftUI
import Testing
@testable import GameShellUI

// MARK: - HomeScreen (#410)
//
// The shared Home scaffold + mode model, extracted from SudokuUI.HomeView +
// MinesweeperUI.MinesweeperHomeView. These tests pin three contracts:
//   1. the single source of truth for the 4 common modes — Daily / Practice /
//      Leaderboard / Settings, in render order, with canonical SF Symbols.
//   2. monetization/GC decoupling — `HomeScreen` instantiates with plain
//      `HomeModeItem` values + injected slots, with NO MonetizationUI /
//      GameCenterClient / AdMob types (compile-only sentinel, mirrors the
//      sibling CompletionScreen / RootShellView sentinels). If a future change
//      leaks a commerce/GC type into the shell, this target stops compiling.
//   3. the sidebar derives from the SAME mode list — `sidebarItems(from:)`
//      preserves id / title / symbol order so Home cards + sidebar can't drift.
//
// Pixel-level verification of the shared body lives in the two apps' existing
// snapshot suites (SudokuUITests.HomeViewTests +
// MinesweeperUITests.MinesweeperHomeSnapshotTests), which render through the
// real wrappers; keeping those baselines byte-identical is the regression guard.

// File-scope (not nested under the suite) so SwiftLint's `nesting` rule is
// satisfied — mirrors `RootShellViewGenericityTests.SentinelRoute`.
private enum HomeSidebarSentinelRoute: Hashable { case only }

@Suite("GameShellUI — HomeScreen")
@MainActor
struct HomeScreenTests {

    @Test func sharedModeSetIsTheFourCommonModesInOrder() {
        #expect(HomeMode.allCases == [.daily, .practice, .leaderboard, .settings])
    }

    @Test func canonicalSymbolsMatchBothApps() {
        #expect(HomeMode.daily.symbolName == "calendar")
        #expect(HomeMode.practice.symbolName == "dice")
        #expect(HomeMode.leaderboard.symbolName == "trophy")
        #expect(HomeMode.settings.symbolName == "gear")
    }

    // Compile-only sentinel: HomeScreen mounts with plain values + injected
    // slots, no commerce/GC types. The slots are filled with bare SwiftUI views.
    @Test func instantiatesWithoutMonetizationOrGameCenter() {
        let items = HomeMode.allCases.map { mode in
            HomeModeItem(mode: mode, subtitleKey: "sub", onTap: {})
        }
        let screen = HomeScreen(
            items: items,
            cardAccessibilityIdentifier: { "id.\($0.rawValue)" },
            header: { Text("header") },
            removeAdsCard: { Color.clear.frame(height: 1) },
            banner: { Color.clear.frame(height: 1) }
        )
        _ = screen
    }

    // The sidebar list is derived from the SAME `HomeModeItem` list, so the two
    // surfaces share one source of truth. Phantom Route type proves the deriver
    // never names a concrete route.
    @Test func sidebarItemsDeriveFromTheSameModeList() {
        let items = HomeMode.allCases.map { mode in
            HomeModeItem(mode: mode, subtitleKey: "sub", onTap: {})
        }
        let sidebar: [SidebarItem<HomeSidebarSentinelRoute>] =
            HomeModeItem.sidebarItems(from: items)

        #expect(sidebar.map(\.id) == ["daily", "practice", "leaderboard", "settings"])
        #expect(sidebar.map(\.systemImage) == ["calendar", "dice", "trophy", "gear"])
    }
}
