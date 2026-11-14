---
name: game-factory-composition
description: The shared composition template that lets multiple games (Sudoku / Minesweeper) share ONE live stack — `GameConfig<Route>` + `makeGameApp(config:)` in GameAppKit, `<Game><Concern>` target naming, and shared non-gameplay UI (3-tab root shell + tab-root chrome / DailyHub skeleton / board-redirect / GC dashboard). Only the Game module is per-game; everything else is reusable module + DI config. Invoke when adding a new game, migrating a game's composition root, deciding what is shared vs per-game, writing a `GameConfig`, or when asked "how do I bootstrap game N / why is there a makeGameApp". Not for gameplay engine or board code inside one game, and not for general SwiftPM target layout (see apple-dev-skills:swiftpm-modularization).
---

# Game Factory Composition

## When to invoke

- Bootstrapping a **new game** (start with `mise run new_game:scaffold <Name>`).
- Migrating a game's composition root onto the shared backbone.
- Deciding whether a surface is **shared** or legitimately **per-game**.
- Writing or reviewing a `GameConfig<Route>` / a `makeGameApp` call site.
- Reviewing a PR that touches `GameAppKit` composition or adds a per-game
  `Live+*.swift` wrapper (the latter is usually drift — see below).
- User asks "how do I add a third/fourth game", "what does makeGameApp wire",
  "what stays per-game".

This skill describes what is live in `GameAppKit` today. The design record is
SDD-005 (`docs/superpowers/specs/2026-06-17-sdd-005-platform-convergence-rfc.md`);
where the two differ, the code is right. The games are Sudoku and Minesweeper.

## The prime shape

> Only the **Game module** is per-game. Everything else = reusable module + DI
> config. A 4th game ≈ fill one `GameConfig` + supply engine / board / tokens.

Reason: a bug in the shared path is fixed and verified once for both apps; a bug
in duplicated per-app code must be fixed twice (#536, #554). This structure is how
the mirror principle (`CLAUDE.md` §Mirror principle) is enforced.

## Three pillars

### A. Naming — `<Game><Concern>` targets

- Targets are named `<Game><Concern>`: `SudokuAppComposition`, `SudokuPersistence`,
  `MinesweeperAppComposition`, `MinesweeperPersistence`. Use Minesweeper as the
  template for a new game.
- New files inside `<Game>UI` take no game prefix. Older Minesweeper files still have one.

### B. Composition-as-template — `GameConfig` + `makeGameApp`

- `GameConfig<Route>` (in `GameAppKit/GameConfig.swift`) carries **per-game
  content only** (subsystem, ckConfig, removeAdsProductId, theme, title, tints,
  audio key prefix, reminder copy, `settingsRoute`) **plus builder closures**
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

- **Root shell (3.0, #1020)** — universal `sidebarAdaptable` TabView
  (`GameShellUI/RootShellView.swift`: Today / Practice / Progress, one path per
  tab) with per-game tab roots supplied through `config.makeTabRoot` (built
  once per tab per launch — treat it as a factory with stable identity). The
  Today root is wrapped in `TodayTabHost` (resume pill); the banner and the ATT
  primer anchor live in one shared `BannerAccessoryView` (`tabViewBottomAccessory`);
  every tab root gets the shared Settings gear (`TabRootChrome`); Progress hosts
  the shared `GameCenterEntryRow`. There is no HOME screen.
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
A game *missing* one (e.g. MS initially shipped with no ATT primer) is a **bug to
fix during its migration**, NOT modelled as an `Optional` capability. Filling the
gap means adding the seam wiring **and** its L10n keys (see the scan:l10n blind
spot in `apple-dev-skills:ai-translated-localization`).

## Before you merge two per-game implementations

Per-game views, view models and route enums are gameplay and do not collapse.
Every "near-identical" claim in a spec so far overstated the overlap (#558, #559, #560).

1. Read both implementations before trusting a claim that they are near-identical.
2. Extract only the shared, bug-prone scaffolding (a small generic skeleton, not one large view model).
3. If the real overlap is smaller than the spec says, tell the user before implementing.

## Adding a new game (checklist)

- [ ] Run `mise run new_game:scaffold <Name>`. It copies Minesweeper into a compiling skeleton and never touches git state.
- [ ] Fill `<Name>CoreKit` (engine and state, Foundation-only) and `<Name>Kit` (UI, board, tokens).
- [ ] Build a `GameConfig<Route>`: values + `makeRouteFactory` + `makeTabRoot` + `settingsRoute` +
      `fetchResume` (if it has a resume surface) + `makeCompletionSinks` (if it
      uses the shared GC pipeline — see `apple-dev-skills:telemetry-facade-pattern`).
- [ ] `AppComposition.live()` calls `makeGameAppWithDeps`, mounts `wired.view`;
      **no** per-game `Live+*` wrapper files.
- [ ] All universal capabilities wired (audio/reminders/ATT) **with their L10n
      keys present in the game's catalog** — diff the key set vs an existing game.
- [ ] One test target per new production target; snapshot suites follow the
      strict-content / tolerant-board split (`apple-dev-skills:swift-testing-baseline`).
- [ ] `mise run scan:l10n` green (incl. shared dotted-key parity).

## Related skills

- `apple-dev-skills:swiftpm-modularization`: the leaf-core / seam / shared-UI target layout this sits on.
- `apple-dev-skills:telemetry-facade-pattern`: how `makeCompletionSinks` + the GC pipeline wire in.
- `apple-dev-skills:swift-testing-baseline`: per-target test + snapshot-gate strategy for new games.
- `apple-dev-skills:ai-translated-localization`: the scan:l10n key-existence blind spot when a game
  adopts a shared capability.
