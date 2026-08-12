// GatedLeaderboardGameCenter — a `GameCenterClient` whose `fetchLeaderboardSlice`
// for one specific leaderboard id suspends until the test calls `release()`.
//
// Used by DailyRankViewModelTests to make a fetch stay "in flight" across a
// tab switch so `DailyRankViewModel.commit(_:for:)`'s selection-key guard can
// be exercised deterministically (continuation-gated, no timing/sleep).

import Foundation
public import GameCenterClient

actor GatedLeaderboardGameCenter: GameCenterClient {
    private let authResultValue: GameCenterAuthState
    private var slices: [String: LeaderboardSlice] = [:]
    private var heldLeaderboardId: String?
    private var didEnterHold = false
    private var didRelease = false
    private var enteredHoldContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(localPlayer: PlayerSummary) {
        self.authResultValue = .authenticated(localPlayer)
    }

    func setSlice(_ slice: LeaderboardSlice, for leaderboardId: String) {
        slices[leaderboardId] = slice
    }

    /// Any future fetch for `leaderboardId` suspends until `release()`.
    func hold(leaderboardId: String) {
        heldLeaderboardId = leaderboardId
    }

    /// Suspends until the held fetch has actually started waiting.
    func waitUntilHeld() async {
        if didEnterHold { return }
        await withCheckedContinuation { enteredHoldContinuation = $0 }
    }

    func release() {
        didRelease = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func authenticate() async throws -> GameCenterAuthState { authResultValue }
    func authStateUpdates() async -> AsyncStream<GameCenterAuthState> { AsyncStream { $0.finish() } }
    func submitScore(puzzleId: String, elapsedSeconds: Int, leaderboardKind: LeaderboardKind) async throws {}
    func submitScore(leaderboardId: String, elapsedSeconds: Int) async throws {}
    func reportAchievement(_ achievement: AchievementProgress) async throws {}
    func friendsAuthorizationStatus() async -> FriendsAuthStatus { .authorized }
    func requestFriendsAuthorization() async throws -> FriendsAuthStatus { .authorized }

    func fetchLeaderboardSlice(
        leaderboardId: String,
        scope: LeaderboardScope,
        aroundLocalPlayer: Bool,
        limit: Int
    ) async throws -> LeaderboardSlice {
        if leaderboardId == heldLeaderboardId, !didRelease {
            didEnterHold = true
            enteredHoldContinuation?.resume()
            enteredHoldContinuation = nil
            await withCheckedContinuation { releaseContinuation = $0 }
        }
        return slices[leaderboardId] ?? LeaderboardSlice(
            leaderboardId: leaderboardId,
            scope: scope,
            entries: [],
            totalPlayerCount: 0,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
