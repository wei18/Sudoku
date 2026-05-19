// GameCenterClient — VM-facing protocol for Game Center integration.
//
// Per design.md §How.3.3. Surface intentionally hides GameKit types so
// that only `Sources/GameCenterClient/Live/*.swift` may `import GameKit`
// (foundations.md §2 framework-import discipline).
//
// All value types are `Sendable + Equatable` for cross-actor passing and
// straightforward test assertions. The protocol itself is `Sendable` so an
// existential `any GameCenterClient` can cross actor boundaries
// (Phase 8 ViewModels, Phase 7.6 GameCenterSink).
//
// Protocol shape note vs design.md §How.3.3:
// - `authenticate()` is `async throws` (returns `GameCenterAuthState`) rather
//   than `async -> AuthState` — the throw lets `LiveGameCenterClient`
//   surface real GameKit auth errors to callers that need them; the
//   non-throwing degraded states (`.unauthenticated`, `.restricted`,
//   `.unavailableInRegion`) are still expressed via the returned enum.
// - `submitScore` takes `puzzleId` + `difficulty` + `LeaderboardKind` rather
//   than a pre-computed leaderboard ID — this keeps the `.v1` suffix logic
//   inside `LeaderboardIDs` (Step 7.3) instead of leaking to call sites.
//   The Phase 8 ViewModels never construct leaderboard IDs directly.

public import Foundation

public protocol GameCenterClient: Sendable {
    /// Run the GameKit authentication handshake exactly once per session.
    /// Returns the resulting auth state (including degraded states).
    func authenticate() async throws -> GameCenterAuthState

    /// Stream of auth state transitions emitted by GameKit (sign-in,
    /// sign-out, region change). VMs `.task`-await this stream.
    func authStateUpdates() async -> AsyncStream<GameCenterAuthState>

    /// Submit a score for a daily puzzle. Implementations map
    /// `puzzleId` + `difficulty` + `leaderboardKind` to the canonical
    /// `.v1`-suffixed leaderboard ID via `LeaderboardIDs`.
    func submitScore(
        puzzleId: String,
        elapsedSeconds: Int,
        difficulty: String,
        leaderboardKind: LeaderboardKind
    ) async throws

    /// Report a single achievement's progress percent (0...100).
    func reportAchievement(_ achievement: AchievementProgress) async throws

    /// Fetch a leaderboard slice in the given scope. `around` lets the
    /// caller request a window centered on a specific player; pass nil
    /// for `globalAllTime`/`globalToday` "top of the world" requests.
    func fetchLeaderboardSlice(
        leaderboardId: String,
        scope: LeaderboardScope,
        around player: String?,
        limit: Int
    ) async throws -> LeaderboardSlice

    /// Current GameKit friends-list authorization status. Step 7.5
    /// requires `.authorized` before issuing a `friendsAllTime` fetch.
    func friendsAuthorizationStatus() async -> FriendsAuthStatus

    /// Trigger the system friends-authorization prompt. The returned
    /// status reflects the user's response.
    func requestFriendsAuthorization() async throws -> FriendsAuthStatus
}

// MARK: - Value types

public enum GameCenterAuthState: Sendable, Equatable, Hashable, Codable {
    case unknown
    case unauthenticated
    case authenticated(PlayerSummary)
    case restricted
    case unavailableInRegion
}

public struct PlayerSummary: Sendable, Equatable, Hashable, Codable {
    /// `GKPlayer.gamePlayerID` — stable across alias / display-name changes.
    /// Mirrored at the protocol surface as `teamPlayerId` so the public
    /// API stays free of GameKit terminology.
    public let teamPlayerId: String
    public let displayName: String

    public init(teamPlayerId: String, displayName: String) {
        self.teamPlayerId = teamPlayerId
        self.displayName = displayName
    }
}

/// v1 leaderboard families. Each maps 1:1 with a `.v1`-suffixed
/// leaderboard ID computed by `LeaderboardIDs`.
public enum LeaderboardKind: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case dailyEasy
    case dailyMedium
    case dailyHard
}

public enum LeaderboardScope: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case globalAllTime
    case globalToday
    case friendsAllTime
}

public struct LeaderboardEntry: Sendable, Equatable, Hashable, Codable {
    public let rank: Int
    public let player: PlayerSummary
    /// Score in elapsed seconds. Lower = better (time-based leaderboard).
    public let score: Int

    public init(rank: Int, player: PlayerSummary, score: Int) {
        self.rank = rank
        self.player = player
        self.score = score
    }
}

public struct LeaderboardSlice: Sendable, Equatable, Hashable, Codable {
    public let leaderboardId: String
    public let scope: LeaderboardScope
    public let entries: [LeaderboardEntry]
    public let totalPlayerCount: Int
    public let fetchedAt: Date

    public init(
        leaderboardId: String,
        scope: LeaderboardScope,
        entries: [LeaderboardEntry],
        totalPlayerCount: Int,
        fetchedAt: Date
    ) {
        self.leaderboardId = leaderboardId
        self.scope = scope
        self.entries = entries
        self.totalPlayerCount = totalPlayerCount
        self.fetchedAt = fetchedAt
    }
}

public struct AchievementProgress: Sendable, Equatable, Hashable, Codable {
    /// Short stable id (e.g. `"first_puzzle"`). The GameKit prefix
    /// `com.wei18.sudoku.achievement.` is prepended at submit time.
    public let achievementId: String
    /// 0...100.
    public let percentComplete: Double

    public init(achievementId: String, percentComplete: Double) {
        self.achievementId = achievementId
        self.percentComplete = percentComplete
    }
}

public enum FriendsAuthStatus: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case notDetermined
    case restricted
    case denied
    case authorized
}

public enum GameCenterError: Error, Sendable, Equatable {
    case notAuthenticated
    case cancelled
    case restricted
    case unavailableInRegion
    case friendsAccessDenied
    case scoreSubmitFailed(reason: String)
    case achievementReportFailed(reason: String)
    case underlying(domain: String, code: Int, description: String)
}
