// TerminalPersistJoinTests — pins the #823 race: a fast dismiss must not let
// the teardown-triggered `sessionTeardownCount` bump run ahead of an
// in-flight terminal-persist save, but a HUNG save must not block the bump
// forever either.
//
// Two layers:
//   1. `TerminalPersistJoin` in isolation — `awaitPending()` genuinely blocks
//      until the registered task resolves (or the bounded timeout elapses).
//   2. `GameRootViewModel.gameSessionDidTearDown(persistJoin:)` /
//      `dismissGame(persistJoin:)` — the production join point: the counter
//      bump waits on the join, but the call to the method itself is never
//      delayed (mirrors "dismiss() stays instant").
//
// `Gate` below is a continuation-based (not sleep-based) synchronization
// primitive so "has the waiter completed yet" assertions are deterministic —
// no `Task.sleep` timing race on the "still blocked" side. Only the
// hung-task timeout tests use real (short) durations, matching the existing
// `for _ in 0..<N { await Task.yield() }` polling idiom this suite already
// uses elsewhere (`GameRootViewModelTests.dismissGameTriggersResumeRefresh`).

import Foundation
import Testing
import GameCenterClient
import SudokuGameState
import Persistence
import SudokuEngine
@testable import GameAppKit

// MARK: - Gate (continuation-based, deterministic)

private actor Gate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

// MARK: - Minimal GameRootViewModel fakes

private enum JoinTestRoute: Hashable, Sendable {
    case board(puzzleId: String)
}

private actor JoinTestPersistence: PersistenceProtocol {
    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(puzzleId: String, mode: Mode, difficulty: Difficulty) async throws -> GameSessionSnapshot {
        throw PersistenceError.zoneNotProvisioned
    }
    func save(_ snapshot: GameSessionSnapshot, puzzleId: String, mode: Mode, difficulty: Difficulty) async throws {}
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> { [] }
    func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>] { [:] }
    func fetchPersonalRecord(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        PersonalRecord(
            recordName: "", mode: .daily, difficulty: .easy, bestTimeSeconds: nil,
            totalTimeSeconds: 0, completedCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 0), completedPuzzleIds: []
        )
    }
    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}

private struct JoinTestGameCenter: GameCenterClient {
    func authenticate() async throws -> GameCenterAuthState { .unauthenticated }
    func authStateUpdates() async -> AsyncStream<GameCenterAuthState> { AsyncStream { $0.finish() } }
    func submitScore(puzzleId: String, elapsedSeconds: Int, difficulty: Difficulty, leaderboardKind: LeaderboardKind) async throws {}
    func submitScore(leaderboardId: String, elapsedSeconds: Int) async throws {}
    func reportAchievement(_ achievement: AchievementProgress) async throws {}
    func fetchLeaderboardSlice(leaderboardId: String, scope: LeaderboardScope, aroundLocalPlayer: Bool, limit: Int) async throws -> LeaderboardSlice {
        LeaderboardSlice(leaderboardId: leaderboardId, scope: scope, entries: [], totalPlayerCount: 0, fetchedAt: Date(timeIntervalSince1970: 0))
    }
    func friendsAuthorizationStatus() async -> FriendsAuthStatus { .notDetermined }
    func requestFriendsAuthorization() async throws -> FriendsAuthStatus { .notDetermined }
}

// MARK: - TerminalPersistJoin (isolated)

@MainActor
@Suite("TerminalPersistJoin — bounded join (#823)")
struct TerminalPersistJoinTests {

    @Test func awaitPendingReturnsImmediatelyWhenNothingRegistered() async {
        let join = TerminalPersistJoin()
        let start = ContinuousClock.now
        await join.awaitPending()
        #expect(start.duration(to: .now) < .seconds(1))
    }

    /// Acceptance criterion 1: a gated save + `awaitPending()` — the waiter
    /// must NOT resolve before the gate opens.
    @Test func awaitPendingBlocksUntilRegisteredTaskCompletes() async {
        let gate = Gate()
        let join = TerminalPersistJoin(timeout: .seconds(5))
        let saveTask = Task { await gate.wait() }
        join.register(saveTask)

        var resolved = false
        let waiter = Task {
            await join.awaitPending()
            resolved = true
        }

        // Yield repeatedly — with a continuation-based Gate this can never
        // spuriously resolve `resolved`, so this is a deterministic
        // "still blocked" assertion, not a timing race.
        for _ in 0..<20 { await Task.yield() }
        #expect(resolved == false)

        await gate.open()
        await waiter.value
        #expect(resolved == true)
    }

    /// Acceptance criterion 2: a save that NEVER completes must not block
    /// `awaitPending()` forever — it returns once `timeout` elapses.
    @Test func awaitPendingTimesOutOnHungTask() async {
        let join = TerminalPersistJoin(timeout: .milliseconds(50))
        let hungTask = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(30))
        }
        defer { hungTask.cancel() }
        join.register(hungTask)

        let start = ContinuousClock.now
        await join.awaitPending()
        let elapsed = start.duration(to: .now)

        // Bounded well below the hung task's 30s sleep — proves the timeout,
        // not the task, is what unblocked us.
        #expect(elapsed < .seconds(5))
    }

    @Test func registerOverwritesPreviousRegistration() async {
        let join = TerminalPersistJoin(timeout: .seconds(5))
        let firstGate = Gate()
        let first = Task { await firstGate.wait() }
        join.register(first)

        // A second registration (e.g. a later terminal transition) replaces
        // the first — awaitPending must not hang on the now-abandoned first
        // task (which never resolves in this test).
        let second = Task {}
        join.register(second)

        let start = ContinuousClock.now
        await join.awaitPending()
        #expect(start.duration(to: .now) < .seconds(1))

        first.cancel()
    }
}

// MARK: - GameRootViewModel integration

@MainActor
@Suite("GameRootViewModel — terminal-persist join (#823)")
struct GameRootViewModelTerminalPersistJoinTests {

    private func makeVM() -> GameRootViewModel<JoinTestRoute> {
        GameRootViewModel<JoinTestRoute>(
            gameCenter: JoinTestGameCenter(),
            persistence: JoinTestPersistence()
        )
    }

    /// The deterministic race pin required by #823's acceptance sketch: a
    /// gated (hanging) save + an immediate teardown call → the counter bump
    /// (the hub's refresh trigger) waits for the save to land instead of
    /// racing ahead of it.
    @Test func gameSessionDidTearDownDefersCounterUntilSaveLands() async {
        let sut = makeVM()
        let gate = Gate()
        let join = TerminalPersistJoin(timeout: .seconds(5))
        join.register(Task { await gate.wait() })

        sut.gameSessionDidTearDown(persistJoin: join)

        // The call above returns immediately (it only spawns an unstructured
        // Task) — the counter must NOT have bumped yet, since the save is
        // still gated.
        for _ in 0..<20 { await Task.yield() }
        #expect(sut.sessionTeardownCount == 0)

        await gate.open()

        // Poll (mirrors the existing `dismissGameTriggersResumeRefresh`
        // idiom) until the deferred Task lands.
        for _ in 0..<50 where sut.sessionTeardownCount == 0 {
            await Task.yield()
        }
        #expect(sut.sessionTeardownCount == 1)
    }

    /// Acceptance criterion 2 at the production seam: a save that never
    /// completes must not block the hub refresh forever — the counter still
    /// bumps once the join's bounded timeout elapses.
    @Test func gameSessionDidTearDownBumpsAfterTimeoutOnHungSave() async {
        let sut = makeVM()
        let join = TerminalPersistJoin(timeout: .milliseconds(50))
        let hungTask = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(30))
        }
        defer { hungTask.cancel() }
        join.register(hungTask)

        sut.gameSessionDidTearDown(persistJoin: join)

        // `Task.yield()` cooperatively reschedules without consuming
        // wall-clock time, so it can't observe a real-time timeout elapsing
        // (unlike the gate-based tests above, which are signaled, not timed).
        // Poll with short real sleeps instead, well past the 50ms bound.
        for _ in 0..<20 where sut.sessionTeardownCount == 0 {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(sut.sessionTeardownCount == 1)
    }

    /// `dismissGame(persistJoin:)` — the real iOS fullScreenCover entry
    /// point — must never delay its own return waiting on the join; only the
    /// counter bump (and the pre-existing resume refresh) defers.
    @Test func dismissGameNeverBlocksOnPersistJoin() async {
        let sut = makeVM()
        let gate = Gate() // never opened in this test
        let join = TerminalPersistJoin(timeout: .seconds(5))
        join.register(Task { await gate.wait() })

        sut.presentGame(route: .board(puzzleId: "2026-07-16-easy"))

        let start = ContinuousClock.now
        sut.dismissGame(persistJoin: join)
        let elapsed = start.duration(to: .now)

        #expect(elapsed < .milliseconds(200))
        #expect(sut.isGamePresented == false)
        #expect(sut.activeGameRoute == nil)

        await gate.open() // let the background Task resolve so it doesn't leak past the test
    }

    /// No `persistJoin` supplied (the pre-#823 call shape) preserves the
    /// original synchronous, unconditional bump — back-compat for any
    /// callsite without a join point.
    @Test func gameSessionDidTearDownWithoutJoinStaysSynchronous() {
        let sut = makeVM()
        sut.gameSessionDidTearDown()
        #expect(sut.sessionTeardownCount == 1)
    }
}
