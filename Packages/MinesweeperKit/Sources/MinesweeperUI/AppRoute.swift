// AppRoute — Minesweeper's navigation destination enum.
//
// #288 / #289 (2026-06-04): MS now opens to a Home mode-card surface (mirror
// of Sudoku's `HomeView`) instead of straight to `NewGameView`. The Home cards
// push these routes:
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
    // #329: `mode` carries daily/practice from the navigation origin (Daily hub
    // → `.daily`, Practice hub / New Game → `.practice`) down to the board so
    // `MinesweeperGameViewModel` can gate the GC daily-board submit to daily
    // wins only — mirroring how Sudoku threads its mode to `GameCenterSink`.
    case board(difficulty: Difficulty, seed: UInt64, mode: GameMode)
    // #386: re-tapping an already-SOLVED daily card pushes this instead of a
    // fresh `.board` — it re-surfaces the player's result (win hero + the
    // daily's leaderboard slice) rather than starting a dead replay (mirrors
    // Sudoku #379). MS stores no elapsed (no save-flow, #284), so the route
    // carries only `difficulty` (→ the daily leaderboard id) and `mode`; the
    // hero time is a placeholder and the real ranked time shows in the slice.
    case completion(difficulty: Difficulty, mode: GameMode)
    // #455 step 4: resume a persisted in-progress board. Carries the CloudKit
    // recordName (the save's identity) + the mode qualifier; the route factory
    // mounts `MinesweeperBoardLoaderView`, which fetches the snapshot and
    // rebuilds the exact board via `MinesweeperSession.restore(from:)`. A
    // fresh `.board` can't express this — it would re-derive a NEW board from
    // the seed instead of replaying the saved reveal/flag state.
    case resumeBoard(recordName: String, mode: GameMode)
    case daily
    case practice
    case settings
}
