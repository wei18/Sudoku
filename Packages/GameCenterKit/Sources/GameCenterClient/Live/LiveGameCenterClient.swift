// LiveGameCenterClient — production `GameCenterClient`.
//
// Coordinates an injected `AuthDriver` (real `GKAuthDriver` in production,
// `FakeAuthDriver` in tests) with the score/achievement/leaderboard APIs.
// Per docs/v1/design.md §How.3.4 the authentication call site is `RootView.task`
// — this actor runs once per session, caches the last observed state, and
// fans subsequent transitions out via `authStateUpdates()`.
//
// `submitScore` performs the canonical **seconds → centiseconds** conversion
// at the GameKit boundary (per docs/v1/design.md §How.3.1:
// `GameState.elapsedSeconds × 100 → Int64 centiseconds`,
// `ELAPSED_TIME_CENTISECOND` ASC formatter, `mm:ss.SS` display) and
// `reportAchievement` forwards `(identifier, percentComplete)`. Both delegate
// to injectable hooks: production wires `GKScoreSubmitter.live` /
// `GKAchievementReporter.live` (the only files that touch the actual
// `GKLeaderboard.submitScore` / `GKAchievement.report` calls — #580,
// device-verified); unit tests inject spies so the conversion + forwarding are
// tested in isolation. See impl-notes
// `meetings/2026-05-20_submit-score-centisecond.impl-notes.md`. `fetchLeaderboardSlice`
// delegates to `LeaderboardSliceService` (+ `GKLeaderboardLoader`).

internal import Foundation
public import SudokuEngine

public actor LiveGameCenterClient: GameCenterClient {

    /// Test seam: receives the post-conversion **centisecond** value the
    /// client would hand to `GKLeaderboard.submitScore(...)`. Default is a no-op
    /// (so unit tests don't touch GameKit); production injects
    /// `GKScoreSubmitter.live` (#580). Tests inject a spy to assert the
    /// `seconds × 100` conversion happens exactly once, at this boundary.
    public typealias SubmitScoreHook = @Sendable (
        _ leaderboardId: String,
        _ centiseconds: Int64
    ) async throws -> Void

    /// Test seam: receives the `(identifier, percentComplete)` the client would
    /// hand to `GKAchievement.report(...)`. Default is a no-op (so unit tests
    /// constructing the client without GameKit don't fault); production injects
    /// `GKAchievementReporter.live` (#580). Tests inject a spy to assert the
    /// forwarding without standing up GameKit.
    public typealias ReportAchievementHook = @Sendable (
        _ identifier: String,
        _ percentComplete: Double
    ) async throws -> Void

    private let authDriver: any AuthDriver
    private let submitScoreHook: SubmitScoreHook
    private let reportAchievementHook: ReportAchievementHook
    private let leaderboardLoader: any LeaderboardLoader
    private var cachedState: GameCenterAuthState = .unknown
    private var continuations: [UUID: AsyncStream<GameCenterAuthState>.Continuation] = [:]
    private var observerTask: Task<Void, Never>?

    public init(
        authDriver: any AuthDriver,
        submitScoreHook: @escaping SubmitScoreHook = { _, _ in },
        reportAchievementHook: @escaping ReportAchievementHook = { _, _ in },
        leaderboardLoader: any LeaderboardLoader = GKLeaderboardLoader()
    ) {
        self.authDriver = authDriver
        self.submitScoreHook = submitScoreHook
        self.reportAchievementHook = reportAchievementHook
        self.leaderboardLoader = leaderboardLoader
    }

    deinit {
        observerTask?.cancel()
    }

    // MARK: - Authentication

    public func authenticate() async throws -> GameCenterAuthState {
        let outcome = await authDriver.performAuthentication()
        let state = try Self.mapOutcomeToState(outcome)
        cachedState = state
        startObservingIfNeeded()
        return state
    }

    public func authStateUpdates() async -> AsyncStream<GameCenterAuthState> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<GameCenterAuthState>.makeStream()
        continuations[id] = continuation
        if cachedState != .unknown {
            continuation.yield(cachedState)
        }
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        startObservingIfNeeded()
        return stream
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func startObservingIfNeeded() {
        guard observerTask == nil else { return }
        // Per impl-notes 2026-05-20_wave-2-blocker-fixes §B3.
        //
        // Pre-fix: the Task implicitly captured `self` strongly via
        // `self.handleObservedOutcome(outcome)`. The for-await loop
        // never terminates on its own, so the actor could never deinit
        // — permanent retain cycle.
        //
        // Fix: capture `self` weakly. Snapshot `authDriver` (an actor
        // ref, value-like since the property is `let`) into the
        // closure's capture list so the outer for-await can run
        // without an unconditional `self?.` chain. Per iteration, we
        // re-grab a strong `self` via `guard let`; the inner await on
        // a strong reference (NOT an optional weak) avoids the
        // `await self?.X` codegen path that exhibited test-harness
        // pathologies (see §未決) and ensures we either dispatch or
        // exit cleanly when the actor is gone.
        observerTask = Task { [weak self, authDriver] in
            let stream = await authDriver.observeStateChanges()
            for await outcome in stream {
                guard let strongSelf = self else { return }
                await strongSelf.handleObservedOutcome(outcome)
            }
        }
    }

    private func handleObservedOutcome(_ outcome: AuthOutcome) {
        // Observed (post-handshake) outcomes always map to a state — even
        // `cancelled` collapses to `.unauthenticated` because there is no
        // active call to surface the throw to.
        let state: GameCenterAuthState
        switch outcome {
        case .signedIn(let player): state = .authenticated(player)
        case .signedOut, .cancelled, .error: state = .unauthenticated
        case .restricted: state = .restricted
        case .unavailableInRegion: state = .unavailableInRegion
        }
        cachedState = state
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }

    // MARK: - Outcome → state mapping

    /// Maps an auth handshake outcome into either a returnable state or a
    /// thrown error. `cancelled` and `error` are the only outcomes that
    /// throw — everything else is a legitimate "we tried, here is what
    /// we have" state including the degraded ones.
    static func mapOutcomeToState(_ outcome: AuthOutcome) throws -> GameCenterAuthState {
        switch outcome {
        case .signedIn(let player): return .authenticated(player)
        case .signedOut: return .unauthenticated
        case .restricted: return .restricted
        case .unavailableInRegion: return .unavailableInRegion
        case .cancelled: throw GameCenterError.cancelled
        case .error(let message): throw GameCenterError.underlying(domain: "AuthDriver", code: -1, description: message)
        }
    }

    // MARK: - Score / achievement / leaderboard (filled in 7.3 / 7.4 / 7.5)

    public func submitScore(
        puzzleId: String,
        elapsedSeconds: Int,
        difficulty: Difficulty,
        leaderboardKind: LeaderboardKind
    ) async throws {
        _ = (puzzleId, difficulty)
        // Map the Sudoku-typed kind → canonical `.v1` leaderboard id, then
        // delegate to the raw game-agnostic path so the centisecond
        // conversion + hook call site stays single-sourced (#291).
        let leaderboardId = LeaderboardIDs.id(for: leaderboardKind)
        try await submitScore(leaderboardId: leaderboardId, elapsedSeconds: elapsedSeconds)
    }

    public func submitScore(
        leaderboardId: String,
        elapsedSeconds: Int
    ) async throws {
        // Per docs/v1/design.md §How.3.1 (`ELAPSED_TIME_CENTISECOND` formatter):
        // ASC's elapsed-time leaderboards use 1/100-second resolution.
        // Convert seconds → centiseconds at this boundary exactly once
        // (callers + the public protocol stay seconds-only). See impl-notes
        // `meetings/2026-05-20_submit-score-centisecond.impl-notes.md`.
        let centiseconds = Int64(elapsedSeconds) * 100
        try await submitScoreHook(leaderboardId, centiseconds)
    }

    public func reportAchievement(_ achievement: AchievementProgress) async throws {
        // #580: forward to the GameKit reporter seam. The id is already
        // prefixed by GameCenterSink; percentComplete is GameKit's 0–100 scale.
        try await reportAchievementHook(achievement.achievementId, achievement.percentComplete)
    }

    public func fetchLeaderboardSlice(
        leaderboardId: String,
        scope: LeaderboardScope,
        aroundLocalPlayer: Bool,
        limit: Int
    ) async throws -> LeaderboardSlice {
        // Per §How.3.5: delegate the friends-auth precondition + load to
        // LeaderboardSliceService. Closures hop back through self so the
        // friends status reflects this actor's latest known state.
        let loader = leaderboardLoader
        return try await LeaderboardSliceService.fetch(
            loader: loader,
            friendsStatus: { [weak self] in
                await self?.friendsAuthorizationStatus() ?? .notDetermined
            },
            requestFriendsAuthorization: { [weak self] in
                guard let self else { return .notDetermined }
                return try await self.requestFriendsAuthorization()
            },
            leaderboardId: leaderboardId,
            scope: scope,
            aroundLocalPlayer: aroundLocalPlayer,
            limit: limit
        )
    }

    public func friendsAuthorizationStatus() async -> FriendsAuthStatus {
        .notDetermined
    }

    public func requestFriendsAuthorization() async throws -> FriendsAuthStatus {
        throw GameCenterError.friendsAccessDenied
    }
}
