// GameRootViewModelTests — bootstrap + resume behavior of the generic Root VM.
//
// #455: resume is now driven by an injected `fetchResume` closure returning
// the game-agnostic `ResumeCandidate<Route>` DTO (not a Sudoku-typed
// `SavedGameSummary`). Tests cover: `fetchResume == nil` (no fetch, nil
// candidate, `resumeTapped()` no-ops), a closure returning a candidate
// (candidate set, `resumeTapped()` appends `candidate.route`), and a throwing
// closure (nil candidate + funneled error). Uses a tiny test `Route` enum.

import Foundation
import Testing
import GameCenterClient
import GameState
import Persistence
import SudokuEngine
import Telemetry
@testable import GameAppKit

// MARK: - Test Route

private enum Route: Hashable, Sendable {
    case board(puzzleId: String)
}

private struct ResumeFetchError: Error {}

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

// MARK: - Tests

private func makeCandidate() -> ResumeCandidate<Route> {
    ResumeCandidate(
        title: "Resume Easy",
        subtitle: "3:21",
        route: .board(puzzleId: "2026-05-19-easy")
    )
}

@MainActor
@Suite("GameRootViewModel — bootstrap + resume")
struct GameRootViewModelTests {

    @Test func bootstrapSetsAuthStateAndFetchesResumeCandidate() async {
        let candidate = makeCandidate()
        let viewModel = GameRootViewModel<Route>(
            gameCenter: StubGameCenter(authResult: .success(.authenticated(
                PlayerSummary(teamPlayerId: "p1", displayName: "Player")
            ))),
            persistence: StubPersistence(),
            fetchResume: { candidate }
        )

        await viewModel.bootstrap()

        #expect(viewModel.authState == .authenticated(
            PlayerSummary(teamPlayerId: "p1", displayName: "Player")
        ))
        #expect(viewModel.resumeCandidate == candidate)
    }

    @Test func authFailureFallsBackToUnauthenticated() async {
        let viewModel = GameRootViewModel<Route>(
            gameCenter: StubGameCenter(authResult: .failure(.cancelled)),
            persistence: StubPersistence(),
            fetchResume: { makeCandidate() }
        )

        await viewModel.bootstrap()

        #expect(viewModel.authState == .unauthenticated)
    }

    @Test func bootstrapIsIdempotent() async {
        let persistence = StubPersistence()
        let viewModel = GameRootViewModel<Route>(
            gameCenter: StubGameCenter(),
            persistence: persistence,
            fetchResume: { makeCandidate() }
        )

        await viewModel.bootstrap()
        await viewModel.bootstrap()

        let count = await persistence.bootstrapCount
        #expect(count == 1)
    }

    @Test func resumeTappedAppendsCandidateRoute() async {
        let candidate = makeCandidate()
        let viewModel = GameRootViewModel<Route>(
            gameCenter: StubGameCenter(),
            persistence: StubPersistence(),
            fetchResume: { candidate }
        )
        await viewModel.bootstrap()

        viewModel.resumeTapped()

        #expect(viewModel.path == [candidate.route])
    }

    @Test func nilFetchResumeSkipsFetchAndNoOpsResume() async {
        let viewModel = GameRootViewModel<Route>(
            gameCenter: StubGameCenter(),
            persistence: StubPersistence()
            // fetchResume omitted (nil) → no resume surface.
        )

        await viewModel.bootstrap()
        #expect(viewModel.resumeCandidate == nil)

        viewModel.resumeTapped()
        #expect(viewModel.path.isEmpty)
    }

    @Test func fetchResumeThrowsLeavesNilAndFunnelsError() async {
        let reporter = FakeErrorReporter()
        let viewModel = GameRootViewModel<Route>(
            gameCenter: StubGameCenter(),
            persistence: StubPersistence(),
            errorReporter: reporter,
            fetchResume: { throw ResumeFetchError() }
        )

        await viewModel.bootstrap()

        #expect(viewModel.resumeCandidate == nil)
        let received = await reporter.received
        #expect(received.contains { $0.source == "GameRootViewModel.bootstrap.resume" })
    }
}
