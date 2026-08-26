// AppRoute — the canonical navigation destination enum for SudokuUI.
//
// #1020 (design.md §2.1–§2.2): `home` / `daily` / `practice` / `stats` are
// gone — `daily` / `practice` / `stats` are now TAB IDENTITIES
// (`GameShellUI.AppTab.today` / `.practice` / `.progress`), each with its own
// `NavigationStack` path; `home` never pushed and is deleted outright. What
// remains are the destinations that genuinely PUSH onto a tab's stack:
// Board, Completion, Settings. `Hashable + Sendable + Codable` so it can
// drive `NavigationStack(path:)` and be serialized for deep-link
// round-tripping.
//
// Issue #49 (2026-05-20): the `.leaderboard(leaderboardId:)` case was
// removed. The full leaderboard dashboard is Apple's native Game Center
// UI, presented as a modal via `GameCenterDashboard.present(leaderboardId:)`.
// #983 briefly reintroduced an in-app push destination (`.dailyRank`) backed
// by a custom `GameAppKit.DailyRankView` screen; that direction was reverted
// (see #983 follow-up) because the Friends tab it depended on was never
// wired to GameKit. The Progress tab's `AchievementsRow` (#1020, C-36)
// presents Apple's dashboard directly again — there is no route for it.

import Foundation

public enum AppRoute: Hashable, Sendable, Codable {
    case board(puzzleId: String)
    case completion(puzzleId: String, elapsedSeconds: Int, mistakeCount: Int)
    case settings
}
