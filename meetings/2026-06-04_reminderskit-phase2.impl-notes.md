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
</content>
</invoke>
