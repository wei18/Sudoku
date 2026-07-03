# 2026-07-04 — upkeep #631 close-out, 2B completion unification (macOS-verified), TF uploads

Arc: session opened with a codebase priming pass + status check → triaged and
fixed upkeep report #631 in one docs PR → the owner picked "option 3" for the
long-deferred 2B (implement now WITH real macOS runtime verification, rejecting
both blind-modify and further deferral) → 2B shipped with the repo's first
working macOS XCUITest run → both apps uploaded to iOS TestFlight → tooling
friction filed as backlog.

## Shipped (all merged to main / uploaded)

| Artifact | What | Refs |
|---|---|---|
| PR #666 | 9 upkeep findings + 1 CR catch: SDD-006 RFC line-edited to the Minesweeper template, v2.5 review doc superseded banner, MS prototype retitle, zh-Hant "On v2.6" callout, lint.yml SSOT comment, mise-task index rows, skills README (en+zh-Hant) + CLAUDE.md → 2-plugin marketplace reality (20+12=32) | closes #631 |
| PR #669 | **2B**: Sudoku completion unified to the in-board `CompletionOverlayScaffold` overlay on every platform; macOS pushed `.completion` terminal route deleted; `exitToHub` (modal→dismiss / push→pop) makes Close always land on the hub; terminal pause-button guard mirroring MS | #667 (2B done) |
| Issue #667 | 2B/2C tracking issue (2B now closed out in-comment; 2C deferred) | — |
| Issue #670 | tf:upload backlog: source-aware archive reuse + parallel multi-app uploads | — |
| TestFlight | Sudoku iOS build `202607032324` + Minesweeper iOS build `202607032326`, both v2.6.0, prod AdMob per policy | — |

## #631 triage — two non-defects worth remembering

- **Agents.md/CLAUDE.md "hand-copy drift"** was a false positive: `Agents.md` IS
  a git symlink (mode 120000, commit 4f0fe03) — the audit tooling resolved it and
  hashed both as regular files. The recommended fix was already the shipped state.
- The byte-identical preview screenshots are the already-tracked #236 harness gap.
- CR round 2 caught that the "On v2.6" README callout itself carried a stale
  claim — "Minesweeper is 1.0" — while `App/Minesweeper/Info.plist` has shipped
  2.6.0 since a3e80d7. Fixed in both READMEs inside #666. A doc-staleness PR
  faithfully translating a stale source duplicates the error; verify claims
  against the source of truth, not the sibling doc.

## 2B — the "third option" and the macOS verification breakthrough

Last session ended on a binary: blind-modify 2B (code-review-only) vs defer.
Reframed as a false dilemma — the dev machine IS a Mac on macOS 26 — and the
owner chose option 3: implement with real macOS runtime verification.

- Developer (sonnet, worktree) shipped the diff: push-`.completion` branch
  deleted, `shouldPresentCompletionOverlay` un-gated from `path == nil`, new
  `exitToHub` pops exactly the board's own stack entry, pause button hidden at
  terminal. Correctly KEPT `AppRoute.completion` — `DailyHubViewModel.openCompleted`
  (#379 re-view-solved-daily) still pushes it. MinesweeperKit byte-identical.
- **macOS verification**: terminal TCC blocks osascript/screencapture, but
  `xcodebuild test` on `platform=macOS` needs no permission. XCUITest on
  SwiftUI-Mac required a workaround chain: `element.tap()` dies on INFINITY
  activation points, `app.coordinate` resolves (-inf,-inf), `hittable` is not a
  predicate key → anchor clicks on the WINDOW element + element frames. A
  temporary (reverted) `-uitest-near-win` BoardLoaderView hook made the
  push-context board winnable in one move. The production flow then passed:
  Practice → push board → win → overlay → Close → back on the hub (36.9s).
  Pattern saved to session memory (`macos-xcuitest-coordinate-clicks`); worth
  productizing if macOS E2E becomes recurring.
- Dual CR: 2× APPROVE. Sonnet traced every `.board` pusher to prove the
  one-entry pop always lands on a hub, and verified no iOS double-present
  regression (the #611 concern the deleted `path == nil` gate used to guard).

## TF uploads — first-run failure mode

Sudoku's first upload attempt died in altool's multipart session: 748 ×
"WILL RETRY PART 1. Checksums do not match" after transient offline errors —
the session was poisoned; archive/export were fine. Kill + fresh run succeeded
with zero retries. Both apps then uploaded clean. Friction → #670 (skip
re-archive when source unchanged; parallelize the upload step).

## Decisions

- **2C stays deferred** (leaderboard-fetch-on-loss guard): since Epic 4 the
  completion popup renders `state: .hidden`, so the wrong fetch is invisible;
  batch it with the future change that re-exposes the leaderboard zone (which
  also owns the `onRetryLeaderboard` no-op stub + unreachable state branches).
- **SUBMISSION-CHECKLIST.md v1.0 follow-up is now timely**: the checklist still
  scripts Minesweeper as ASC "version 1.0", but today's TF build went up as
  2.6.0 — an ASC "1.0" version record would not accept it. User-owned: confirm
  what ASC shows, then the doc retitle is mechanical.

## Open

- 2C (deferred, #667) · SUBMISSION-CHECKLIST v1.0→2.6 (pending owner's ASC
  check) · #670 tf:upload ergonomics · #479 new-game scaffold epic (untouched).
