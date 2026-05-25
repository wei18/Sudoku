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
        let range = NSRange(location: 1, length: max(1, limit))
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
        _ = (player) // around-player handling is a Phase 10 follow-up.
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
}
