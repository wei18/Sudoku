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
import SudokuGameState
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

    func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>] { [:] }

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

    // MARK: - #675: in-session resume refresh

    /// `refreshResumeCandidate()` must re-invoke `fetchResume` (not reuse the
    /// value cached by `bootstrap()`) and clear a candidate that has since
    /// been consumed (e.g. the underlying save was `markCompleted`'d).
    @Test func refreshResumeCandidateClearsConsumedCandidate() async {
        let box = FetchResumeBox(initial: makeCandidate())
        let viewModel = GameRootViewModel<Route>(
            gameCenter: StubGameCenter(),
            persistence: StubPersistence(),
            fetchResume: { await box.fetch() }
        )

        await viewModel.bootstrap()
        #expect(viewModel.resumeCandidate == makeCandidate())

        // Simulate the just-finished game's record no longer qualifying as
        // in-progress (completed / abandoned) — the next fetch returns nil.
        await box.setNext(nil)
        await viewModel.refreshResumeCandidate()

        #expect(viewModel.resumeCandidate == nil)
        let callCount = await box.callCount
        #expect(callCount == 2) // bootstrap's fetch + the explicit refresh
    }

    /// `refreshResumeCandidate()` picks up a NEWLY in-progress game too (not
    /// just clearing) — proves it's a real re-fetch, not a one-way latch.
    @Test func refreshResumeCandidatePicksUpNewCandidate() async {
        let box = FetchResumeBox(initial: nil)
        let viewModel = GameRootViewModel<Route>(
            gameCenter: StubGameCenter(),
            persistence: StubPersistence(),
            fetchResume: { await box.fetch() }
        )

        await viewModel.bootstrap()
        #expect(viewModel.resumeCandidate == nil)

        let candidate = makeCandidate()
        await box.setNext(candidate)
        await viewModel.refreshResumeCandidate()

        #expect(viewModel.resumeCandidate == candidate)
    }

    /// `dismissGame()` (the iOS fullScreenCover teardown hook) must trigger
    /// the same refresh — this is the actual #675 production wiring: a game
    /// modal that just completed clears its stale pill without a relaunch.
    @Test func dismissGameTriggersResumeRefresh() async {
        let box = FetchResumeBox(initial: makeCandidate())
        let viewModel = GameRootViewModel<Route>(
            gameCenter: StubGameCenter(),
            persistence: StubPersistence(),
            fetchResume: { await box.fetch() }
        )
        await viewModel.bootstrap()
        #expect(viewModel.resumeCandidate == makeCandidate())

        await box.setNext(nil)
        viewModel.presentGame(route: .board(puzzleId: "2026-05-19-easy"))
        viewModel.dismissGame()

        // `dismissGame()` fires the refresh as an unstructured `Task`; yield
        // the MainActor cooperative pool until it lands.
        for _ in 0..<10 where viewModel.resumeCandidate != nil {
            await Task.yield()
        }

        #expect(viewModel.resumeCandidate == nil)
    }

    // MARK: - #685: shared Game Center signed-out guard

    /// `presentGameCenterOrAlert` is the single guard both the Home
    /// leaderboard card and the Settings Game Center row route through
    /// (#685: the Settings row previously had NO guard at all and silently
    /// no-op'd when signed out). Authenticated → calls `present`, never
    /// raises the alert.
    @Test func presentGameCenterOrAlertPresentsWhenAuthenticated() async {
        let viewModel = GameRootViewModel<Route>(
            gameCenter: StubGameCenter(authResult: .success(.authenticated(
                PlayerSummary(teamPlayerId: "p1", displayName: "Player")
            ))),
            persistence: StubPersistence()
        )
        await viewModel.bootstrap()

        var presented = false
        viewModel.presentGameCenterOrAlert { presented = true }

        #expect(presented == true)
        #expect(viewModel.showGameCenterSignedOutAlert == false)
    }

    /// Unauthenticated → raises the alert flag instead of calling `present`.
    @Test func presentGameCenterOrAlertRaisesAlertWhenUnauthenticated() async {
        let viewModel = GameRootViewModel<Route>(
            gameCenter: StubGameCenter(authResult: .success(.unauthenticated)),
            persistence: StubPersistence()
        )
        await viewModel.bootstrap()

        var presented = false
        viewModel.presentGameCenterOrAlert { presented = true }

        #expect(presented == false)
        #expect(viewModel.showGameCenterSignedOutAlert == true)
    }

    /// `.unknown` (auth never resolved / never bootstrapped) must ALSO raise
    /// the alert, not silently no-op — this is the exact state the Settings
    /// row previously ignored entirely.
    @Test func presentGameCenterOrAlertRaisesAlertWhenAuthStateUnknown() async {
        let viewModel = GameRootViewModel<Route>(
            gameCenter: StubGameCenter(),
            persistence: StubPersistence()
        )
        // No bootstrap() — authState stays .unknown (the default).

        var presented = false
        viewModel.presentGameCenterOrAlert { presented = true }

        #expect(presented == false)
        #expect(viewModel.showGameCenterSignedOutAlert == true)
    }
}

// MARK: - #675 fetchResume test double

/// Mutable box so a test can change what the injected `fetchResume` closure
/// returns BETWEEN calls (proving `refreshResumeCandidate()` genuinely
/// re-fetches instead of reusing `bootstrap()`'s cached result) and count
/// invocations.
private actor FetchResumeBox {
    private var next: ResumeCandidate<Route>?
    private(set) var callCount = 0

    init(initial: ResumeCandidate<Route>?) {
        self.next = initial
    }

    func setNext(_ candidate: ResumeCandidate<Route>?) {
        next = candidate
    }

    func fetch() -> ResumeCandidate<Route>? {
        callCount += 1
        return next
    }
}
