// GKScoreSubmitter — production `LiveGameCenterClient.SubmitScoreHook` backed
// by `GKLeaderboard.submitScore(_:context:player:leaderboardIDs:)`.
//
// #580: the real GameKit submit call. Isolated here (like `GKLeaderboardLoader`
// / `GKAuthDriver`) behind `#if canImport(GameKit)` so the target compiles
// cross-platform; the seconds→centiseconds conversion lives in
// `LiveGameCenterClient.submitScore` and is unit-tested via the injected hook,
// so this file carries only the untestable GameKit boundary (device-verified).

internal import Foundation
#if canImport(GameKit)
internal import GameKit
#endif

public enum GKScoreSubmitter {

    /// Submits the already-converted **centisecond** score to the given
    /// leaderboard for the local player. `context` is unused (0).
    public static let live: LiveGameCenterClient.SubmitScoreHook = { leaderboardId, centiseconds in
        #if canImport(GameKit)
        try await GKLeaderboard.submitScore(
            Int(centiseconds),
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [leaderboardId]
        )
        #else
        _ = (leaderboardId, centiseconds)
        throw GameCenterError.notAuthenticated
        #endif
    }
}
