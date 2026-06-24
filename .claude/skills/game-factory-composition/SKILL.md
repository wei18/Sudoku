---
name: game-factory-composition
description: The shared composition template that lets multiple games (Sudoku / Minesweeper / Tiles2048) share ONE live stack — `GameConfig<Route>` + `makeGameApp(config:)` in GameAppKit, `<Game><Concern>` target naming, and shared non-gameplay UI (Home / DailyHub skeleton / board-redirect / GC dashboard). Only the Game module is per-game; everything else is reusable module + DI config. Invoke when adding a new game, migrating a game's composition root, deciding what is shared vs per-game, writing a `GameConfig`, or when asked "how do I bootstrap game N / why is there a makeGameApp".
---

# Game Factory Composition

## When to invoke

- Bootstrapping a **new game** (the "game N" / new-game-scaffold path, #479/#501).
- Migrating a game's composition root onto the shared backbone.
- Deciding whether a surface is **shared** or legitimately **per-game**.
- Writing or reviewing a `GameConfig<Route>` / a `makeGameApp` call site.
- Reviewing a PR that touches `GameAppKit` composition or adds a per-game
  `Live+*.swift` wrapper (the latter is usually drift — see below).
- User asks "how do I add a third/fourth game", "what does makeGameApp wire",
  "what stays per-game".

This is the **shipped** shape of SDD-005 platform convergence (all 3 games
migrated, 2026-06-19). The SDD's *future* DI-config refinements are not yet here;
this skill describes only what is live in `GameAppKit` today.

## The prime shape

> Only the **Game module** is per-game. Everything else = reusable module + DI
> config. A 4th game ≈ fill one `GameConfig` + supply engine / board / tokens.

Payoff: fix/verify a bug **once** in the shared path, not per-app. Proven both
ways — #544 fixed in the shared gateway fixed both apps; #536/#554 lived in
per-app-duplicated code and had to be fixed twice. The mirror principle
(`minesweeper-mirrors-sudoku`) is enforced *structurally* here, not by discipline.

## Three pillars

### A. Naming — `<Game><Concern>` targets

- Targets are `SudokuGameState` / `SudokuAppComposition` / `SudokuPersistence`,
  `Minesweeper…`, `Game2048…`. **2048 is the canonical clean shape**; Sudoku was
  the drifted one and was renamed (#561/#562).
- `<Game>UI` internals are **prefix-none** (don't over-prefix every file; MS
  historically over-prefixed, Sudoku didn't — settle on prefix-none).

### B. Composition-as-template — `GameConfig` + `makeGameApp`

- `GameConfig<Route>` (in `GameAppKit/GameConfig.swift`) carries **per-game
  content only** (subsystem, ckConfig, removeAdsProductId, theme, title, tints,
  audio key prefix, reminder copy, `homeModes`) **plus builder closures**
  (`makeRouteFactory`, `fetchResume`, `makeCompletionSinks`, …) that receive the
  wired `GameDeps` bag.
- `makeGameApp(config:)` / `makeGameAppWithDeps(config:)` wire the **entire**
  game-agnostic live stack once and return a ready-to-mount `View`. Wiring order:
  `1` Telemetry (+MetricKit) → `2` ErrorReporter → `3` GameCenter → `4`
  Persistence → `5` Monetization (AdGate/adProvider/IAP/Toast/controller) → `6`
  Audio → `7` ATT primer → `8` Reminders → `9` `GameDeps` assembled → `10`
  rootVM + routeFactory + `GameRoot`.
- A game's `AppComposition.live()` becomes a thin shell: build a `GameConfig`,
  call `makeGameAppWithDeps`, mount `wired.view`. **The existence of per-game
  `Live+Resume.swift` / `Live+Audio.swift` / asymmetric `Live*` wrappers IS the
  drift** this kills — if a migration leaves them, it's not done.
- Dep direction: `GameShellKit`/`GameShellUI` stay **zero-dep**; all live seams
  are imported in `GameAppKit`. `GoogleMobileAds` stays behind AdsAdMob's bridge;
  `CKContainer` stays lazy (`PrivateCKGatewayFactory`).

### C. Shared non-gameplay UI (all consume the config)

- **Home** — universal `GameHomeView` + `GameHomeViewModel<Route>`, built from
  `config.homeModes`; retired each game's bespoke `RootView`/`HomeView`/VM (#557).
  Universal ResumePill + ATT primer mount live here (closed #554).
- **DailyHub** — the two VMs are legitimately gameplay-divergent; only the
  bug-prone **two-phase-load skeleton** (`performDailyBootstrap`) is shared in
  GameShellUI (#558).
- **Board redirect** — only the genuinely-shared #491 two-context decision
  (`boardDestination(route:path:…)`) is extracted to GameAppKit (#559); `view(for:)`
  stays per-game.
- **GameCenterDashboard** — one shared dashboard (3 byte-identical copies
  collapsed, #560); per-game `*LeaderboardID` injected via DI.

## Capabilities are UNIVERSAL, not Optional

Audio / reminders / ATT / MetricKit **all** wire in `makeGameApp` for every game.
A game *missing* one (MS had no ATT; 2048 had no audio/reminders) is a **bug to
fix during its migration**, NOT modelled as an `Optional` capability. Filling the
gap means adding the seam wiring **and** its L10n keys (see the scan:l10n blind
spot in `ai-translated-localization`).

## The recurring lesson (5×: #558 / #559 / #560 / MS / 2048)

The SDD's "near-identical / generate-from-config / collapse N wrappers" claims
were **optimistic every single time**. Per-game `view` / VM / route enums are
legit gameplay and do NOT collapse. **Audit the actual code before trusting a
spec's "near-identical" claim**, extract only the genuinely-shared bug-prone
scaffolding (a ~15-line generic skeleton, not a god-VM), and **surface the scope
correction to the user before implementing**. Convergence scope is per-surface,
not blanket.

## Adding a new game (checklist)

- [ ] New `<Game>Core` (engine/state, Foundation-only) + `<Game>Kit` (UI/board/tokens).
- [ ] Build a `GameConfig<Route>`: values + `makeRouteFactory` + `homeModes` +
      `fetchResume` (if it has a resume surface) + `makeCompletionSinks` (if it
      uses the shared GC pipeline — see `telemetry-facade-pattern`).
- [ ] `AppComposition.live()` calls `makeGameAppWithDeps`, mounts `wired.view`;
      **no** per-game `Live+*` wrapper files.
- [ ] All universal capabilities wired (audio/reminders/ATT) **with their L10n
      keys present in the game's catalog** — diff the key set vs an existing game.
- [ ] One test target per new production target; snapshot suites follow the
      strict-content / tolerant-board split (`swift-testing-baseline`).
- [ ] `mise run scan:l10n` green (incl. shared dotted-key parity).

## Related skills

- `swiftpm-modularization`: the leaf-core / seam / shared-UI target layout this sits on.
- `telemetry-facade-pattern`: how `makeCompletionSinks` + the GC pipeline wire in.
- `swift-testing-baseline`: per-target test + snapshot-gate strategy for new games.
- `ai-translated-localization`: the scan:l10n key-existence blind spot when a game
  adopts a shared capability.
