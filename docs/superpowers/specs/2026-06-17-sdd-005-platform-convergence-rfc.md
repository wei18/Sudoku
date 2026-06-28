# SDD-005 — Platform Convergence: one Game module per game, everything else reusable + DI

**Status:** SHIPPED 2026-06-19 (see AS-BUILT NOTE below) — the body is retained as a historical design snapshot; its "DRAFT / to-do" framing and `[OQ]` markers are NOT unshipped blockers. (#592)
**Date:** 2026-06-17
**Author:** AI Leader (from a working session with the user)
**Related:** SDD-003 (UX refresh), SDD-004 (game 3 / 2048), north-star memory `goal-many-small-games-platform`, the mirror principle (CLAUDE.md prime directive)

> **AS-BUILT NOTE (2026-06-19) — SDD-005 COMPLETE.**
> The Pillar B backbone (GameConfig / makeGameApp / shared GameHomeView) and the
> Pillar A Sudoku renames shipped in PRs #556 / #557. SDD-005 was marked complete
> on 2026-06-19. The "DRAFT / to-do" framing below is **historical** — it reflects
> the design conversation as captured on 2026-06-17. Do not act on open items
> or [OQ] markers without first verifying the current tree.

> This doc is a captured snapshot of a design conversation. It is INTENTIONALLY a
> draft: sections marked **[OQ]** are open questions for the next session. Verify
> every code/file claim against the current tree before acting — line counts and
> file lists drift.

---

## 1. Goal

Make the repo a true **game factory**: the only thing implemented per game is the
**Game module** (gameplay), everything else is a reusable module + DI config.

Target user flow — only `Game(×1)` is per-game:

```
Daily | Practice  →  Difficulty  →  Game (game module × 1, contains gameplay)  →  Completion
        └────────────────────── reusable modules + DI configs ──────────────────────┘
                     (design system / fonts / icons / mode list / routes / flow)
```

### Why (the payoff the user named)
Reduce the time spent **verifying / fixing / clarifying** the same thing twice.
Evidence from the 2026-06-17 session:
- **#544** (resume save broken: etag-less CloudKit save) lived in the **shared**
  `PersistenceKit` gateway → one fix (`.allKeys` last-write-wins) fixed BOTH apps.
- **#536** (Daily Hub infinite spinner) lived in **per-app-duplicated**
  `DailyHubViewModel` + `RouteFactory` → had to be fixed **twice** (Sudoku + MS),
  and **#554** (MS Home ResumePill never surfaces) is the same class: MS wires
  resume *differently* from Sudoku, so one works and the other doesn't, and you
  can't see the divergence because it isn't the same code.

**Thesis:** every per-app-duplicated non-gameplay file is a place where a bug must
be found, fixed, and verified N times instead of once. Converge them.

---

## 2. The three pillars

### Pillar A — Naming conventions (`<Game><Concern>`, 2048 is canonical)

Observed state (verify in `Packages/*/Package.swift`):

| Concern | Sudoku | Minesweeper | **2048 (cleanest)** | Convention |
|---|---|---|---|---|
| Engine | `SudokuEngine` | `MinesweeperEngine` | `Game2048Engine` | `<Game>Engine` ✓ |
| Game state | **`GameState`** ⚠️ | `MinesweeperGameState` | `Game2048GameState` | `<Game>GameState` |
| UI | `SudokuUI` | `MinesweeperUI` | `Game2048UI` | `<Game>UI` ✓ |
| Composition | **`AppComposition`** ⚠️ | `MinesweeperAppComposition` | `Game2048AppComposition` | `<Game>AppComposition` |
| Persistence | **`PuzzleStore`** ⚠️ | `MinesweeperPersistence` | `Game2048Persistence` | `<Game>Persistence` |
| Core pkg | `SudokuCoreKit` | `MinesweeperCoreKit` | `Game2048CoreKit` | `<Game>CoreKit` ✓ |
| Kit pkg | `SudokuKit` | `MinesweeperKit` | `Game2048Kit` | `<Game>Kit` ✓ |

- **Shared platform targets are already consistent** across all three (GameAppKit,
  GameShellKit/GameShellUI, PersistenceKit/Persistence, AppMonetizationKit/
  AdsAdMob/IAPStoreKit2/MonetizationCore/MonetizationUI, GameCenterKit/
  GameCenterClient, RemindersKit, GameAudioKit/GameAudio, TelemetryKit,
  SettingsKit/SettingsUI, DeterminismKit, TimeKit). ✅
- **Irony:** the *reference* impl (Sudoku) is the one that drifted — it predates the
  convention MS + 2048 later settled on. 2048 (newest, most platform-aware) is the
  cleanest template.

**Actions:**
- Adopt `2048` as the **canonical target/file shape** for a game.
- **Rename Sudoku targets** to match: `GameState → SudokuGameState`,
  `AppComposition → SudokuAppComposition`, `PuzzleStore → SudokuPersistence`.
  (Mechanical but wide — touches imports across SudokuKit + tests + Tuist. Do as
  its own PR with `swift build` + snapshot gate.)
- **File-naming inside `<Game>UI`:** MS prefixes every file `Minesweeper*`; Sudoku
  prefixes none. The target already namespaces, so pick ONE convention and pin it.
  **[OQ-A1]** prefix-none (shorter; relies on target name) vs prefix-all (greppable).
  Leader leans prefix-none for `<Game>UI` internals; revisit.

### Pillar B — Composition is a TEMPLATE, not per-app code

The composition *shape* must be symmetric. Today it is NOT:
- Sudoku: `AppComposition/Live.swift` (resume + audio wired inline).
- MS: `MinesweeperAppComposition/Live.swift` **+ `Live+Resume.swift` + `Live+Audio.swift`
  + `LiveRouteFactory.swift` + `LiveRouteFactory+Helpers.swift`**.

The very fact that **MS has a `Live+Resume.swift` and Sudoku doesn't** is the drift:
the same seam (resume) is wired by *different code* in each app. That asymmetry is
exactly how #554 happened.

**Target:** a single shared composition builder, per-app reduced to a config value.

```swift
// GameAppKit (one place, all games):
@MainActor func makeGameApp(config: GameConfig) -> some View
// — wires resume, audio, telemetry, GameCenter, persistence, monetization,
//   reminders, route factory ONCE, identically for every game.

// per-app (App/<Game>/...): only declares differences, no wiring logic:
let SudokuConfig = GameConfig( /* see §4 */ )
@main struct SudokuApp: App { var body: some Scene { WindowGroup { makeGameApp(config: SudokuConfig) } } }
```

Consequence: there is **no place** for an asymmetric `Live+Resume.swift` — resume
wiring exists only in `makeGameApp`; the app supplies the `resumeMapping` value.
Seams are structurally symmetric → #554-class "wired differently per app" bugs are
designed out.

**[OQ-B1]** How much of the current per-app `Live.swift` is genuinely game-specific
vs boilerplate? Audit which injected values are真正 per-game (engine, board view,
mode cards, AdMob IDs, CK config, GC config, theme/fonts/icons, resume mapping,
audio events) vs which are identical wiring. The identical wiring is what moves
into `makeGameApp`.

### Pillar C — Shared UI extraction (the non-gameplay screens)

The non-gameplay screens are game-agnostic and should render from config, not be
re-implemented per app.

---

## 3. Drift audit (Sudoku ↔ Minesweeper), 2026-06-17

> Verify against `find Packages/{SudokuKit,MinesweeperKit}/Sources -name '*.swift'`.

### 🔴 Per-app duplicated → EXTRACT to shared + DI

| Concern | Sudoku | Minesweeper | Note |
|---|---|---|---|
| Home (4-mode menu + ResumePill) | `Home/HomeView` + `HomeViewModel` | `Home/MinesweeperHomeView` + `…ViewModel` | game-agnostic; **#554 lives here** |
| Daily hub VM | `Daily/DailyHubViewModel` | `Daily/MinesweeperDailyHubViewModel` | near-identical; **#536 fixed in BOTH** |
| Daily hub View | `Daily/DailyHubView` | `Daily/MinesweeperDailyHubView` | shell shared (`DailyHubShellView`), wrappers drift |
| Practice hub | `Practice/PracticeHubView` + VM | `Practice/MinesweeperPracticeHubView` | parallel |
| Completion wrapper | `Completion/CompletionView` + VM | `Completion/MinesweeperCompletionView` + VM | `CompletionScreen` shared, wrappers drift |
| Settings wrapper | `Settings/SettingsView` + VM | `SettingsView` | SettingsKit shared, wrappers drift |
| Leaderboard / GC dashboard | `Leaderboard/GameCenterDashboard` | `Leaderboard/MinesweeperGameCenterDashboard` + `MinesweeperLeaderboardID` | dashboard game-agnostic; only IDs differ = DI |
| Route + factory | `Navigation/AppRoute` + `RouteFactory` | `AppRoute` + `LiveRouteFactory` + `+Helpers` | parallel; **#536 root cause here** |
| Root wrapper | `Root/RootView` (+ `RootViewModel`=typealias) | `MinesweeperRoot` (+ `MinesweeperRootViewModel`) | thin shells over shared `GameRoot`; near-identical |
| NearWin DEBUG hooks | `SudokuNearWinBoard/Modifier` | `MinesweeperNearWin*` | parallel test hooks |
| Composition | `AppComposition/Live` (+Preview+…) | `MinesweeperAppComposition/Live` (+Audio+Resume+RouteFactory…) | **Pillar B** |
| Reminders glue | `Reminders/ReminderPrimerCoordinator` + `…SettingsStore` | (wired in MS Live) | check parity |
| ATT primer | `Monetization/ATTPrimerCoordinator` + `…Sheet` | (MS lacks ATTPrimerCoordinator — memory 6141) | **drift: MS missing ATT primer** |

### 🟢 Legitimately per-game (the Game module × 1) → KEEP

- Engine + rules: `SudokuEngine` / `MinesweeperEngine` / `Game2048Engine`,
  `PuzzleStore` (Sudoku) / `MinesweeperDailyProvider` / `Game2048` daily.
- Board rendering: `Board/BoardView` + `BoardCellView` + `DigitPadView` vs
  `MinesweeperBoardView` + `MinesweeperCellButton` vs 2048 board.
- Gameplay VM: `GameViewModel` / `MinesweeperGameViewModel` / `Game2048GameViewModel`.
- Cell theme tokens: `Theme/CellTokens` / `MinesweeperCellTokens`.
- Game-specific persistence MAPPING (snapshot ↔ record): `SavedGameMapper` (Sudoku),
  `MinesweeperSavedGameStore` payload, etc. — the *gateway* is shared, the field
  mapping is per-game.

### ✅ Already shared (do not touch — reference for the pattern)

GameAppKit (`GameRootViewModel<Route>`, `GameRoot`, `ResumeCandidate`, `ResumePill`),
GameShellKit (`DailyHubShellView`, `RootShellView`, `NavigationStackHost`,
`CompletionScreen`, `HubLoadState`, `RouteFactory` protocol), SettingsKit,
AppMonetizationKit, PersistenceKit, GameCenterKit, RemindersKit, GameAudioKit,
TelemetryKit, DeterminismKit, TimeKit.

---

## 4. `GameConfig` field draft  **[OQ-C1: this is the crux — refine next session]**

The single per-game DI value `makeGameApp(config:)` consumes. First-cut fields:

```
GameConfig<Route> {
  // Identity / naming
  appName, bundleId, ckConfig (PrivateCKConfig), gcConfig (leaderboard/achievement IDs)

  // Design system (DI — "diverse design systems, fonts, icons")
  theme (color tokens), fonts, iconSet, appIcon

  // Navigation
  routes: [Route] + a route→destination factory (replaces per-app RouteFactory)
  modeCards: [HomeModeCard]  // Daily / Practice / Leaderboard / Settings + per-game extras

  // Gameplay injection (the per-game Game module)
  makeBoardView: (puzzleId/seed/difficulty) -> AnyView
  makeGameViewModel: ...
  difficulties: [Difficulty-like]
  puzzleProvider / dailyProvider

  // Persistence mapping (game-specific snapshot ↔ RecordPayload)
  savedGameMapping, resumeMapping (-> ResumeCandidate<Route>)

  // Audio events, monetization (AdMob IDs already via xcconfig $() — keep secret-injected)
  audioEvents, monetization config
}
```

Open: how to keep this CloudKit-free / GameShellKit-zero-dep clean (closures, not
concrete deps, as the existing seams already do).

---

## 5. Extraction / migration roadmap (prioritized by drift pain)

1. **Pillar B backbone — `GameConfig` + `makeGameApp(config:)`** in GameAppKit.
   Subsumes Live.swift / Live+Resume / Live+Audio / RouteFactory per-app shapes.
   Migrate Sudoku first (reference), then MS, then 2048. Deletes MS's
   `Live+Resume.swift` / `Live+Audio.swift` / `LiveRouteFactory*` asymmetry.
2. **Home** → shared `GameHomeView(config)` consuming `modeCards` + the shared
   ResumePill. **Fixes #554** (one Home, wired once) and removes the Home drift.
3. **DailyHub VM** → shared generic `DailyHubViewModel<Route>` (the logic is the
   same; only the trio source + completion fetch differ — inject them). Removes the
   #536 "fix twice" surface.
4. **RouteFactory** → generated from `config.routes` (the #536 root); per-app factory
   files deleted.
5. **Leaderboard / Completion / Settings wrappers** → shared views taking config
   (leaderboard IDs, completion copy, settings sections are already SettingsKit).
6. **Naming alignment (Pillar A)** — rename Sudoku targets to `<Game><Concern>`;
   pin the file-naming convention. Can land early (mechanical) or alongside each
   extraction.
7. **Composition acceptance** — MS's per-app non-gameplay file count collapses
   toward `{engine, board, cell tokens, one GameConfig}`.

Each step: extract reusable target → migrate one app to consume → delete the app's
duplicate → shared test covers it → snapshot gate green.

---

## 6. Known problems / bugs to fold in (open as of 2026-06-17)

- **#554** — MS Home ResumePill never surfaces. Rendering (`GameRoot`) + wiring
  (`fetchResume`) are shared/correct; MS save trigger / `latestInProgress` is the
  suspect. Pillar B + Pillar C (shared Home + shared composition) likely dissolve it.
- **#552** — PersonalRecord best-time can clobber under multi-device race after
  #544's `.allKeys`. Scope `.allKeys` to SavedGame; keep optimistic concurrency for
  PersonalRecord (gateway save-policy parameter).
- **Dead conflict path** — after #544's last-write-wins, `SavedGameStore` RetryHarness
  + ConflictResolver merge is unreachable in production; remove or repurpose.
- **MS missing ATTPrimerCoordinator** (memory 6141) — monetization drift.
- **Telemetry parity** — both apps DO wire OSLog telemetry into their stores
  (Sudoku `Live.swift:51`, MS `Live.swift:42` + store at `:271`); earlier "MS
  telemetry not wired" was a misread. Keep as a parity check, not a bug.

---

## 7. Acceptance criteria

> **AS-BUILT (2026-06-28 audit).** Verified against the current tree: C1, C2, C5
> met; C3 met **as revised**; C4 met structurally, pending empirical proof.
> - **C1** ✓ — composition roots are thin mirrors (MS 127 / 2048 102 LOC; Sudoku
>   229, carrying its extra monetization/ATT/error-reporter surface). Home (#557),
>   DailyHub two-phase skeleton (#558), board redirect (#559), GC dashboard (#560)
>   are all shared; per-app delta is `GameConfig` values + `Live.swift` DI values.
> - **C2** ✓ — `Sudoku{UI,Persistence,AppComposition}` · `Minesweeper*` ·
>   `Game2048*`; no legacy `GameState` / `AppComposition` / `PuzzleStore`.
> - **C3 — REVISED during execution (#559).** `Live+Resume.swift` / `Live+Audio.swift`
>   are gone and all three roots compose via `makeGameApp` ✓. But a per-app
>   **`LiveRouteFactory` legitimately remains**: its `view(for:)` builds gameplay
>   screens and the route enums differ per game, so it is *not* drift. The genuinely
>   shared scaffolding (the `RouteFactory` protocol + `GameBoardRedirect` /
>   `boardDestination`) was extracted to GameAppKit/GameShellUI. Read this criterion
>   as "no per-app **composition** / `Live+Resume` / `Live+Audio`", **not** "no per-app
>   RouteFactory". (Recurring SDD §5 lesson: per-game `view`/VM/routes are legit
>   gameplay; extract only the shared bug-prone scaffolding.)
> - **C4** — structurally met (no per-app Home/Root/HomeView remains; the shared
>   `GameHomeView` + `GameRootViewModel<Route>` serve all three), but **not yet
>   empirically proven** — that proof is scaffolding game 4 under epic **#479**.
> - **C5** ✓ — each migration PR reported 0 snapshot-pixel moves; #554 CLOSED and
>   sim-verified (#577).

- `diff` of the **non-gameplay** source between games trends to ~empty (only
  `GameConfig` values differ).
- Target/file naming matches the `<Game><Concern>` table for all games incl. 2048.
- No per-app `Live+Resume.swift` / `Live+Audio.swift` / per-app `RouteFactory`
  remains — composition is `makeGameApp(config:)` everywhere.
- A new game (game 4) = one `GameConfig` + engine + board + tokens; no copied
  composition or non-gameplay UI.
- All existing snapshot baselines unchanged where behaviour is unchanged; #554
  resolved (MS Home pill works).

---

## 8. Open questions for the next session

- **[OQ-A1]** ~~file-naming inside `<Game>UI`: prefix-none vs prefix-all.~~ **RESOLVED: prefix-none.** Sudoku's `SudokuUI` source files carry no per-file prefix (e.g. `GameViewModel.swift`, not `SudokuGameViewModel.swift`). The `<Game>` prefix is already encoded at the *target/module* level (`SudokuUI`, `MinesweeperUI`). Adding a redundant per-file prefix inside the module would be verbose without adding disambiguation value. No file churn required for Pillar A; existing SudokuUI filenames are conformant.
- **[OQ-B1]** audit which `Live.swift` injected values are genuinely per-game.
- **[OQ-C1]** finalize `GameConfig` fields + keep it dep-clean (closures over deps).
- Sequencing: land Pillar A (rename) early as a mechanical PR, or bundle per extraction?
- Does 2048 (pre-ship) become the literal "new-game scaffold/template" source?
- Should this be one epic issue with per-pillar sub-issues, or per-step PRs off this SDD?

---

*Captured 2026-06-17 at the end of a long session (#536/#539/#540/#541/#544 fixes +
skills + Phase-3 sim audit). Next context: refine §4 `GameConfig`, confirm the drift
audit against the current tree, and turn §5 into tracked work.*

*As-built closure (2026-06-28): all of the above "next context" work is done — §4
`GameConfig` shipped (#556), the drift audit was confirmed per-surface during #558–#560,
and §5 became the #479-tracked roadmap (#556–#561 / #572 / #575 / #577). SDD-005 is
COMPLETE; see the §7 as-built audit note. The only forward thread is empirical C4 proof
via the #479 new-game scaffold.*
