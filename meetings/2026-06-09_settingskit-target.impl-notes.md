# Impl Notes — SettingsKit target extraction (2026-06-09)

Status: COMPLETE
Owner: Senior Developer
Dispatched by: Leader
Started: 2026-06-09

## 設計決定 (Design decisions)

- **SettingsKit dependency edge → depends on GameShellUI (option a)** — Task §"Build the package"
  offers (a) SettingsKit → GameShellUI for Theme, or (b) extract Theme standalone.
  Chose **(a)**. `ReminderPrimerSheet` + `ReminderDeniedExplainer` read `@Environment(\.theme)`
  (`theme.text.primary.resolved`, etc.) and rely on `NeutralTheme` as the env default — all
  defined in `GameShellUI/Theme/Theme.swift`. The 7 other moved files use NO theme. Option (a)
  is the cheap, no-cycle choice: GameShellUI already has zero references back to any
  Settings/Reminder symbol in production (verified — only comment mentions of "SettingsShellView"
  remain in DailyHubShellView/PracticeHubShellView), so SettingsUI → GameShellUI is a clean DAG
  edge. Theme extraction (b) would be a speculative second refactor touching every Theme
  consumer; deferred per Karpathy "simplicity first" + task's "don't do speculative Theme
  extraction".

- **Package shape** — New `Packages/SettingsKit` with one library target `SettingsUI` + one
  test target `SettingsUITests` (one-to-one per swiftpm-modularization). Repo already runs 12
  sibling packages, so a new sibling package matches established precedent (task explicitly
  requests a package, not a target inside GameShellKit).

- **SettingsUI dependencies** — `GameShellUI` (Theme env) + `Reminders` (the protocol seams the
  models re-export: `ReminderAuthStatus`, `NotificationAuthorizing`, `ReminderScheduler`,
  `ReminderKind`, `ReminderContent`). `SettingsUITests` adds `RemindersTesting`
  (Noop/Fake authorizers the moved model tests drive).

## 偏離 (Deviations)

- **Moved-test `@Suite` display labels still read "GameShellUI — …"** — the 5 moved test
  files keep their `@Suite("GameShellUI — …")` display strings (now in SettingsUITests). Left
  as-is per surgical-changes: they're cosmetic console labels, not identifiers; renaming would
  add churn unrelated to the move. Flagging for Leader — trivial follow-up if desired.

- **`tuist generate` not run** — sandbox denied the command (workspace mutation). The full SPM
  graph (13 packages incl. new SettingsKit) resolves + builds + tests clean via `swift build`,
  which is what Tuist's SPM integration consumes. Project.swift names no SettingsKit product
  directly (apps pull SettingsUI transitively via SudokuUI/MinesweeperUI), so no Project.swift
  edit was needed. Leader/user should run `tuist generate` once to confirm the schemes.

## 折衷 (Tradeoffs)

- **Move ReminderPermissionModel into SettingsUI too** — it is not strictly a "Settings" type,
  but `ReminderSettingsModel` composes it and `ReminderPrimerCoordinator` (Sudoku) constructs it.
  Task's move-set explicitly lists it. Keeping it in GameShellUI would force SettingsUI ↔
  GameShellUI to share it across the boundary with no benefit. Moved.

## 未決 (Open questions)

- **Project.swift (Tuist)** — references only `SudokuUI` / `AppComposition` / `MinesweeperUI` /
  `MinesweeperAppComposition` package products, NOT GameShellUI or any moved symbol directly.
  SettingsUI is pulled transitively. Expectation: no Project.swift edit needed. Will confirm by
  resolution at verify. If `tuist generate` complains, revisit.
