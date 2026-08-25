// UITestLaunchTargetTests — the #1020 rework of the `-uitest-route` seam.
//
// Both E2E suites launch straight into a screen instead of tapping through the
// app, and two of their keys (`daily`, `practice`) named ROUTES that are tab
// identities now. `UITestLaunchTarget` is what lets one seam express both
// landings; these tests pin that a tab target only selects, a push target
// selects AND pushes, and that a re-fired `onAppear` cannot stack duplicates.

import Foundation
import Testing
import GameCenterClient
import GameShellUI
import SudokuGameState
import Persistence
import SudokuEngine
import Telemetry
@testable import GameAppKit

// MARK: - Test route

private enum LaunchRoute: Hashable, Sendable {
    case settings
    case board(puzzleId: String)
}

// MARK: - Fakes

private actor LaunchStubPersistence: PersistenceProtocol {
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

private struct LaunchStubGameCenter: GameCenterClient {
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
private func makeRootViewModel() -> GameRootViewModel<LaunchRoute> {
    GameRootViewModel<LaunchRoute>(
        gameCenter: LaunchStubGameCenter(),
        persistence: LaunchStubPersistence()
    )
}

@MainActor
private func makeModifier(
    _ rootViewModel: GameRootViewModel<LaunchRoute>
) -> UITestRouteModifier<LaunchRoute> {
    UITestRouteModifier(rootViewModel: rootViewModel, resolve: { _ in nil })
}

// MARK: - Suite

@Suite("GameAppKit — UITestLaunchTarget (#1020)")
@MainActor
struct UITestLaunchTargetTests {

    /// `daily` / `practice` used to be pushable routes; they are tab identities
    /// now, so their landing is a selection with an empty stack behind it.
    @Test("a tab target selects the tab and pushes nothing")
    func tabTargetOnlySelects() {
        let rootViewModel = makeRootViewModel()

        makeModifier(rootViewModel).apply(.tab(.practice))

        #expect(rootViewModel.selectedTab == .practice)
        #expect(AppTab.allCases.allSatisfy { rootViewModel.path(for: $0).isEmpty })
    }

    /// A push has to select its tab too — landing a route on a stack the runner
    /// is not looking at would leave the test staring at the wrong screen.
    @Test("a push target selects the tab AND pushes onto it")
    func pushTargetSelectsAndPushes() {
        let rootViewModel = makeRootViewModel()

        makeModifier(rootViewModel).apply(.push(.settings, tab: .progress))

        #expect(rootViewModel.selectedTab == .progress)
        #expect(rootViewModel.path(for: .progress) == [.settings])
        #expect(rootViewModel.path(for: .today).isEmpty)
    }

    @Test("the push shorthand lands on the tab the app opens on")
    func pushShorthandDefaultsToToday() {
        let rootViewModel = makeRootViewModel()

        makeModifier(rootViewModel).apply(.push(.settings))

        #expect(rootViewModel.selectedTab == .today)
        #expect(rootViewModel.path(for: .today) == [.settings])
    }

    /// `onAppear` can re-fire (size-class change, re-mount). Applying the same
    /// target twice must REPLACE the stack, never append — a doubled entry
    /// would leave the runner one Back tap away from where it expects to be.
    @Test("re-applying replaces the stack instead of stacking duplicates")
    func reapplyingDoesNotStack() {
        let rootViewModel = makeRootViewModel()
        let modifier = makeModifier(rootViewModel)

        modifier.apply(.push(.settings))
        modifier.apply(.push(.settings))

        #expect(rootViewModel.path(for: .today) == [.settings])
    }
}
