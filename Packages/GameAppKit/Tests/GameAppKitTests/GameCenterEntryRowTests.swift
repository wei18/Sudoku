// GameCenterEntryRowTests — the #1021 Phase D `Achievements`/`Leaderboards`
// PROGRESS entry points (generalizes #1020 C-36's `AchievementsRowTests`).
//
// What has to survive the generalization is the #685 auth gate: a tap while
// Game Center is signed out raises the shared alert instead of silently
// no-op'ing. Both branches are asserted here through each row's own
// `activate()`, which is exactly what its `Button` calls — for BOTH the
// `.achievements` and `.leaderboards` factory rows.

import Foundation
import Testing
import GameCenterClient
import SudokuGameState
import Persistence
import SudokuEngine
import Telemetry
@testable import GameAppKit

// MARK: - Test route

enum GameCenterEntryTestRoute: Hashable, Sendable {
    case settings
}

// MARK: - Fakes

private actor GameCenterEntryStubPersistence: PersistenceProtocol {
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

private struct GameCenterEntryStubGameCenter: GameCenterClient {
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
) -> GameRootViewModel<GameCenterEntryTestRoute> {
    GameRootViewModel<GameCenterEntryTestRoute>(
        gameCenter: GameCenterEntryStubGameCenter(authResult: .success(authState)),
        persistence: GameCenterEntryStubPersistence()
    )
}

// MARK: - Suite

/// One row-factory per case so every `@Test` below runs against BOTH
/// `Achievements` and `Leaderboards` — the C-36 contract is identical for
/// each, only the row's own copy/icon/id differ.
enum RowKind: CaseIterable, Sendable {
    case achievements
    case leaderboards

    @MainActor
    func make(
        rootViewModel: GameRootViewModel<GameCenterEntryTestRoute>,
        present: @escaping @MainActor () -> Void
    ) -> GameCenterEntryRow<GameCenterEntryTestRoute> {
        switch self {
        case .achievements:
            return GameCenterEntryRow(
                title: "Achievements",
                systemImage: "trophy",
                accessibilityIdentifier: "game.progress.achievements",
                rootViewModel: rootViewModel,
                present: present
            )
        case .leaderboards:
            return GameCenterEntryRow(
                title: "Leaderboards",
                systemImage: "list.number",
                accessibilityIdentifier: "game.progress.leaderboards",
                rootViewModel: rootViewModel,
                present: present
            )
        }
    }
}

@Suite("GameAppKit — GameCenterEntryRow (#1021 Phase D, C-36)")
@MainActor
struct GameCenterEntryRowTests {

    @Test("authenticated: presents the dashboard, raises no alert", arguments: RowKind.allCases)
    func authenticatedPresents(kind: RowKind) async {
        let rootViewModel = makeRootViewModel(
            authState: .authenticated(PlayerSummary(teamPlayerId: "p1", displayName: "Player"))
        )
        await rootViewModel.bootstrap()

        var presented = 0
        let row = kind.make(rootViewModel: rootViewModel, present: { presented += 1 })
        row.activate()

        #expect(presented == 1)
        #expect(rootViewModel.showGameCenterSignedOutAlert == false)
    }

    @Test("signed out: raises the shared alert instead of presenting", arguments: RowKind.allCases)
    func unauthenticatedRaisesAlert(kind: RowKind) async {
        let rootViewModel = makeRootViewModel(authState: .unauthenticated)
        await rootViewModel.bootstrap()

        var presented = 0
        let row = kind.make(rootViewModel: rootViewModel, present: { presented += 1 })
        row.activate()

        #expect(presented == 0)
        #expect(rootViewModel.showGameCenterSignedOutAlert == true)
    }

    /// `.unknown` — auth never resolved — must behave like signed out rather
    /// than silently doing nothing.
    @Test("auth unresolved: still raises the alert, never presents", arguments: RowKind.allCases)
    func unknownAuthRaisesAlert(kind: RowKind) {
        let rootViewModel = makeRootViewModel(authState: .unauthenticated)
        // No bootstrap() — authState stays .unknown.

        var presented = 0
        let row = kind.make(rootViewModel: rootViewModel, present: { presented += 1 })
        row.activate()

        #expect(presented == 0)
        #expect(rootViewModel.showGameCenterSignedOutAlert == true)
    }

    /// The row is a side effect, not a navigation push — tapping it must
    /// leave every tab's stack untouched (mirrors #1020 C-35's HOME card).
    @Test("presenting does not push onto any tab", arguments: RowKind.allCases)
    func presentingDoesNotNavigate(kind: RowKind) async {
        let rootViewModel = makeRootViewModel(
            authState: .authenticated(PlayerSummary(teamPlayerId: "p1", displayName: "Player"))
        )
        await rootViewModel.bootstrap()
        rootViewModel.selectedTab = .progress

        kind.make(rootViewModel: rootViewModel, present: {}).activate()

        #expect(rootViewModel.path(for: .progress).isEmpty)
        #expect(rootViewModel.path(for: .today).isEmpty)
        #expect(rootViewModel.selectedTab == .progress)
    }
}
