# Impl Notes — #287 Reminders in Settings (2026-06-09)

Status: COMPLETE
Owner: Senior Developer
Dispatched by: Leader
Started: 2026-06-09
Completed: 2026-06-09

## Context — Step 0 current state

RemindersKit is COMPLETE (prior PRs #287/#319/#321): protocol seams
(`NotificationAuthorizing`, `ReminderScheduler`), value types, Live conformers
(real `UNUserNotificationCenter` scheduling + authorization — scheduling IS
implemented), Noop, Fakes, tests. GameShellUI has `ReminderPermissionModel`,
`ReminderPrimerSheet`, `ReminderDeniedExplainer` (shared chrome).

Sudoku: `ReminderPrimerCoordinator` (post-Daily primer), `ReminderTimeSettingsModel`,
`ReminderSettingsStore`. Settings has a **time-picker row ONLY** (no enable/permission
entry). The permission primer fires ONLY post-Daily-completion (CompletionView).

Minesweeper: NOTHING — no RemindersKit dep, no Settings reminder entry, no copy.

### Gaps to close
1. Sudoku Settings has no user-initiated way to enable reminders / prime permission
   (only the time picker, which silently no-ops the reschedule until granted).
2. Minesweeper Settings has no reminders entry at all.
3. Sudoku reminder copy literals (in Live.swift) are NOT in the app catalog →
   English fallback in 6 non-en locales.

## 設計決定 (Design decisions)

- **Enable-from-Settings via the existing primer chrome, not a new toggle widget**
  — The prompt asks the Settings entry to "enable daily reminders, prime the
  notification permission (reuse ReminderPrimerSheet/ReminderPermissionModel), and
  set the reminder time (reuse ReminderTimeSettings)." Rather than invent a Toggle
  with custom on/off semantics (which fights iOS — the OS owns auth state), the
  Settings Reminders section gets: (a) a permission/enable ROW that, when
  notifications are not yet authorized, presents the SAME `ReminderPrimerSheet` to
  prime + request; once authorized it schedules the daily reminder; (b) the
  existing time-picker row. This reuses 100% of existing seams.

- **Shared `ReminderSettingsModel` in GameShellUI** — To satisfy "Minesweeper
  mirrors Sudoku" + "reusable targets over duplication", the enable/prime/schedule
  logic for the Settings entry lives in a NEW shared `@Observable` model in
  GameShellUI (depends only on the `Reminders` seams + injected copy), consumed by
  BOTH apps. Sudoku's existing `ReminderTimeSettingsModel` (SudokuUI) stays as-is
  for the time row; the new shared model owns the enable/permission affordance.
  Decision pending: whether to ALSO move the time-picker logic into the shared
  model — see 折衷.

## 偏離 (Deviations)

- **`.cancelled` event emits NO telemetry** — `TelemetryEvent` has no
  `reminderCancelled` case (only shown/accepted/declined/scheduled/fired/openedApp).
  Rather than add a telemetry case (out of scope), the host's emit-bridge drops
  `.cancelled`. The `disable()` cancel still happens; only the analytics event is
  omitted. The Reminders OSLog subsystem already logs the center call.
- **MS reuses `.dailyReady` kind** — MS has a Daily mode but no Sudoku-style
  "dailyReady" semantic. The generic `ReminderKind.dailyReady` is the daily-anchor
  kind; MS uses it (no new kind added). Copy is MS-specific.
- **MS fire-time persistence is inline UserDefaults closures (no store type)** —
  Sudoku's `ReminderSettingsStore` stays SudokuUI-local (still used by the
  post-Daily coordinator). The shared model takes get/set closures, so MS Live
  inlines a `UserDefaults` pair under `com.wei18.minesweeper.reminder.*` rather
  than extracting a shared store type — smaller blast radius, no new public type.

## 折衷 (Tradeoffs)

- **Keep SudokuUI `ReminderTimeSettingsModel` vs. move it into shared GameShellUI**
  — Considered moving the whole time-picker model into GameShellUI for max reuse.
  Picked: build ONE shared `ReminderSettingsModel` in GameShellUI that owns BOTH
  enable-priming AND the fire-time, and have Sudoku adopt it (deprecating its
  SudokuUI-local time model is out of scope / risk). To avoid two overlapping
  models, the shared model is the single source for the Settings entry in BOTH
  apps; Sudoku's existing post-Daily `ReminderPrimerCoordinator` is untouched.
  Final shape decided during implementation below.

## 未決 (Open questions)

- **RESOLVED — Sudoku's `ReminderTimeSettingsModel` is RETIRED** in favor of the
  shared GameShellUI `ReminderSettingsModel`. It was Settings-only (RouteFactory
  `makeReminderTimeSettings` → SettingsView; the post-Daily path uses the separate
  `ReminderPrimerCoordinator`, untouched). Adopting the shared model in both apps
  is the "reusable targets over duplication" call. Its tests migrate to GameShellUI.
  `ReminderSettingsStore`/`ReminderFireTime` (SudokuUI) STAY — still used by the
  post-Daily `ReminderPrimerCoordinator`; the shared model persists via injected
  get/set closures so it does not couple to Sudoku's concrete store. Sudoku's
  Live.swift bridges those closures to the existing `ReminderSettingsStore`; MS
  gets its own `UserDefaults`-backed closures (own key prefix).

## Final design (implemented)

GameShellUI gains:
- `ReminderSettingsModel` (`@MainActor @Observable`) — owns: current auth status
  (refreshed on appear), the fire `Date`, primer presentation. Actions: `onAppear`
  (refresh status + seed time), `enable()` (present primer), `acceptPrimer()`
  (request auth → on grant schedule daily), `declinePrimer()`, `fireDate.didSet`
  (persist + reschedule when granted), `openSettings()` (denied recovery).
  Persistence via injected `getFireTime`/`setFireTime` closures (Sendable hour/min
  tuple) so it is store-agnostic.
- `ReminderSettingsSection` (View) — a `Section` with: an enable/status row
  (button when not-authorized → primer; shows "On"/deep-link when authorized/denied)
  + the time `DatePicker` row (shown once authorized). Copy fully injected
  (`ReminderSettingsCopy`). Presents `ReminderPrimerSheet` / `ReminderDeniedExplainer`.

Sudoku: SettingsView swaps `ReminderTimeRow`+`ReminderTimeSettingsModel` for the
shared section/model; Live.swift builds the shared model (bridging closures to the
existing `ReminderSettingsStore`). Minesweeper: SettingsView mounts the same shared
section; MS adds RemindersKit dep, MS Live builds the model with a UserDefaults
store (key prefix `com.wei18.minesweeper.reminder.*`) + MS copy + Live conformers.

## AppComposition / ATT boundary — CONFIRMED CLEAN

`git diff --name-only` shows NO change to `AppComposition.swift` (boot sequence),
`ATTPresenter`, or any ATT path. Only `AppComposition/Live.swift` (the composition
ROOT — constructs the model factory; not the cold-launch boot/permission path) was
touched, for both apps. `ReminderNotificationDelegate.swift` (post-Daily tap
routing) is untouched. Reminder priming fires ONLY from the user-initiated Settings
entry (the `enable()` → primer sheet path), never at cold launch.

## Verification

- swift test GREEN: GameShellKit 26 / SudokuKit 210 / MinesweeperKit 111.
- New scheduler-seam coverage via `ReminderSettingsModelTests` (authorization
  gating, schedule/cancel, picker persist+reschedule) using RemindersTesting fakes.
- No snapshot baseline broke: SettingsView call sites in snapshot tests pass no
  reminder entry → `reminderSettings: nil` → byte-identical Settings screen.
- Localization: +21 keys each in App/Sudoku + App/Minesweeper catalogs, full
  7-locale coverage (en/es/ja/ko/th/zh-Hans/zh-Hant), 0 `<TRANSLATE>`, pure
  additions (no reformatting of existing entries — Xcode separators + preserved
  key order + no trailing newline = clean diff).
