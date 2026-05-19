// LiveGameCenterClient — production `GameCenterClient`.
//
// Coordinates an injected `AuthDriver` (real `GKAuthDriver` in production,
// `FakeAuthDriver` in tests) with the score/achievement/leaderboard APIs.
// Per design.md §How.3.4 the authentication call site is `RootView.task`
// — this actor runs once per session, caches the last observed state, and
// fans subsequent transitions out via `authStateUpdates()`.
//
// `submitScore`, `reportAchievement`, `fetchLeaderboardSlice` and the
// friends-auth pair are wired in subsequent steps (7.3 / 7.4 / 7.5). The
// current file ships authentication only; score/achievement methods throw
// `.notAuthenticated` as a deliberate placeholder until those steps land.

internal import Foundation

public actor LiveGameCenterClient: GameCenterClient {

    private let authDriver: any AuthDriver
    private var cachedState: GameCenterAuthState = .unknown
    private var continuations: [UUID: AsyncStream<GameCenterAuthState>.Continuation] = [:]
    private var observerTask: Task<Void, Never>?

    public init(authDriver: any AuthDriver) {
        self.authDriver = authDriver
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
        observerTask = Task { [authDriver] in
            for await outcome in await authDriver.observeStateChanges() {
                self.handleObservedOutcome(outcome)
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
        difficulty: String,
        leaderboardKind: LeaderboardKind
    ) async throws {
        _ = (puzzleId, elapsedSeconds, difficulty, leaderboardKind)
        // Real implementation lands in 7.3 (live GKLeaderboard submit).
        throw GameCenterError.notAuthenticated
    }

    public func reportAchievement(_ achievement: AchievementProgress) async throws {
        _ = achievement
        throw GameCenterError.notAuthenticated
    }

    public func fetchLeaderboardSlice(
        leaderboardId: String,
        scope: LeaderboardScope,
        around player: String?,
        limit: Int
    ) async throws -> LeaderboardSlice {
        _ = (leaderboardId, scope, player, limit)
        throw GameCenterError.notAuthenticated
    }

    public func friendsAuthorizationStatus() async -> FriendsAuthStatus {
        .notDetermined
    }

    public func requestFriendsAuthorization() async throws -> FriendsAuthStatus {
        throw GameCenterError.friendsAccessDenied
    }
}
