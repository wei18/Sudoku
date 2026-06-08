// FakeGameCenterClient — scripted in-memory `GameCenterClient`.
//
// Backs every GameCenterClientTests / SudokuUITests scenario: live GameKit
// is exercised manually in Phase 10 sandbox validation only (plan.md §10.2).
//
// Records every operation the SUT observes so tests can assert on call shape
// (e.g. "Sink only invokes submitScore once for the same puzzleId").

import Foundation
public import GameCenterClient
public import SudokuEngine

public enum FakeGameCenterOperation: Sendable, Equatable, Hashable {
    case authenticate
    case submitScore(puzzleId: String, elapsedSeconds: Int, leaderboardKind: LeaderboardKind)
    case submitRawScore(leaderboardId: String, elapsedSeconds: Int)
    case reportAchievement(achievementId: String, percentComplete: Double)
    case fetchLeaderboardSlice(leaderboardId: String, scope: LeaderboardScope, aroundLocalPlayer: Bool, limit: Int)
    case friendsAuthorizationStatus
    case requestFriendsAuthorization
}

public actor FakeGameCenterClient: GameCenterClient {

    // MARK: - Scripted state

    public private(set) var operations: [FakeGameCenterOperation] = []

    public var authResult: Result<GameCenterAuthState, GameCenterError> = .success(
        .authenticated(PlayerSummary(teamPlayerId: "P0001", displayName: "TestPlayer"))
    )
    public var friendsStatus: FriendsAuthStatus = .authorized
    public var requestFriendsResult: Result<FriendsAuthStatus, GameCenterError> = .success(.authorized)
    public var leaderboardSlice: LeaderboardSlice = LeaderboardSlice(
        leaderboardId: "",
        scope: .globalAllTime,
        entries: [],
        totalPlayerCount: 0,
        fetchedAt: Date(timeIntervalSince1970: 0)
    )
    public var submitScoreError: GameCenterError?
    public var reportAchievementError: GameCenterError?
    public var fetchLeaderboardSliceError: GameCenterError?

    private var authContinuations: [UUID: AsyncStream<GameCenterAuthState>.Continuation] = [:]

    public init() {}

    // MARK: - Scripting helpers

    public func setAuthResult(_ result: Result<GameCenterAuthState, GameCenterError>) {
        self.authResult = result
    }

    public func setFriendsStatus(_ status: FriendsAuthStatus) {
        self.friendsStatus = status
    }

    public func setRequestFriendsResult(_ result: Result<FriendsAuthStatus, GameCenterError>) {
        self.requestFriendsResult = result
    }

    public func setLeaderboardSlice(_ slice: LeaderboardSlice) {
        self.leaderboardSlice = slice
    }

    public func setSubmitScoreError(_ error: GameCenterError?) {
        self.submitScoreError = error
    }

    public func setReportAchievementError(_ error: GameCenterError?) {
        self.reportAchievementError = error
    }

    public func setFetchLeaderboardSliceError(_ error: GameCenterError?) {
        self.fetchLeaderboardSliceError = error
    }

    /// Push an auth state into every active `authStateUpdates()` consumer.
    public func emitAuthState(_ state: GameCenterAuthState) {
        for continuation in authContinuations.values {
            continuation.yield(state)
        }
    }

    // MARK: - GameCenterClient

    public func authenticate() async throws -> GameCenterAuthState {
        operations.append(.authenticate)
        switch authResult {
        case .success(let state): return state
        case .failure(let error): throw error
        }
    }

    public func authStateUpdates() async -> AsyncStream<GameCenterAuthState> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<GameCenterAuthState>.makeStream()
        authContinuations[id] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.unregisterContinuation(id) }
        }
        return stream
    }

    private func unregisterContinuation(_ id: UUID) {
        authContinuations.removeValue(forKey: id)
    }

    public func submitScore(
        puzzleId: String,
        elapsedSeconds: Int,
        difficulty: Difficulty,
        leaderboardKind: LeaderboardKind
    ) async throws {
        operations.append(.submitScore(
            puzzleId: puzzleId,
            elapsedSeconds: elapsedSeconds,
            leaderboardKind: leaderboardKind
        ))
        if let error = submitScoreError { throw error }
    }

    public func submitScore(
        leaderboardId: String,
        elapsedSeconds: Int
    ) async throws {
        operations.append(.submitRawScore(
            leaderboardId: leaderboardId,
            elapsedSeconds: elapsedSeconds
        ))
        if let error = submitScoreError { throw error }
    }

    public func reportAchievement(_ achievement: AchievementProgress) async throws {
        operations.append(.reportAchievement(
            achievementId: achievement.achievementId,
            percentComplete: achievement.percentComplete
        ))
        if let error = reportAchievementError { throw error }
    }

    public func fetchLeaderboardSlice(
        leaderboardId: String,
        scope: LeaderboardScope,
        aroundLocalPlayer: Bool,
        limit: Int
    ) async throws -> LeaderboardSlice {
        operations.append(.fetchLeaderboardSlice(
            leaderboardId: leaderboardId,
            scope: scope,
            aroundLocalPlayer: aroundLocalPlayer,
            limit: limit
        ))
        if let error = fetchLeaderboardSliceError { throw error }
        return leaderboardSlice
    }

    public func friendsAuthorizationStatus() async -> FriendsAuthStatus {
        operations.append(.friendsAuthorizationStatus)
        return friendsStatus
    }

    public func requestFriendsAuthorization() async throws -> FriendsAuthStatus {
        operations.append(.requestFriendsAuthorization)
        switch requestFriendsResult {
        case .success(let status):
            self.friendsStatus = status
            return status
        case .failure(let error):
            throw error
        }
    }
}
