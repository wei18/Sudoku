// Leaderboard slice fetcher — seam over `GKLeaderboard.loadEntries`.
//
// Same shape pattern as AuthDriver (Step 7.2): an internal protocol is
// driven by an injected implementation. Production wires `GKLeaderboardLoader`
// (live, GameKit-imported); tests inject a fake.
//
// Friends-only precondition: `.friendsAllTime` scope MUST be gated on
// `friendsAuthorizationStatus()` returning `.authorized` per design.md
// §How.3.5. The precondition is enforced here (not in the live loader)
// so the fake-driven tests cover it.

internal import Foundation

public protocol LeaderboardLoader: Sendable {
    func loadSlice(
        leaderboardId: String,
        scope: LeaderboardScope,
        around player: String?,
        limit: Int
    ) async throws -> LeaderboardSlice
}

public enum LeaderboardSliceService {
    /// Apply the friends-auth precondition before forwarding to the loader.
    /// `friendsStatus` is captured via callback so the caller (the actor
    /// that owns the friends state — `LiveGameCenterClient` in production)
    /// can return its latest known value.
    public static func fetch(
        loader: any LeaderboardLoader,
        friendsStatus: @Sendable () async -> FriendsAuthStatus,
        requestFriendsAuthorization: @Sendable () async throws -> FriendsAuthStatus,
        leaderboardId: String,
        scope: LeaderboardScope,
        around player: String?,
        limit: Int
    ) async throws -> LeaderboardSlice {
        if scope == .friendsAllTime {
            var status = await friendsStatus()
            if status == .notDetermined {
                // Trigger the system prompt exactly once; the user's
                // response becomes the new status.
                status = try await requestFriendsAuthorization()
            }
            switch status {
            case .authorized: break
            case .denied, .restricted, .notDetermined:
                throw GameCenterError.friendsAccessDenied
            }
        }
        return try await loader.loadSlice(
            leaderboardId: leaderboardId,
            scope: scope,
            around: player,
            limit: limit
        )
    }
}
