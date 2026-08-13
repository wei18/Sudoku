// GameCenterClient — VM-facing protocol for Game Center integration.
//
// Per docs/v1/design.md §How.3.3. Surface intentionally hides GameKit types so
// that only `Sources/GameCenterClient/Live/*.swift` may `import GameKit`
// (foundations.md §2 framework-import discipline).
//
// All value types are `Sendable + Equatable` for cross-actor passing and
// straightforward test assertions. The protocol itself is `Sendable` so an
// existential `any GameCenterClient` can cross actor boundaries
// (Phase 8 ViewModels, Phase 7.6 GameCenterSink).
//
// Protocol shape note vs docs/v1/design.md §How.3.3:
// - `authenticate()` is `async throws` (returns `GameCenterAuthState`) rather
//   than `async -> AuthState` — the throw lets `LiveGameCenterClient`
//   surface real GameKit auth errors to callers that need them; the
//   non-throwing degraded states (`.unauthenticated`, `.restricted`,
//   `.unavailableInRegion`) are still expressed via the returned enum.
// - `submitScore` takes `puzzleId` + `LeaderboardKind` rather than a
//   pre-computed leaderboard ID — this keeps the `.v1` suffix logic inside
//   `LeaderboardIDs` (Step 7.3) instead of leaking to call sites. The Phase 8
//   ViewModels never construct leaderboard IDs directly. `difficulty` used to
//   be a parameter here too, but every conformer discarded it (the caller
//   already resolves `Difficulty → LeaderboardKind` before crossing this
//   boundary — see `GameCenterSink.leaderboardKind(forDifficulty:)`); dropping
//   it removes the `SudokuEngine.Difficulty` leak from this game-agnostic
//   protocol (#947). `AchievementEvaluator` (which re-exported SudokuEngine
//   at module level — the packaging problem tracked as #955) has since
//   moved out of this package into SudokuAppComposition, along with
//   GameCenterSink and SubmitGuards; they were Sudoku-specific, not part
//   of this game-agnostic seam.

public protocol GameCenterClient: Sendable {
    /// Run the GameKit authentication handshake exactly once per session.
    /// Returns the resulting auth state (including degraded states).
    func authenticate() async throws -> GameCenterAuthState

    /// Stream of auth state transitions emitted by GameKit (sign-in,
    /// sign-out, region change). VMs `.task`-await this stream.
    func authStateUpdates() async -> AsyncStream<GameCenterAuthState>

    /// Submit a score for a daily puzzle. Implementations map
    /// `puzzleId` + `leaderboardKind` to the canonical `.v1`-suffixed
    /// leaderboard ID via `LeaderboardIDs`.
    func submitScore(
        puzzleId: String,
        elapsedSeconds: Int,
        leaderboardKind: LeaderboardKind
    ) async throws

    /// Game-agnostic raw submit: hand a fully-formed leaderboard identifier
    /// and an elapsed-seconds score straight to GameKit. Sudoku's typed
    /// `submitScore(puzzleId:…)` above delegates here after computing its
    /// `LeaderboardKind → id` mapping; Minesweeper (and any future game)
    /// calls this directly with its own leaderboard IDs (#291). The
    /// seconds → centiseconds conversion happens inside the implementation,
    /// exactly once, at the GameKit boundary.
    func submitScore(
        leaderboardId: String,
        elapsedSeconds: Int
    ) async throws

    /// Report a single achievement's progress percent (0...100).
    func reportAchievement(_ achievement: AchievementProgress) async throws
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

public enum GameCenterError: Error, Sendable, Equatable {
    case notAuthenticated
    case cancelled
    case restricted
    case unavailableInRegion
    case scoreSubmitFailed(reason: String)
    case achievementReportFailed(reason: String)
    case underlying(domain: String, code: Int, description: String)
}
