// AppRoute — Minesweeper's navigation destination enum.
//
// #1020 (design.md §2.1–§2.2): `daily` / `practice` / `stats` are gone — they
// are now TAB IDENTITIES (`GameShellUI.AppTab.today` / `.practice` /
// `.progress`), each with its own `NavigationStack` path; MS never had a
// `.home` case to begin with (Home was always the universal mode-card
// surface `makeGameApp` built, not a pushed route). What remains are the
// destinations that genuinely PUSH onto a tab's stack: Board,
// ReplayDailyBoard, Completion, ResumeBoard, Settings.
//
// #983 briefly added an in-app push destination (`.dailyRank`) backed by a
// custom `GameAppKit.DailyRankView` screen; that direction was reverted (see
// #983 follow-up) because the Friends tab it depended on was never wired to
// GameKit. The Progress tab's `AchievementsRow` (#1020, C-36) presents
// Apple's native Game Center dashboard directly again — there is no route
// for it.
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
    // Epic 8 (SDD-003): free replay of a failed daily. The seed is the same
    // daily board the player lost on. This route is NEVER scored, NEVER submitted
    // to Game Center, and NEVER saves a new record (no store/recordName). The
    // Failed record from the first attempt is untouched — replay is cosmetic.
    // Separate case (not `.board(mode: .dailyReplay)`) to keep `GameMode` stable
    // and to make the "no persistence, no submit" contract explicit at the route
    // layer rather than a hidden flag on the board VM.
    case replayDailyBoard(difficulty: Difficulty, seed: UInt64)
    // #386: re-tapping an already-SOLVED daily card pushes this instead of a
    // fresh `.board` — it re-surfaces the player's result (win hero + the
    // daily's leaderboard slice) rather than starting a dead replay (mirrors
    // Sudoku #379). MS stores no elapsed (no save-flow, #284), so the route
    // carries only `difficulty` (→ the daily leaderboard id) and `mode`; the
    // hero time is a placeholder and the real ranked time shows in the slice.
    // #826: widened with `day` (a `UTCDay.string(from:)` value, e.g.
    // "2026-07-14") so a past-day dot tap in the #774 week strip can push a
    // review distinct from today's — defaulted to `nil` so every pre-#826
    // call site (today's completed-card re-view) keeps compiling unchanged;
    // `nil` means "today" exactly as before. NOTE: `day` currently has no
    // runtime effect inside `LiveRouteFactory`'s `.completion` case beyond
    // route/Hashable identity — the leaderboard-slice fetch this was meant to
    // key was already deleted in #698 before #826 landed (`MinesweeperCompletionViewModel`
    // is fully synthetic: hardcoded `didWin: true, elapsedSeconds: 0`). Kept
    // per owner-adjudication for future re-wiring if the slice returns.
    case completion(difficulty: Difficulty, mode: GameMode, day: String? = nil)
    // #455 step 4: resume a persisted in-progress board. Carries the CloudKit
    // recordName (the save's identity) + the mode qualifier; the route factory
    // mounts `MinesweeperBoardLoaderView`, which fetches the snapshot and
    // rebuilds the exact board via `MinesweeperSession.restore(from:)`. A
    // fresh `.board` can't express this — it would re-derive a NEW board from
    // the seed instead of replaying the saved reveal/flag state.
    case resumeBoard(recordName: String, mode: GameMode)
    case settings
}
