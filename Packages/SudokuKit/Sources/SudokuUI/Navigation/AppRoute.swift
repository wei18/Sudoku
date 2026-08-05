// AppRoute — the canonical navigation destination enum for SudokuUI.
//
// Per docs/v1/design.md §How.5.2. Each case maps 1:1 with one of the 7 Views on the
// navigation stack (Root is the container; Home / Daily / Practice / Board /
// Completion / Settings). `Hashable + Sendable + Codable` so it can drive
// `NavigationStack(path:)` and be serialized for deep-link round-tripping.
//
// Issue #49 (2026-05-20): the `.leaderboard(leaderboardId:)` case was
// removed. The full leaderboard dashboard was Apple's native Game Center
// UI, presented as a modal via `GameCenterDashboard.present(leaderboardId:)`.
//
// #983: `.dailyRank` reintroduces a leaderboard destination, but as a real
// in-app push (not a re-add of #49's removed case) — the shared
// `GameAppKit.DailyRankView` screen. `GameCenterDashboard.present()` stays
// reachable from a secondary button ON that screen, not from the Home card.

import Foundation

public enum AppRoute: Hashable, Sendable, Codable {
    case home
    case daily
    case practice
    case board(puzzleId: String)
    case completion(puzzleId: String, elapsedSeconds: Int, mistakeCount: Int)
    case settings
    // #773: Statistics screen (PersonalRecord readout). Pushed from the Home
    // secondary-weight entry below the four mode cards — deliberately NOT a
    // `HomeMode` case (owner adjudication: must not compete with the cards).
    case stats
    // #983: the shared Daily Rank screen, pushed from the Home Leaderboard
    // card (see `SudokuAppComposition/Live.swift`'s `homeModes[.leaderboard]`).
    case dailyRank
}
