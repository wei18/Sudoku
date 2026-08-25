// TabRootChromeTests — the #1020 shared Settings gear.
//
// design.md §2.1 / §3.7 put a gear on every tab's trailing toolbar. This is the
// app's ONLY Settings entry point now that HOME (and its Settings card) is
// retired — an interactive iPad pass over the new shell found Settings simply
// unreachable, which is what this chrome fixes.
//
// Two properties are pinned here:
//   1. the gear pushes `settingsRoute` onto the SELECTED tab (so Back returns to
//      the tab that opened it, per §2.1's per-tab paths), and
//   2. every tab root carries the chrome — enforced by the return TYPE of
//      `chromedTabRoots`, so the annotation below is itself the assertion.

import Foundation
import SwiftUI
import Testing
import GameCenterClient
import GameShellUI
import SudokuGameState
import Persistence
import SudokuEngine
import Telemetry
@testable import GameAppKit

// MARK: - Test route

private enum ChromeRoute: Hashable, Sendable {
    case settings
    case board(puzzleId: String)
}

// MARK: - Fakes

private actor ChromeStubPersistence: PersistenceProtocol {
    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> GameSessionSnapshot {
        throw PersistenceError.zoneNotProvisioned
    }
    func save(
        _ snapshot: GameSessionSnapshot,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws {}
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> { [] }
    func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>] { [:] }
    func fetchPersonalRecord(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        PersonalRecord(
            recordName: "",
            mode: .daily,
            difficulty: .easy,
            bestTimeSeconds: nil,
            totalTimeSeconds: 0,
            completedCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 0),
            completedPuzzleIds: []
        )
    }
    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}

private struct ChromeStubGameCenter: GameCenterClient {
    func authenticate() async throws -> GameCenterAuthState { .unauthenticated }
    func authStateUpdates() async -> AsyncStream<GameCenterAuthState> {
        AsyncStream { $0.finish() }
    }
    func submitScore(
        puzzleId: String,
        elapsedSeconds: Int,
        leaderboardKind: LeaderboardKind
    ) async throws {}
    func submitScore(leaderboardId: String, elapsedSeconds: Int) async throws {}
    func reportAchievement(_ achievement: AchievementProgress) async throws {}
}

@MainActor
private func makeRootViewModel() -> GameRootViewModel<ChromeRoute> {
    GameRootViewModel<ChromeRoute>(
        gameCenter: ChromeStubGameCenter(),
        persistence: ChromeStubPersistence()
    )
}

// MARK: - Suite

@Suite("GameAppKit — TabRootChrome Settings gear (#1020)")
@MainActor
struct TabRootChromeTests {

    @Test("the gear pushes the settings route onto the selected tab")
    func pushesSettingsOntoSelectedTab() {
        let rootViewModel = makeRootViewModel()
        rootViewModel.selectedTab = .practice

        TabRootChrome(rootViewModel: rootViewModel, settingsRoute: ChromeRoute.settings)
            .openSettings()

        #expect(rootViewModel.path(for: .practice) == [.settings])
        #expect(rootViewModel.path(for: .today).isEmpty)
        #expect(rootViewModel.path(for: .progress).isEmpty)
        // A gear tap is a push WITHIN the tab, never a tab switch — Back has to
        // land the player back where they started (§2.1).
        #expect(rootViewModel.selectedTab == .practice)
    }

    /// Every tab's gear pushes onto its own stack, so opening Settings from one
    /// tab leaves the others untouched.
    @Test("each tab's gear pushes onto that tab only")
    func eachTabPushesOntoItsOwnStack() {
        let rootViewModel = makeRootViewModel()
        let chrome = TabRootChrome(rootViewModel: rootViewModel, settingsRoute: ChromeRoute.settings)

        for tab in AppTab.allCases {
            rootViewModel.selectedTab = tab
            chrome.openSettings()
        }

        for tab in AppTab.allCases {
            #expect(rootViewModel.path(for: tab) == [.settings])
        }
    }

    /// The gear stacks onto whatever the tab already had rather than replacing
    /// it — Settings opened from a deep stack must not silently pop it.
    @Test("the push appends to an existing stack")
    func appendsToExistingStack() {
        let rootViewModel = makeRootViewModel()
        rootViewModel.setPath([.board(puzzleId: "p1")], for: .today)

        TabRootChrome(rootViewModel: rootViewModel, settingsRoute: ChromeRoute.settings)
            .openSettings()

        #expect(rootViewModel.path(for: .today) == [.board(puzzleId: "p1"), .settings])
    }

    /// The type annotation IS the assertion: `chromedTabRoots` is declared to
    /// return `ModifiedContent<AnyView, TabRootChrome<Route>>`, so this compiles
    /// only while every tab root carries the gear. One closure serves all three
    /// tabs, so no per-tab path can skip it.
    ///
    /// The body then re-checks the #918 memoization contract still holds through
    /// the chroming wrapper: 3 builder calls, no matter how often the shell asks.
    @Test("chromes every tab root and still builds each exactly once")
    func chromesEveryTabRootOnce() {
        let rootViewModel = makeRootViewModel()
        var callsPerTab: [AppTab: Int] = [:]

        let tabRoot: (AppTab) -> ModifiedContent<AnyView, TabRootChrome<ChromeRoute>> =
            chromedTabRoots(
                rootViewModel: rootViewModel,
                settingsRoute: ChromeRoute.settings
            ) { tab in
                callsPerTab[tab, default: 0] += 1
                return AnyView(Text(tab.rawValue))
            }

        #expect(callsPerTab == [.today: 1, .practice: 1, .progress: 1])

        for _ in 0..<5 {
            for tab in AppTab.allCases {
                _ = tabRoot(tab)
            }
        }

        #expect(callsPerTab == [.today: 1, .practice: 1, .progress: 1])
    }
}
