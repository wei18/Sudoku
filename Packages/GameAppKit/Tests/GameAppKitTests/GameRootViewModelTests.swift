// GameRootViewModelTests — bootstrap + resume behavior of the generic Root VM.
//
// Mirrors Sudoku's RootViewTests bootstrap/resume assertions against a tiny
// test `Route` enum, plus the `supportsResume: false` path (skip the fetch +
// no-op `resumeTapped()`).

import Foundation
import Testing
import GameCenterClient
import GameState
import Persistence
import SudokuEngine
@testable import GameAppKit

// MARK: - Test Route

private enum Route: Hashable {
    case board(puzzleId: String)
}

// MARK: - Fakes

private actor StubPersistence: PersistenceProtocol {
    var resumeCandidate: SavedGameSummary?
    private(set) var bootstrapCount = 0

    init(resumeCandidate: SavedGameSummary? = nil) {
        self.resumeCandidate = resumeCandidate
    }

    func bootstrap() async throws { bootstrapCount += 1 }

    func latestInProgress() async throws -> SavedGameSummary? { resumeCandidate }

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

    func fetchPersonalRecord(
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> PersonalRecord {
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

private struct StubGameCenter: GameCenterClient {
    let authResult: Result<GameCenterAuthState, GameCenterError>

    init(authResult: Result<GameCenterAuthState, GameCenterError> = .success(.unauthenticated)) {
        self.authResult = authResult
    }

    func authenticate() async throws -> GameCenterAuthState {
        try authResult.get()
    }

    func authStateUpdates() async -> AsyncStream<GameCenterAuthState> {
        AsyncStream { $0.finish() }
    }

    func submitScore(
        puzzleId: String,
        elapsedSeconds: Int,
        difficulty: Difficulty,
        leaderboardKind: LeaderboardKind
    ) async throws {}

    func submitScore(leaderboardId: String, elapsedSeconds: Int) async throws {}

    func reportAchievement(_ achievement: AchievementProgress) async throws {}

    func fetchLeaderboardSlice(
        leaderboardId: String,
        scope: LeaderboardScope,
        aroundLocalPlayer: Bool,
        limit: Int
    ) async throws -> LeaderboardSlice {
        LeaderboardSlice(
            leaderboardId: leaderboardId,
            scope: scope,
            entries: [],
            totalPlayerCount: 0,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func friendsAuthorizationStatus() async -> FriendsAuthStatus { .notDetermined }

    func requestFriendsAuthorization() async throws -> FriendsAuthStatus { .notDetermined }
}

private func makeSummary() -> SavedGameSummary {
    SavedGameSummary(
        recordName: "saved-2026-05-19-easy",
        puzzleId: "2026-05-19-easy",
        mode: .daily,
        difficulty: .easy,
        lastModifiedAt: Date(timeIntervalSince1970: 1_715_000_000),
        elapsedSeconds: 201,
        status: "inProgress",
        generatorVersion: 1
    )
}

// MARK: - Tests

@MainActor
@Suite("GameRootViewModel — bootstrap + resume")
struct GameRootViewModelTests {

    @Test func bootstrapSetsAuthStateAndFetchesResumeCandidate() async {
        let summary = makeSummary()
        let viewModel = GameRootViewModel<Route>(
            gameCenter: StubGameCenter(authResult: .success(.authenticated(
                PlayerSummary(teamPlayerId: "p1", displayName: "Player")
            ))),
            persistence: StubPersistence(resumeCandidate: summary),
            resumeRoute: { Route.board(puzzleId: $0.puzzleId) }
        )

        await viewModel.bootstrap()

        #expect(viewModel.authState == .authenticated(
            PlayerSummary(teamPlayerId: "p1", displayName: "Player")
        ))
        #expect(viewModel.resumeCandidate == summary)
    }

    @Test func authFailureFallsBackToUnauthenticated() async {
        let viewModel = GameRootViewModel<Route>(
            gameCenter: StubGameCenter(authResult: .failure(.cancelled)),
            persistence: StubPersistence(),
            resumeRoute: { Route.board(puzzleId: $0.puzzleId) }
        )

        await viewModel.bootstrap()

        #expect(viewModel.authState == .unauthenticated)
    }

    @Test func bootstrapIsIdempotent() async {
        let persistence = StubPersistence()
        let viewModel = GameRootViewModel<Route>(
            gameCenter: StubGameCenter(),
            persistence: persistence,
            resumeRoute: { Route.board(puzzleId: $0.puzzleId) }
        )

        await viewModel.bootstrap()
        await viewModel.bootstrap()

        let count = await persistence.bootstrapCount
        #expect(count == 1)
    }

    @Test func resumeTappedAppendsResumeRoute() async {
        let summary = makeSummary()
        let viewModel = GameRootViewModel<Route>(
            gameCenter: StubGameCenter(),
            persistence: StubPersistence(resumeCandidate: summary),
            resumeRoute: { Route.board(puzzleId: $0.puzzleId) }
        )
        await viewModel.bootstrap()

        viewModel.resumeTapped()

        #expect(viewModel.path == [.board(puzzleId: summary.puzzleId)])
    }

    @Test func supportsResumeFalseSkipsFetchAndNoOpsResume() async {
        let summary = makeSummary()
        let viewModel = GameRootViewModel<Route>(
            gameCenter: StubGameCenter(),
            persistence: StubPersistence(resumeCandidate: summary),
            supportsResume: false,
            resumeRoute: { Route.board(puzzleId: $0.puzzleId) }
        )

        await viewModel.bootstrap()
        #expect(viewModel.resumeCandidate == nil)

        viewModel.resumeTapped()
        #expect(viewModel.path.isEmpty)
    }
}
