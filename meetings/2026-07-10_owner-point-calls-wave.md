# 2026-07-10 — owner point-calls wave: composition rename, settings persistence, acknowledgements root cause, ASC apply closeout

Session id: n/a (consolidated across 2026-07-09 → 2026-07-10)
Mode: AI Collaboration Mode (Leader/Developer)

Arc: this wave closed the four items the owner pointed at directly (#739
composition naming, #720 settings-persistence inventory, #721 Acknowledgements
diagnostic, plus the #700/#738 ASCRegister apply closeout) alongside a
backlog-cleanup pass on #713's fresh Upkeep triage and two l10n gaps
(#731/#688 item 6). Six PRs merged (#740, #742, #743, #745, #746, #748), two
long-open issues fully closed end-to-end (#700, #738) via user-owned
ASCRegister apply runs, and #721 in particular needed two rounds of
prerequisite verification before implementation — the first plan's premise
was falsified by the second round's check.

## Shipped (all merged)

| PR | What | Closes |
|---|---|---|
| #740 | fix iOS 26 `Text("+")` concatenation deprecation warning in `PracticeHubView` | #735 |
| #742 | l10n: MS board-control strings + Sudoku "Cache cleared" toast | #731 (also completes #688 item 6) |
| #743 | l10n: complete MS daily-leaderboard title locales (5 remaining), align es/th Expert wording | prep for #738's ASC apply |
| #745 | refactor: rename Sudoku `AppComposition` → `SudokuAppComposition` | #739 |
| #746 | feat: persist practice difficulty (Sudoku + MS) and MS tap-mode via shared `LastSelectionStore` (gaps G1/G2/G3) | #720 |
| #748 | fix: seed `Root.plist` (+ fix `packagePaths` resolution) so Acknowledgements actually appear in iOS Settings | #721 |

#748 was verified merged with all 4 CI checks green (PR-title lint, lychee
link check, SwiftLint changed-files, L10n catalog completeness) at merge time
— not left mid-CI as originally suspected going into the write-up.

## #700 / #738: ASCRegister apply closeout

- **#700** (MS achievement system, code landed earlier via #734): the
  user-owned `ASCRegister apply` run created **11 achievements + 77
  localizations (11 × 7 locales)** on the live ASC app; a re-plan afterward
  showed 0 remaining creates. Closed.
- That same full-config reconcile surfaced 6 pending leaderboard-localization
  UPDATEs (3 daily leaderboards × en-US/zh-Hant) that were **out of #700's
  scope** — deliberately excluded from that apply and filed separately as
  **#738**, rather than silently widened into the running apply.
- **#738**: the 3 MS daily leaderboards' titles had drifted to internal
  Sudoku-style names instead of MS's own difficulty names. #743 landed the
  missing locale strings + Expert-wording alignment first; the subsequent
  `ASCRegister apply --app minesweeper` then pushed **21
  leaderboard-localization UPDATEs (3 leaderboards × 7 locales)** live —
  Beginner/Intermediate/Expert now match the app's own difficulty labels
  across all 7 locales. Apply log: 98 UPDATEs executed (21 leaderboard-loc +
  77 achievement-loc idempotent re-push), zero HTTP errors. Closed.
  - Lesson (already in memory): a re-plan continuing to show UPDATE for
    already-applied localizations is expected Reconciler behavior, not a
    failure signal — don't treat it as a retry trigger.

## #713 upkeep triage: count discrepancy, flagged not smoothed over

- The Upkeep bot's own machine-generated report table shows **13 findings**
  (0 high / 5 medium / 8 low). The owner's triage comment instead states
  **15 findings — 1 duplicate / 3 won't-fix / 11 actionable**. The two counts
  do not reconcile item-for-item from the data alone (the triage's 11
  "actionable" items are largely a different list than the report's own 13
  rows). Recording both figures as-is rather than picking one.
- 1 duplicate: screenshot placeholder dupe → already tracked at #236.
- 3 won't-fix: an `Agents.md` symlink false positive, plus two
  prototype-staleness false positives where a SUPERSEDED banner was already
  in place (audit tooling didn't detect it).
- Of the 11 actionable items: **item 11** (composition-root naming asymmetry,
  `AppComposition` vs `MinesweeperAppComposition`) → filed as #739 → closed by
  #745 this wave. **Items 4–5** (SDD-005/SDD-006 doc staleness) routed into
  the existing #479 epic tracker (still open). **Items 1, 2, 3, 6, 7, 8, 9,
  10** (apple-dev-skills spec-status note, README state-machine claim,
  `docs/designs/README` index gap, `CONTRIBUTING.md` pattern mismatch, dead
  `UITestLaunchArg.nearWinModalPuzzleId`, hardcoded E2E launch-arg literals,
  two `dark.svg` citation gaps) — no merged PR or dedicated follow-up issue
  found for any of these; they remain outstanding carryover, not silently
  resolved.

## #720: settings-persistence inventory → shared LastSelectionStore

17 user-facing settings inventoried: 10 already persisted, 4 legitimately
transient, 3 real gaps — **G1** Sudoku practice difficulty, **G2** MS practice
difficulty, **G3** MS board tap-mode (the toggle itself shipped via #730/#724;
persisting its last state was the new gap). All three filled through one
shared `LastSelectionStore` seam in #746, not three separate per-app stores.
Two dispositions recorded on the issue:
- **Pencil/notes mode: out of scope** — it's session state belonging to the
  saved-game record, not a `UserDefaults` preference.
- **Theme persistence: deferred**, explicitly marked as a Leader default (not
  an owner ruling, overturnable) — there is no theme picker yet (apps follow
  system appearance 100%, zero `@AppStorage`/appearance hits), so persisting
  one is a new feature, not a gap-fill; file separately if the owner wants it.

## #721: Acknowledgements page — premise falsified on the second verification round

Two-round diagnostic before any code moved, per the L-size prerequisite gate:
- **Round 1**: hypothesized root cause = `Settings.bundle` had no `Root.plist`
  entry point; sized M, flagged one Unconfirmed prerequisite.
- **Round 2** (prerequisite verification): falsified round 1's plan —
  LicensePlist does **not** layer onto an existing `Root.plist`, it must
  directly embed the child-pane spec. Verification also surfaced a second,
  independent bug: `packagePaths` in `license_plist.yml` resolves relative to
  the *config file's* directory, so a workspace-less local generation run
  finds zero packages and could silently ship an empty Acknowledgements page.
- Both fixed in #748 (seeded `Root.plist` correctly + corrected `packagePaths`
  resolution). Closed #721.
- Follow-ups filed as **#747** (3 non-blocking observations, none blocking):
  MS's `Package.resolved` is gitignored causing a local-gen asymmetry vs
  Sudoku; `Settings.bundle` strings aren't localized (a `Root.strings`
  mechanism exists but needs an owner call); test-only dependencies
  (`swift-custom-dump` etc.) currently ship in the generated acknowledgements
  list.

## New issues opened this wave

- **#741** — found while fixing #731: two more MS board sites bypass the l10n
  catalog via ternary-produced bare literals (context-menu Flag/Unflag;
  `MinesweeperBoardView` status text + pause button). Out of #731's scope,
  filed for later.
- **#747** — see #721 follow-ups above.
- **#744** exists but is unrelated to this wave: a bare, unelaborated stray
  feature request ("share & review on app store & the way to add friend on
  game center", body = "as title") — flagging it exists, not treating it as
  part of this closeout.

## Decisions carried / reconfirmed

- **#724** floating-button veto (from the 2026-07-08 wave) — no new activity
  this wave, stays decided.
- **#688** item 6 (Cache-cleared toast l10n) folded into #742's scope; #688
  closed once #742 merged, alongside its other already-closed items.
- Theme persistence and pencil-mode scoping — see #720 above (both recorded
  as explicit dispositions on the issue, not silent omissions).

## Open queue

- **#713** — 8 of 11 actionable items (1, 2, 3, 6, 7, 8, 9, 10) still have no
  closing PR/issue; item count itself (13 vs 15) needs reconciling next pass.
- **#741** — MS board ternary-literal l10n gaps (context menu + status/pause).
- **#747** — #721's 3 non-blocking follow-ups.
- **#716** — pencil notes as positional 3×3 mini-grid (carried from #688 item 4).
- **#722** — digit-first input proposal (select number, then tap cells).
- **#705** — MS practice personal bests, blocked on a per-game unique practice
  id design.
- **#667** — carried-over 2B/2C follow-up (macOS completion pushed-route
  elimination + pause→close icon; leaderboard-fetch-on-loss guard).
- **#479** — SDD-005/SDD-006 doc-staleness epic tracker (hosts #713 items 4–5).
- **#286** — CaptureGuardKit anti-capture cheat-guard proposal (parked).
- **#166** — Android module portability reservation (parked).

## Infra notes

- Session/weekly rate limits interrupted this wave's work more than once;
  the worktree-salvage + targeted-resume pattern from the 2026-07-05/07-08
  waves (uncommitted work survives the stall, resume message picks it back
  up) continued to recover work with no loss. One resume did fall back to the
  main checkout instead of its assigned worktree before being caught — the
  same class of incident already logged from the prior wave, reinforcing the
  "verify the resumed agent's actual `pwd`/branch" practice.
- ASCRegister apply behavior: a post-apply re-plan continuing to list
  already-pushed localizations as UPDATE is the Reconciler's normal idempotent
  behavior, not a signal that the apply failed — folded into memory this wave
  (#738's closing comment made this explicit).

## Next session

Reconcile #713's 13-vs-15 finding-count discrepancy and pick up its 8
untouched actionable items; #705's per-game-unique-practice-id design remains
blocked; #716/#722 remain open product proposals awaiting scheduling.
