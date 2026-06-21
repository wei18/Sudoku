// GKAchievementReporter — production `LiveGameCenterClient.ReportAchievementHook`
// backed by `GKAchievement.report(_:)`.
//
// #580: the real GameKit achievement call. Isolated here (like
// `GKScoreSubmitter` / `GKLeaderboardLoader`) behind `#if canImport(GameKit)`.
// `showsCompletionBanner` is true so GameKit shows the unlock banner when the
// achievement reaches 100%; partial progress reports update silently. The
// `(identifier, percentComplete)` mapping is unit-tested via the injected hook,
// so this file carries only the untestable GameKit boundary (device-verified).

internal import Foundation
#if canImport(GameKit)
internal import GameKit
#endif

public enum GKAchievementReporter {

    public static let live: LiveGameCenterClient.ReportAchievementHook = { identifier, percentComplete in
        #if canImport(GameKit)
        let achievement = GKAchievement(identifier: identifier)
        achievement.percentComplete = percentComplete
        achievement.showsCompletionBanner = true
        try await GKAchievement.report([achievement])
        #else
        _ = (identifier, percentComplete)
        throw GameCenterError.notAuthenticated
        #endif
    }
}
