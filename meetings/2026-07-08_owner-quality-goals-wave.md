# 2026-07-08 — owner quality-goals wave: mirror closeout, TF automation, GC/loader hardening, MS achievements

Session id: n/a (consolidated across 2026-07-05 evening → 2026-07-08 multiple sessions)
Mode: AI Collaboration Mode (Leader/Developer)

Arc: with the 2026-07-05 UX audit's fix train shipped (see
`meetings/2026-07-05_uiux-audit-screen-contracts-fix-train.md`), this wave closed
out the audit's remaining product-decision backlog (B1–B4), hardened the local
TestFlight pipeline into a four-PR toolchain, then chased two hardening threads
(#685's GC-signed-out residuals, #719's board-loader trap) to a #726 l10n gap and
a #700 achievement-system spec — landing 17+ merged PRs (#701–#734) across four
days. Recurring theme: every owner design call (mirror vs diverge, MS-native vs
generalized seam, fixed vs floating control) got written down as a decision
record on the originating issue before code moved.

## Shipped (all merged)

| PR | What | Closes |
|---|---|---|
| #701 | MS `reminderTapRoute` wired + completion re-view Close pops one level | #696, #697 |
| #702 | delete dead completion leaderboard-zone state machine (both apps hardcode `.hidden`) | #698 |
| #703 | TF tag-per-upload + auto changelog from squash-merge PR titles (#694 P1) | #694 (P1) |
| #706 | MS-native `MinesweeperPersonalRecordStore`, wired at daily win | #699 |
| #708 | TF: skip re-archive on fingerprint match (#670 P1) | — |
| #709 | `.worktreeinclude` so gitignored xcconfig/secrets reach agent worktrees | #707 |
| #711 | fix 4 doc-staleness findings from upkeep audit #668 | — |
| #712 | TF: parallel multi-app upload via `app-position all` (#670 P2) | #670 |
| #715 | GC signed-out entry points alert instead of no-op | #685 |
| #717 | TF: auto-sync What-to-Test via ASC `betaBuildLocalizations` (#694 P2) | #704 |
| #718 | hoist duplicated `elapsed(_:)` formatter into GameAppKit | #710 |
| #725 | #688 mechanical polish: dark banner seam, MS settings tint parity, Sudoku pause a11y id | #688 (items 2/5a/5b) |
| #727 | board loader `.failed` screen gets a Close exit + DEBUG fail hook | #719 |
| #728 | MS catalog: add missing `error.userFacing.*` key family (5 keys × 7 locales) | #726 |
| #729 | AdMob banner: reserve the slot height before the ad loads (AdGate hint) | #723 |
| #730 | MS reveal/flag segmented control merged into one fixed-placement icon toggle | #724 |
| #733 | harden `presentGameCenter` seam (assert + stronger test) left by #685's review | #714 |
| #734 | MS achievement system — 11 achievements, MS-native evaluator, GC reporting | refs #700 (stays open for ASC apply) |

## Product decisions (B1–B4, the audit's carry-over backlog)

- **B1** (#698): both apps hardcoded the completion leaderboard zone to `.hidden`
  while `CompletionViewModel` still ran the dead 5-state fetch machinery — owner
  decided **delete**, not expose.
- **B2 part 1** (#699): MS had no `PersonalRecordSink` — owner decided **wire it
  now**, but as an **MS-native store** (`MinesweeperPersonalRecordStore` beside
  `submitDailyTimeIfWon`) rather than generalizing `TelemetryEvent`/
  `makeCompletionSinks`; that generalization stays deferred to #479. Production
  CloudKit schema for the new `PersonalRecord` type was deployed by the owner via
  Console 2026-07-06 — #699 fully closed end-to-end.
  - Follow-up **#705** (open): the store/schema were built for 6 mode/difficulty
    slots but the write gates on `mode == .daily` — MS practice's `recordName` is
    a non-unique `practice-{difficulty}` singleton (would collapse every practice
    win into one entry), unlike Sudoku's per-game-unique practice id. Needs a
    per-game unique practice id design before ungating.
  - Follow-up **#700** (open, achievements): owner approved an ~11-item set sized
    to Sudoku parity (First Sweep, Daily Debut, Sweeper/Veteran/Master 10/50/200,
    Expert Cleared, Full Spectrum, No Flags Needed, Lightning Sweep, Week/Month
    Streak), same MS-native-evaluator precedent as #699 (MS can't construct
    Sudoku-typed `TelemetryEvent`). Code landed via #734; the issue stays open
    only for the user-owned ASCRegister `plan`→`apply` run against the real ASC
    app id (one-liner recorded in the issue thread).
- **B3** (#696): MS scheduled daily-reminder notifications but `GameConfig`
  omitted `reminderTapRoute` (silent no-op tap) — owner decided **wire it**,
  mirroring Sudoku. Landed in #701.
- **B4** (#697): MS completion Close used `popToNewGame` (`removeAll()`, back to
  Home root) vs Sudoku's `removeLast()` (back to Daily hub) — a leftover from
  SDD-003 Epic 4's New Game button removal. Owner decided **mirror Sudoku**.
  Landed in #701.

## #688 P3 batch: three design gut-checks adjudicated

- Item 1 (MS loss overlay renders near-black vs the win overlay's light mask) —
  **won't-fix**, intentional loss drama.
- Item 3 (Sudoku undo/redo batches 4 same-cell edits into one undo press) —
  **won't-fix**, matches "undo this cell" player intent.
- Item 4 (pencil notes render as a top-left vertical list, not a positional 3×3
  mini-grid) — **promoted to #716** (open, M-sized, snapshot re-records
  expected), not a quick polish item.
- The batch's parked "suspected trap" (BoardLoader `.failed` offers only Retry,
  no exit) graduated from suspicion to **confirmed iOS trap** by code-evidence
  audit (sim repro was blocked by no iCloud-signed-in sim — the gap that
  motivated #727's new DEBUG fail hook) → fixed in #727.
- Mechanical items 2/5a/5b shipped via #725; #688 stays open only as the
  tracking issue for that closed scope (superseded by #716 for item 4).

## #724: floating-button proposal vetoed

Owner's original UX proposal for MS's tap-mode control floated a freely
**movable** floating button. Leader recommended **against** it (drag-vs-board
gesture conflicts, position persistence, a11y complexity, poor discoverability —
long-press-to-flag already solves the reach problem the floating button was
meant to fix), owner accepted the veto. Shipped instead: one **fixed-placement**
44×44pt icon toggle (#730). Recorded fallback if fixed placement proves awkward:
a left/right-hand position Setting (would join #720's persistence inventory).

## TestFlight toolchain: four-PR automation chain

`mise run tf:upload` gained, in sequence: **#703** tag-per-upload + changelog
from squash-merge PR titles (closes #694 P1) → **#708** skip re-archive on a
fingerprint match (source-tree + rendered AdMob.xcconfig hash) → **#712**
parallel multi-app upload (`app-position all`; archive/export stays strictly
sequential to avoid racing the shared `Tuist/AdMob.xcconfig` / `Game.xcworkspace`
paths — only the network-bound altool step fans out) → **#717** auto-sync the
What-to-Test note to ASC via `betaBuildLocalizations` (closes #704 / #694 P2).
Self-caught bug: **#703's implementer found a tag-before-changelog ordering bug
during its own dual-model review** — tagging first would have made every real
upload's changelog empty (self-discovery, not reviewer-found). Build
`202607061321` was the first fully tag+changelog-automated upload (P2's
What-to-Test sync backfilled it after landing); build `202607081028` (carrying
#734's achievement system) was the first upload with What-to-Test sync running
live at upload time, not backfilled.

## Review highlights

- **#734** (MS achievements): dual review (haiku machine-verified 11 IDs / 231
  translation entries / scope discipline; sonnet's deep pass) found **2 MAJORs**
  — a VM-instance-level "already won" latch instead of a game-scoped fact
  (resuming an already-won save could re-inflate the win tally) and
  `everFlagged` computed as a session-transient instead of a persisted fact
  (backgrounding/resuming could falsely grant "No Flags Needed") — both fixed
  and re-verified ACCEPT by the original finder.
- **#719→#726**: #719's own review, walking a real-sim screenshot of the fixed
  board-loader `.failed` screen, spotted MS rendering the raw key
  `error.userFacing.unknown.body` — the whole key family was absent from MS's
  catalog (dynamically-composed keys are invisible to `scan:l10n`'s per-catalog
  completeness check). Filed as #726, fixed same-day in #728.
- **#715** (GC signed-out): root cause traced to the `.alert` modifier being
  attached inside `universalRootModifiers` — a plain helper called exactly once
  from `makeGameApp`, outside any View's `body` — so Observation's render
  invalidation never revisited that attachment point; flipping the alert flag
  had been a correctly-computed no-op all along. Reviewer independently
  reproduced the mechanism with a fresh agent given only the SwiftUI/Observation
  description, no diff.

## Open queue

- **#700** — MS achievement ASC registration (user-owned `ASCRegister plan`→
  `apply` against the real MS app id; code side complete via #734).
- **#705** — MS practice personal bests, blocked on a per-game unique practice id
  design.
- **#716** — pencil notes as positional 3×3 mini-grid (M-sized, from #688 item 4).
- **#720** — settings persistence inventory (would also host #724's fallback
  left/right-hand toggle if needed).
- **#721** — Acknowledgements page not visible in installed app's iOS Settings.
- **#722** — digit-first input proposal (select number, then tap cells).
- **#731** — MS board-control strings are plain English, not in the l10n catalog.
- **#732** — new banner-reserved snapshots are environment-sensitive; switch to
  `.tolerantImage`.
- **#667** — carried-over 2B/2C follow-up (macOS completion pushed-route
  elimination + pause→close icon; leaderboard-fetch-on-loss guard).
- **#713** — fresh Upkeep Report (2026-07-08), not yet triaged.

## Infra notes

- An App Store Connect Program License Agreement lapse produced altool upload
  403s (`ERROR_19`-class) mid-wave; diagnosed by probing the ASCRegister API
  surface rather than guessing, resolved once the owner re-signed the agreement,
  and the queued TF upload auto-resumed on the next poll with no manual re-run.
- One agent-resume incident: a resumed background agent fell back to the main
  checkout instead of its assigned worktree — caught before any cross-task file
  bleed; lesson folded into worktree-hygiene practice (verify the resumed
  agent's actual `pwd`/branch before trusting its next commit).
- Several tasks hit background-agent API rate limits mid-run; the
  worktree-salvage pattern (uncommitted work survives the stall → targeted
  resume message) recovered all of them with zero work lost, consistent with
  the pattern already recorded from the 2026-07-05 wave.

## Next session

Triage #713's fresh Upkeep Report; pick up #705's per-game-unique practice id
design; owner to run the #700 ASCRegister apply step when ready.
