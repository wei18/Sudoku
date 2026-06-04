# RemindersKit Phase 2 — Impl Notes (in-flight)

**Task**: #287 Phase 2 — permission-priming UI (GameShellUI) + Sudoku U1 wiring + telemetry seam.
**Branch**: `feat/reminderskit-phase2-287`. Foundation merged in #318.
**Design target**: `docs/designs/reminders-flow.prototype.html`; proposal `meetings/2026-06-03_notification-reminders-proposal.md` §5 / §4.5–4.7.

## Decisions

### D1 — ReminderPermissionModel location: GameShellUI (not Reminders)
Proposal §4.4 left this open (Q2). Put the `@MainActor @Observable ReminderPermissionModel`
in **GameShellUI** alongside the primer sheet view, because:
- It drives SwiftUI shell chrome (the sheet) and needs `@Observable` (SwiftUI dep).
- Keeping `Reminders` SwiftUI-free preserves it as a leaf domain package (proposal §4.3).
- GameShellUI already depends on nothing reminder-related → add a `Reminders` product dep
  to GameShellKit (leaf → leaf, no cycle). The model depends only on the
  `NotificationAuthorizing` protocol seam, never on `UserNotifications`.

### D2 — Primer sheet copy fully injected (params), default rendered at Sudoku call site
The `ReminderPrimerSheet` view takes title/lede/bullets/CTAs as params so both apps share it
(proposal §4.4 / flow S03). Sudoku passes the flow-visual S03 copy ("One nudge a day, that's
it" …) from its `Localizable.xcstrings`. S06 denial explainer is a second view
(`ReminderDeniedExplainer`) in the same file.

### D3 — Value-moment trigger (Sudoku U1): Daily Completion screen affordance
The flow visual S02/S03 shows the primer after solving a Daily. The completion route
(`AppRoute.completion`) is reached after solving any puzzle. To avoid asking on a Practice
solve, the affordance ("Remind me when tomorrow's puzzle is ready") + primer is gated on the
puzzle being a Daily. CompletionViewModel/Route do not currently carry `isDaily` — see D3a.

### D3a — How "isDaily" is known at Completion
`AppRoute.completion` lacks an isDaily flag and the leaderboardId is hardcoded `.dailyEasy`.
Threading a new flag through the route + everywhere it's constructed is a large blast radius
that risks snapshot churn.

**FINAL CHOICE**: the value-moment is the **Daily Completion screen** affordance
("Remind me when tomorrow's puzzle is ready" → opens primer sheet), mirroring flow S02/S03.
`CompletionView` gains an OPTIONAL `reminderPrimer: ReminderPrimerCoordinator?` param
defaulting to `nil`. The affordance + `.sheet` render ONLY when the coordinator is non-nil.
All existing snapshot fixtures construct `CompletionView(viewModel:)` with no coordinator →
byte-identical. Live wiring (RouteFactory) injects a coordinator only for the Daily-solve
completion (gated `isDaily`), so a Practice solve shows nothing.
The coordinator owns the `ReminderPermissionModel` + the localized `ReminderContent` + the
`schedule(...)` call on accept.

### D4 — Snapshot discipline
Primer is a `.sheet` (isPresented=false by default) + the affordance must NOT render in any
existing snapshot fixture. Any churn = bug.

## Telemetry seam (Chunk 3)
Add 5 TelemetryEvent cases (proposal §4.6). RemindersKit stays Telemetry-free; AppComposition
observes outcomes → `telemetry.observe(...)`.

## Deferred
- MS U1 (no Daily yet) — Noop/skip, follow-up.
- macOS Settings deep-link (P12) — textual fallback only.
- #195 ATT rescope — Leader/user action, not code.

---

## Chunks 2 & 3 execution (2026-06-04, continuation)

Chunk 1 (shared primer UI in GameShellUI) merged in #323. This pass does the
Sudoku U1 wiring (chunk 2) + the telemetry seam (chunk 3).

### D5 — Telemetry events: `kind: String`, not typed (chunk 3)
Added 6 `TelemetryEvent` cases (`reminderPrimerShown/Accepted/Declined`,
`reminderScheduled`, `reminderFired`, `reminderOpenedApp`). Payload is `kind: String`
(the `ReminderKind.rawValue`) rather than a typed `ReminderKind`, because TelemetryKit
is a leaf observability package that must NOT import `RemindersKit` (mirrors the
`puzzleId: String` precedent; the M5 typed-`Mode` argument doesn't apply since
`ReminderKind` lives in a sibling package, not SudokuEngine which TelemetryKit
already imports). Host maps `kind.rawValue` at each emit site. OSLogSink switch
extended; event-surface tests extended (Sendable + Codable round-trip lists).

### D6 — ReminderPrimerCoordinator lives in SudokuUI (chunk 2)
The coordinator (owns the localized Sudoku copy + `ReminderContent` + the
permission model + the schedule-on-accept flow + the telemetry callback) is a
`@MainActor @Observable` class in **SudokuUI**. SudokuUI gains a `Reminders`
product dep (it already depends on GameShellUI for the primer view + permission
model). The concrete `Live*` authorizer/scheduler + the `UNUserNotificationCenterDelegate`
stay in AppComposition (the only layer allowed `import UserNotifications`).
Telemetry is injected as a `@Sendable (TelemetryEvent) -> Void` callback so SudokuUI
needs no behavioural coupling to the Telemetry actor beyond the event type
(SudokuUI already imports Telemetry).

### D7 — Value moment & isDaily gate (confirms D3a)
Per design S02→S03, the primer is offered on the **Daily completion screen**.
`CompletionView` gains an optional `reminderPrimer: ReminderPrimerCoordinator?`
(nil default) → affordance + `.sheet` render only when non-nil → all existing
snapshot fixtures stay byte-identical. `LiveRouteFactory.view(for: .completion)`
injects the coordinator **only when the puzzleId is a Daily** (`!hasPrefix("practice-")`,
the same encoding `BoardLoaderView.identity` relies on) — a Practice solve shows nothing.
NOTE (deviation surfaced): production code does not yet PUSH `.completion` anywhere
(only RouteFactory maps it + tests construct it). The solve→completion nav is a
separate un-landed transition; this wiring is correct for when it lands and is the
faithful design seam. Flagged for Leader.

### D8 — Persisted fire-time = the #321 seam
`ReminderSettingsStore` — a tiny `UserDefaults`-backed value (`Sudoku` has no
existing local-prefs store; Settings uses CloudKit Persistence, wrong home for a
device-local fire time). Keys `com.wei18.sudoku.reminder.dailyReadyHour` /
`...Minute`, default 9:00 AM local. #321's Settings picker binds to this exact
store. Lives in SudokuUI so both the coordinator and a future Settings picker read it.

### D9 — UNUserNotificationCenterDelegate in AppComposition
`ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate` in
AppComposition. `willPresent` → `[.banner, .sound]` + `reminderFired` telemetry.
`didReceive` → `reminderOpenedApp` telemetry + deep-link to `.daily` via the
RootViewModel path. iOS+macOS (UN exists on both); delegate retained process-wide
(mirrors `LiveMetricKitRetainer`). Set in `bootMonetization`-adjacent boot, gated so
tests don't touch the system center.

### Chunk-1 CR nits folded
- (a) Scrubbed the paste-artifact tail from THIS impl-notes md.
- (b) 28pt min-height in ReminderPrimerSheet left as-is per CR (cosmetic, auto-grown).

### Verification (2026-06-04)
- TelemetryKit: `swift test` → 29 tests pass (7 suites).
- RemindersKit: `swift test` → 12 tests pass (2 suites). (untouched sources; sanity)
- SudokuKit: `swift test` → 176 tests pass (37 suites), incl. new
  `ReminderPrimerCoordinator — daily-ready flow` (7) + `ReminderSettingsStore` (3).
  Full `swift build` (all targets, incl. AppComposition) clean.
- GameShellKit: `swift build` clean (untouched; consumed).
- No snapshot baselines needed re-record — the optional nil-default coordinator
  param kept every existing Completion/Root fixture byte-identical (zero new PNGs).

### Open / Leader follow-up
- **`.completion` is not pushed in production yet** (D7 note). The reminder primer
  is wired to the faithful design seam (Daily completion screen) but the
  solve→`.completion` navigation transition is itself un-landed. When that lands,
  the primer activates automatically with no further wiring. NOT a regression —
  flagged so Leader knows the affordance won't appear until the solve-nav ships.
- Sudoku copy passed as `LocalizedStringKey` literals; non-en locales pending the
  next `ai-translated-localization` sweep (en renders correctly meanwhile).
- MS U1 still deferred (no Daily in Minesweeper). macOS Settings deep-link (P12)
  textual fallback only.

Status: COMPLETE
