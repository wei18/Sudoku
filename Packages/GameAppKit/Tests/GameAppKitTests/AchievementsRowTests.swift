// AchievementsRowTests — the #1020 C-36 Game Center entry point.
//
// C-35 removed HOME's Leaderboard card along with HOME; C-36 adds this row to
// the Progress tab. What has to survive the move is the #685 auth gate: a tap
// while Game Center is signed out raises the shared alert instead of silently
// no-op'ing. Both branches are asserted here through the row's own `activate()`,
// which is exactly what its `Button` calls.

import Foundation
import Testing
import GameCenterClient
import SudokuGameState
import Persistence
import SudokuEngine
import Telemetry
@testable import GameAppKit

// MARK: - Test route

private enum AchievementsTestRoute: Hashable, Sendable {
    case settings
}

// MARK: - Fakes

private actor AchievementsStubPersistence: PersistenceProtocol {
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

private struct AchievementsStubGameCenter: GameCenterClient {
    let authResult: Result<GameCenterAuthState, GameCenterError>

    func authenticate() async throws -> GameCenterAuthState { try authResult.get() }
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
private func makeRootViewModel(
    authState: GameCenterAuthState
) -> GameRootViewModel<AchievementsTestRoute> {
    GameRootViewModel<AchievementsTestRoute>(
        gameCenter: AchievementsStubGameCenter(authResult: .success(authState)),
        persistence: AchievementsStubPersistence()
    )
}

// MARK: - Suite

@Suite("GameAppKit — AchievementsRow (C-36)")
@MainActor
struct AchievementsRowTests {

    @Test("authenticated: presents the dashboard, raises no alert")
    func authenticatedPresents() async {
        let rootViewModel = makeRootViewModel(
            authState: .authenticated(PlayerSummary(teamPlayerId: "p1", displayName: "Player"))
        )
        await rootViewModel.bootstrap()

        var presented = 0
        let row = AchievementsRow(rootViewModel: rootViewModel, present: { presented += 1 })
        row.activate()

        #expect(presented == 1)
        #expect(rootViewModel.showGameCenterSignedOutAlert == false)
    }

    @Test("signed out: raises the shared alert instead of presenting")
    func unauthenticatedRaisesAlert() async {
        let rootViewModel = makeRootViewModel(authState: .unauthenticated)
        await rootViewModel.bootstrap()

        var presented = 0
        let row = AchievementsRow(rootViewModel: rootViewModel, present: { presented += 1 })
        row.activate()

        #expect(presented == 0)
        #expect(rootViewModel.showGameCenterSignedOutAlert == true)
    }

    /// `.unknown` — auth never resolved — must behave like signed out rather
    /// than silently doing nothing. This is the exact state #685 found the
    /// Settings row ignoring entirely; the new entry point must not reintroduce
    /// it.
    @Test("auth unresolved: still raises the alert, never presents")
    func unknownAuthRaisesAlert() {
        let rootViewModel = makeRootViewModel(authState: .unauthenticated)
        // No bootstrap() — authState stays .unknown.

        var presented = 0
        let row = AchievementsRow(rootViewModel: rootViewModel, present: { presented += 1 })
        row.activate()

        #expect(presented == 0)
        #expect(rootViewModel.showGameCenterSignedOutAlert == true)
    }

    /// The row is a side effect, not a navigation push — tapping it must leave
    /// every tab's stack untouched (C-35's HOME card behaved the same way).
    @Test("presenting does not push onto any tab")
    func presentingDoesNotNavigate() async {
        let rootViewModel = makeRootViewModel(
            authState: .authenticated(PlayerSummary(teamPlayerId: "p1", displayName: "Player"))
        )
        await rootViewModel.bootstrap()
        rootViewModel.selectedTab = .progress

        AchievementsRow(rootViewModel: rootViewModel, present: {}).activate()

        #expect(rootViewModel.path(for: .progress).isEmpty)
        #expect(rootViewModel.path(for: .today).isEmpty)
        #expect(rootViewModel.selectedTab == .progress)
    }
}
