// AppRoute — Minesweeper's navigation destination enum.
//
// Standard-tier scope (2026-06-02): only two stack pushes — a board with a
// chosen difficulty + seed, and the placeholder Settings screen. Daily /
// Practice / Completion / Leaderboard destinations are out of scope until
// Minesweeper's product surface is designed (see follow-up issues).
//
// `Hashable + Sendable` is the minimum SwiftUI's `.navigationDestination(for:)`
// + GameShellUI's `RouteFactory` require. `Codable` is intentionally not
// adopted yet — there is no Minesweeper deep-link spec to round-trip.

public import MinesweeperEngine

public enum AppRoute: Hashable, Sendable {
    case board(difficulty: Difficulty, seed: UInt64)
    case settings
}
