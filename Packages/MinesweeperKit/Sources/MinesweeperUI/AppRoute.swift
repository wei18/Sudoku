// AppRoute — Minesweeper's navigation destination enum.
//
// #288 / #289 (2026-06-04): MS now opens to a Home mode-card surface (mirror
// of Sudoku's `HomeView`) instead of straight to `NewGameView`. The Home cards
// push these routes:
//   - `.newGame`  → NewGameView (difficulty picker; was the old root content).
//   - `.daily`    → MinesweeperDailyHubView (existed in source but was
//                   unreachable — no AppRoute case wired it).
//   - `.practice` → MinesweeperPracticeHubView (same — now reachable).
//   - `.settings` → placeholder Settings screen.
//   - `.board`    → a board with a chosen difficulty + seed.
//
// Leaderboard is intentionally NOT a route — mirroring Sudoku (#49) it is a
// Game Center modal side-effect, not a stack push. MS has no GC surface yet
// (#291), so the Home Leaderboard card is a disabled stub for now.
//
// `Hashable + Sendable` is the minimum SwiftUI's `.navigationDestination(for:)`
// + GameShellUI's `RouteFactory` require. `Codable` is intentionally not
// adopted yet — there is no Minesweeper deep-link spec to round-trip.

public import MinesweeperEngine

public enum AppRoute: Hashable, Sendable {
    case newGame
    case board(difficulty: Difficulty, seed: UInt64)
    case daily
    case practice
    case settings
}
