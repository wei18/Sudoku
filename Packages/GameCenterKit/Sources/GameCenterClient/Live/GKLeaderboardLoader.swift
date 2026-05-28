// GKLeaderboardLoader — production adapter wrapping
// `GKLeaderboard.loadLeaderboards(IDs:)` + `loadEntries(for:timeScope:range:)`.
//
// Per docs/v1/design.md §How.3.5: the live leaderboard slice is fetched
// from Apple's GameKit dashboard. `LeaderboardSliceService` (in
// `Leaderboard/Slice.swift`) applies the friends-auth precondition before
// forwarding to this loader.
//
// COMPILE-ONLY in this phase — live wire-up is exercised in plan.md
// Phase 10 manual device validation. Unit tests inject
// `FakeLeaderboardLoader` instead.

internal import Foundation
#if canImport(GameKit)
internal import GameKit
#endif

public struct GKLeaderboardLoader: LeaderboardLoader {

    public init() {}

    public func loadSlice(
        leaderboardId: String,
        scope: LeaderboardScope,
        around player: String?,
        limit: Int
    ) async throws -> LeaderboardSlice {
        #if canImport(GameKit)
        let leaderboards = try await GKLeaderboard.loadLeaderboards(IDs: [leaderboardId])
        guard let leaderboard = leaderboards.first else {
            return LeaderboardSlice(
                leaderboardId: leaderboardId,
                scope: scope,
                entries: [],
                totalPlayerCount: 0,
                fetchedAt: Date()
            )
        }
        let playerScope: GKLeaderboard.PlayerScope
        switch scope {
        case .friendsAllTime:
            playerScope = .friendsOnly
        case .globalAllTime, .globalToday:
            playerScope = .global
        }
        let timeScope: GKLeaderboard.TimeScope
        switch scope {
        case .globalToday:
            timeScope = .today
        case .globalAllTime, .friendsAllTime:
            timeScope = .allTime
        }
        // SCOPE NARROWING (issue #140): when `around != nil`, centre the
        // slice on the LOCAL player's rank. GameKit's
        // `loadEntries(for: [GKPlayer], timeScope:)` requires `GKPlayer`
        // instances, but our `around` param is a teamPlayerID string and
        // `GKPlayer.loadPlayers(forIdentifiers:)` only accepts
        // gamePlayerIDs — so cheap conversion is not available. The
        // realistic production use case (CompletionView) is "centre on
        // local player", so `GKLocalPlayer.local` is the correct source
        // here. If a future feature ever needs centring on a different
        // player, file a follow-up issue.
        let centerRank: Int?
        if player != nil {
            // `loadEntries(for: [GKPlayer], timeScope:)` returns
            // `(localPlayerEntry: GKLeaderboard.Entry?, entries: [GKLeaderboard.Entry])`.
            // The local-player entry is what we want for centring.
            let (localPlayerEntry, _) = try await leaderboard.loadEntries(
                for: [GKLocalPlayer.local],
                timeScope: timeScope
            )
            centerRank = localPlayerEntry?.rank
        } else {
            centerRank = nil
        }
        let range = Self.makeRange(centeredOnRank: centerRank, limit: limit)
        let (_, entries, total) = try await leaderboard.loadEntries(
            for: playerScope,
            timeScope: timeScope,
            range: range
        )
        let mapped: [LeaderboardEntry] = entries.map { entry in
            LeaderboardEntry(
                rank: entry.rank,
                player: PlayerSummary(
                    teamPlayerId: entry.player.teamPlayerID,
                    displayName: entry.player.displayName
                ),
                // Score is centiseconds (per §How.3.1 submitScore); project
                // back to seconds for the public slice value.
                score: Int(entry.score / 100)
            )
        }
        return LeaderboardSlice(
            leaderboardId: leaderboardId,
            scope: scope,
            entries: mapped,
            totalPlayerCount: total,
            fetchedAt: Date()
        )
        #else
        _ = (leaderboardId, scope, player, limit)
        throw GameCenterError.notAuthenticated
        #endif
    }

    /// Compute the `NSRange` for the second `loadEntries` call.
    ///
    /// - When `centeredOnRank == nil` (no `around` player, or the local
    ///   player isn't on the board for this scope), return top-N
    ///   anchored at rank 1.
    /// - Otherwise, centre a window of `limit` entries on the rank,
    ///   clamping the start to 1. Window size per side is `limit / 2`
    ///   rounded down (per issue #140 acceptance).
    ///
    /// `internal` so the GameCenterClientTests target can verify it
    /// without standing up a fake `GKLeaderboard`.
    internal static func makeRange(centeredOnRank rank: Int?, limit: Int) -> NSRange {
        let length = max(1, limit)
        guard let rank else {
            return NSRange(location: 1, length: length)
        }
        let window = length / 2
        let start = max(1, rank - window)
        return NSRange(location: start, length: length)
    }
}
