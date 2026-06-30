# 2026-06-29 — interactive simulator UX audit (Sudoku + Minesweeper v2.6.0)

Drove both shipping apps in the iOS Simulator with idb, screen by screen, and ran a
3-perspective design/a11y review in parallel. Arc: **stand up a reusable idb drive
harness → capture every screen/flow of both apps → reconcile findings (Leader
adjudicates each falsifiable claim against code + production) → file + fix the real
ones**. Ran from ~16:00 past midnight.

## Goals (as they arrived)

1. Bring both latest apps up via idb and exercise every screen / flow / behavior.
2. Save the useful drive operations as scripts for reuse next time.
3. Pair with a UI/UX perspective to check it all carefully.
4. (then) File + fix what's real. User authorized F1+F2, then F5/F6/F7, then F3 + Play Again.

## Method

- **Reusable harness** (kept local, NOT committed): `.claude/skills/interactive-sim-ux-audit/scripts/`
  — `sim-env.sh` / `build-install.sh` / `drive.sh` (launch · desc · tap · taplabel · swipe ·
  shot · dyntype · appearance) + `README.md` of every gotcha.
- **39 screenshots**, each eyeballed; a11y tree per screen. Both apps built from the
  **main checkout** (worktrees lack the GC/CK/AdMob entitlements + secrets).
- **3 parallel reviewers** (Sonnet): Sudoku UI, Minesweeper UI, cross-app Accessibility.
  Leader reconciled — union of real issues, and **personally verified every falsifiable
  colour/behaviour claim against code + a production render** before filing.

## Findings → outcomes

| # | Sev | Finding | Status |
|---|---|---|---|
| **F1** | P1 | Sudoku Settings showed hardcoded **"1.0.0"** (MS read 2.6.0 from bundle) — `LiveRouteFactory:220` never passed `appVersion:` | **fixed** #644 → PR #646; **sim-verified 2.6.0** |
| **F2** | P2 | Cancelling App Store sign-in leaked raw **"userCancelled"** toast — two `String(describing: error)` catch-alls in `MonetizationStateController` | **fixed** #645 → PR #646 |
| **F3** | P3 | system-blue leaks: board **Undo/Redo** (DigitPad missed by #610 sweep) + Settings **Purchases rows** (`Button` label default tint) | **fixed** #650 → PR #651 |
| **F5** | P2 | **Pause/Resume tap target ~13–16 pt** (both apps), ≪ 44 pt HIG; cells 39–42, digit keys ~32 | **filed** #647 |
| **F6** | P2 | Leave-Game has no **visible Cancel** on iOS 26 (see below) | **filed + reframed** #648 |
| **F7** | P2 | MS light-mode **revealed-empty cells are borderless white**, grid structure lost (dark mode OK) | **filed** #649 |
| — | P3 | Play Again missing on completion (both designers) | **#652, in flight** (reverses SDD-003 Epic 4) |

Plus unfiled P3s: contrast sweep (multiple text/CTA pairs visually < AA — needs tooling),
colour-only cues (MS 1/2/3; Daily difficulty dots), AX5 icon-no-scale + "Leader-board"
hyphenation, completion dead-space, home bottom dead-space, Leaderboard silent no-op when
GC unavailable.

## Shipped

| PR | What | Issues |
|---|---|---|
| #646 | Sudoku settings reads bundle version; silence IAP-cancel toast | Closes #644, #645 |
| #651 | kill system-blue on undo/redo + IAP rows (4 src lines + 13 re-recorded snapshots) | Closes #650 |

Opened: #644 #645 #647 #648 #649 #650 #652. In flight: **#652 Play Again** (Developer in
worktree; lower-risk approach — reuse `drawPuzzle`+`presentGame`, no determinism-sensitive
re-seed; L10n ×7 + snapshots to be Leader-finalized).

## Key calls / false-positive intercepts (Leader adjudication beat the agents twice)

- **Completion "Close" blue = DEBUG artifact, NOT a bug.** Both UI agents "confirmed" the
  win-screen Close was wrong-colour system blue. It only renders blue under the
  `-uitest-near-win` **push** hook, which bypasses `makeGameApp`'s theme injection. Re-ran
  the win on the **production** path (`-uitest-near-win-modal`) → Close is correctly **sage
  green**. Sent both agents the production screenshot; both retracted. The real F3 cluster
  (Undo/Redo, IAP rows) was confirmed separately in code + production pixels.
- **#648 reframed, not closed.** `GameRoot` already uses a standard `.confirmationDialog`
  with a `.cancel` role. But **iOS 26 renders it as a centered card showing only "Leave"** —
  cancel is tap-the-backdrop only (verified: tap-outside returns to game). So the gap is
  *visible-cancel discoverability*; the real fix is the spec's already-planned designer
  bottom-sheet, not re-adding a `.cancel` that exists.
- **NOT bugs (verified intentional / environmental):** MS in-board "196" = deliberate
  classic-LED **raw-seconds** idiom (top chrome keeps M:SS; code suppresses one). Sudoku
  green / MS blue = intentional **per-game theming**. **Leaderboard does nothing** on the
  sim because the local Debug build carries **no Game-Center entitlement** (`codesign`
  confirmed 0) → GKLocalPlayer never authenticates → `select(.leaderboard)` no-ops; needs a
  signed TestFlight/device build. #491/#518/#536 all clean.

## Signed-in flows (user signed a sandbox Apple ID into the sim mid-session)

- **Resume pill** appears only when signed in (#515) and **actually restores** board +
  ticking clock + **conflict highlighting** (red + corner-triangle — a non-colour cue).
- **AdMob test banner** loads ("Test mode"). Game Center auto-authenticates at the *system*
  level (Settings shows the sandbox player) but the unentitled app build can't use it.

## Lessons

- **A debug launch hook can silently bypass theme/entitlement injection** — verify
  colour/Behaviour findings on the *production* path before filing (`-uitest-near-win-modal`,
  not `-uitest-near-win`). This caught a P2 false positive.
- **idb cell taps on this build are flaky** (first tap after a state change often swallowed;
  retry + re-`desc`). MS near-win beacon is **0-indexed** while a11y labels are **1-indexed**
  (`r8.c8` → "Row 9, Column 9") — off-by-one there hits a mine.
- **Read the code before trusting a reviewer's P1** — "no Cancel button" and "wrong colour"
  both dissolved under a 2-minute code/pixel check.

## Follow-on (same session, into 2026-06-30) — shipping the fixes + Play Again

Acted on the audit. Every fix went issue → worktree Developer → Leader review → CI → squash-merge.

| PR | What | Closes |
|---|---|---|
| #646 | Sudoku settings reads bundle version; silence IAP-cancel toast | #644, #645 |
| #651 | kill system-blue on undo/redo + Settings IAP rows (4 src lines + 13 re-recorded snapshots) | #650 |
| #654 | **Play Again** (same-difficulty) completion CTA — reverses SDD-003 Epic 4 "Close only" | #652 |
| #655 | snapshot test + sim-driveable DEBUG hook for Play Again | (verify #652) |
| #653 | this meeting log | — |

Still open: #647 (Pause tap target), #648 (Leave cancel discoverability — reframed: code has
`.cancel`, iOS 26 just doesn't render it as a visible button), #649 (MS revealed-cell grid).

**F1 sim-verified:** rebuilt from main → Sudoku Settings → Version now shows 2.6.0 (was 1.0.0).

### Play Again was the hard one — four agent defects the Leader caught

The feature reverses a deliberate spec decision (SDD-003 Epic 4 made the popup Close-only;
GC-entry relocation is the still-open #468). Got product sign-off first, then implemented via
subagents. Each agent pass needed Leader repair:

1. **Daily-board fork (real bug).** "Play Again" drew a *practice* puzzle even after a Daily —
   a daily is one-per-day. Guarded: Sudoku `SudokuLeaderboardRouting.isDaily(puzzleId:)`,
   Minesweeper `mode == .practice` → Daily stays Close-only.
2. **L10n left as English placeholders** (`needs_review`) — the gate passes on non-empty
   values, so "green" hid 6 untranslated locales. Filled real es/ja/ko/th/zh-Hans/zh-Hant.
3. **Whole-catalog reformat bled across worktrees.** An agent re-serialised
   `App/Sudoku/.../Localizable.xcstrings` (compact JSON, 7 k lines) which leaked onto the main
   checkout's working tree and failed the L10n fixture byte-sync gate on an *unrelated* PR.
   Fixed by rebuilding that branch clean from origin/main.
4. **A compile error the agent's "tests pass" claim masked.** The DEBUG hook used
   `.onChange(of: nearWinBoard)`, which requires `SudokuNearWinBoard: Equatable` (it's only
   `Identifiable`) → SudokuUI didn't compile. An *incremental* xcodebuild silently embedded the
   stale SudokuUI framework (so the Play Again button never appeared in the sim, looking like a
   wiring bug); only a **clean** build surfaced the real `error:`. Fix: observe
   `(nearWinBoard == nil)` (a Bool — no Equatable needed).

**End-to-end sim-verified** on a clean device build: completion shows Play Again (primary green)
above Close (secondary); tapping it cleanly dismisses + re-presents a fresh board with a reset
timer — the dismiss→present transition I'd flagged as a race is empirically clean.

### More lessons

- **Never trust a subagent's "tests pass" — re-run the gate.** #655's agent reported SudokuKit
  green while the file didn't compile; the snapshot test it added literally could not have run.
- **An incremental build can mask a compile error as a behaviour bug.** When sim behaviour
  contradicts correct-looking source, `rm -rf` the derived data and clean-build before debugging
  the code. (And `> dir/log` right after `rm -rf dir` silently fails — recreate the dir first.)
- **Worktree edits to shared resource files (xcstrings) can reformat-and-bleed.** Tell impl
  agents to insert keys surgically, never re-serialise; verify the catalog diff is +N lines, not
  a whole-file churn, before merging.
- **Reverting a spec decision is a product call** — surface the prior decision (SDD-003 Epic 4 /
  #468) and get sign-off before implementing, don't silently "fix" it.
