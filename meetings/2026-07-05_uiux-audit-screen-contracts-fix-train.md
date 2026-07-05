# 2026-07-05 — dual-app UIUX/spec audit, screen-contract methodology, fix train

Arc: the owner reported 4 device screenshots (fixed same-day: #673-#677) → then
asked for a Fable-led systematic UIUX/spec review of BOTH apps → three audit
lanes (Sudoku sim · MS sim · spec-drift) + a Leader heuristic pass → the owner
elevated navigation specs to "the most important product-planning artifact" →
a new as-built spec pair + a new `screen-contract-spec` skill (research-backed)
→ the skill audited its own repo (contract-driven static pass) → a 4-PR fix
train closed every actionable finding. Two suspected P1s were downgraded to
environmental with log/code evidence rather than "fixed".

## Shipped (all merged)

| PR | What | Closes |
|---|---|---|
| #676 | reminder denied-sheet background fills the detent (ScrollView-root, mirrors primer) | #673 |
| #677 | Sudoku timer into the board header; modal chrome capsule retired (GameChromeState dormant) | #674 |
| #678 | `mise run new_game:scaffold` generator (#479 PR1; Zephyr build+launch smoke) | — |
| #679 | resume pill: no eager loadOrCreate write (the 0:00 orphan) + in-session refresh hooks | #675 |
| #683 | **`docs/navigation-flows.md` + `docs/screen-contracts.md`** (21 contracts, 18→23-row negative-flow table) + 10 doc corrections | — |
| #684 | **`screen-contract-spec` skill** (9th project skill) | — |
| #689 | negative flows N19-N23 (clear-cache, GC-completion, ATT-denied, IAP, restore-empty) | — |
| #690 | Sudoku clearCache failure toast (was unconditional success) + 7-locale key | #687 |
| #691 | `.isModal` a11y isolation on pause + completion overlays (17 lines, both apps) | #680 |
| #692 | Daily `.exhausted` alert CTAs actually navigate (Practice swap / Cancel→Home) | #686 |
| #693 | MS pre-first-tap board exit (idle branch + ✕/`leave.game.leave` label) | #681 |

## The audit (three lanes + one skill-driven)

- **Sim lanes** (both apps, dedicated simulators after a collision incident —
  lesson recorded: pre-assign UDIDs in dispatch prompts; `simctl ui appearance`
  is device-global). Sudoku 6 findings / MS 5 findings + independent P1
  re-verification on an isolated device.
- **Spec lane**: SDD-003's push→modal switch had never propagated to
  `docs/v1/design.md` §How.5 or `docs/designs/01-06` (8 docs, one shared root
  cause). Real product asymmetries surfaced: MS reminder tap no-op; MS re-view
  Close→Home vs Sudoku→Daily-hub; completion leaderboard slice dormant (#468).
- **Contract-driven static pass** (the new skill auditing its own worked
  example) added: the empty `{}` exhausted-alert button (#686), the clearCache
  false-success (#687), the silent third GC signed-out entry (folded into
  #685), and 5 missing negative-flow rows (#689).
- **Environmental downgrades (evidence, not vibes)**: sim resume-pill absence =
  genuine CK unauth (`CKError 36/1029` in the app's own telemetry log); IAP
  dead rows = `simctl launch` doesn't inject the `.storekit` scheme config; MS
  daily-card badges (#682 closed) = three-state UI fully wired, but the sim's
  dead CK meant the loss record was never written NOR fetchable.

## screen-contract-spec skill

Two research passes (methodology: NN/g wireflows, statecharts/orthogonal
regions for covering/z-order, negative-edges→E2E derivation, traceability IDs,
ADR deltas · platform: full presentation-semantics table SwiftUI↔UIKit with
constraint matrix) + repo battle-scars (#197/#523/#611/#518/2B/#674-trap).
Key naming decision: NOT "design-app-prototyping" (collides with
`ios-design-mockup` triggers). Includes the owner's login example: success =
**root-swap, not modal-present**; logout = swap back, never dismiss.
Research provenance: memory `reference/screen-contract-spec-research.md`.

## Notable engineering decisions

- **#681 idle exit**: view-local `showIdleLeaveOverlay` instead of calling
  `session.pause()` — MinesweeperSession deliberately guards `.playing`, so
  routing through the session would silently no-op. Resume-from-idle clears the
  flag only; `resumeBeforeFirstActionIsNoop` pins the seam as defense-in-depth.
- **#686 exhausted CTA**: in-place last-path-entry swap (`path[count-1] =
  .practice`) — a NEW pattern (no repo precedent); sonnet CR reasoned it safe
  (one Binding write → one UIKit `setViewControllers` transition) but flagged:
  **manually sim-verify before reusing the pattern elsewhere** (`.exhausted`
  has no DEBUG hook). Bonus: fresh VM per `.daily` push = real same-day retry.
- **#691**: `.accessibilityAddTraits(.isModal)` alone suffices — evaluated
  against manual `accessibilityHidden` plumbing with before/after
  `describe-all` tree evidence; live re-confirmed on #693's new idle path.
- Infra weather: repeated 600s-watchdog stalls + API outages killed several
  agents mid-task; the worktree-salvage pattern (uncommitted work survives →
  targeted resume message) recovered every one with zero work lost.

## Open (gated, no work in flight)

- **#685** GC signed-out dead buttons (3 entry points) — gate: owner confirms
  the AUTHENTICATED dashboard path on a real GC-signed-in device; Completion
  entry entangled with #468.
- **#468 + B1-B4 product decisions**: completion leaderboard zone
  (expose vs delete dead states) · MS `makeCompletionSinks` absent
  (achievements/PersonalRecord unwired — intentional or gap?) · MS
  `reminderTapRoute` absent · MS re-view Close lands Home vs Sudoku Daily-hub.
- **#688** P3 polish batch (6 items incl. the unlocalized "Cache cleared"
  literal) · **#694** TF per-build changelog (tag-per-upload + PR-title
  changelog + ASC whatsNew P2) · #670 tf:upload ergonomics · #667-2C ·
  #479 PR2-4.
- Coverage gaps for a future audit round: iPad regular + macOS (highest
  platform-trap density), MS Intermediate board, Settings sub-screens,
  AX3 on Board/Completion, offline pass.

## Owner device-check list (next build)

Reminder sheet margins (#676) · timer in header (#674) · resume pill lifecycle
(#675) · MS Ready-state ✕ exit + "Leave" label resolution (#693) · fail a
daily → Failed badge appears (#682 reopen condition) · GC entry points open
the dashboard when signed in (#685 gate).
