// AppRoute — the canonical navigation destination enum for SudokuUI.
//
// Per design.md §How.5.2. Each case maps 1:1 with one of the 8 Views
// (Root is the container; Home / Daily / Practice / Board / Completion /
// Leaderboard / Settings live on the stack). `Hashable + Sendable +
// Codable` so it can drive `NavigationStack(path:)` and be serialized
// for deep-link round-tripping (e.g. CompletionView → LeaderboardView).

import Foundation

public enum AppRoute: Hashable, Sendable, Codable {
    case home
    case daily
    case practice
    case board(puzzleId: String)
    case completion(puzzleId: String, elapsedSeconds: Int)
    case leaderboard(leaderboardId: String)
    case settings
}
