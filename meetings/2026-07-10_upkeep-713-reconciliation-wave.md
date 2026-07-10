# 2026-07-10 — #713 reconciliation wave: 13-vs-15 root cause, doc-hygiene batch, two dead-code deletions

Session id: n/a (single evening session, 2026-07-10 → 2026-07-11 00:xx, one session-limit
interruption recovered with no loss)
Mode: AI Collaboration Mode (Leader/Developer)

Arc: executed the prior wave's "next session" plan — reconcile #713's
13-vs-15 finding-count discrepancy and clear its untouched actionable items.
The reconciliation turned out to be the interesting part: the counts were
never comparable, because the Upkeep bot **overwrites the report issue's body
on every nightly run**. Three PRs merged (#751, #752, #753), #713 closed
(all actionable items from BOTH triaged rounds done or tracked), one
follow-up filed (#750).

## The 13-vs-15 root cause

- GraphQL `userContentEdits` on #713 shows github-actions rewrote the body on
  07-06, 07-07, 07-08, and 07-09. The owner's 15-finding triage (posted 07-09
  01:03Z) addressed the **07-08 21:12Z** report; the body everyone read
  afterwards was the **07-09 21:29Z** regeneration with a different
  13-finding list. Neither count is wrong; they index different rounds.
- Process rule adopted (memory + #713 comment): every triage pins the
  report's `_Generated_` timestamp, and a triage older than the body's last
  edit is expired until re-verified.
- All 13 claims of the 07-09 round + all 8 carryover items of the 07-08
  triage were re-verified LIVE against `main@28b68ff` before any fix
  (read-only verification agent).

## Shipped (all merged, all dual-code-reviewed)

| PR | What | Notes |
|---|---|---|
| #752 | docs: 13-file doc-hygiene wave (11 findings) | CR hard-reject round 1: the new minesweeper-v1.md SUPERSEDED banner contradicted the untouched "source of truth" line below it — fixed by mirroring sudoku-v2.5.md exactly |
| #753 | chore(uitest): drop dead `nearWinModalPuzzleId` + de-hardcode E2E launch-arg literals | Triage assumed a literal swap; verification showed E2E targets can't import GameAppKit — fixed by compiling `UITestLaunchArg.swift` directly into both E2E targets (existing `App/UITestsShared` technique), Project.swift touched |
| #751 | chore(composition): drop dead `SudokuAppComposition.bootMonetization()` | CR found the follow-on orphan: the source target's now-unused `AdsAdMob` product dep in Package.swift — folded into the same PR. Pre-existing `IAPStoreKit2` dep also looks unused (predates this diff) — noted in the PR, not touched |

## Non-PR dispositions

- ASCScreenshotRender duplication → **#750** filed (shared test-support
  target extraction). The audit's "byte-identical" claim was already false —
  headers/doc-comments have drifted, i.e. the mirror-principle failure mode
  the finding warns about has already begun.
- Screenshot placeholder PNGs → dup of #236; `Agents.md` symlink (4th
  consecutive round) + 3× asset-catalog `Contents.json` → won't-fix.
- #479 got a note: SDD-005 retcon + SDD-006 OQ-1..4 reconciliation (its
  routed #713 items 4–5) landed via #752.

## Gotchas recorded to memory

- **Upkeep body overwrite** (above) — `reference/upkeep-issue-body-regenerated-nightly`.
- **"does not close #713" still auto-closed #713**: GitHub's keyword parser
  matches the `close #NNN` substring and ignores negation — the three PR
  bodies unintentionally closed the issue on first merge (harmless here,
  the wave was closing it anyway) — `feedback/pr-body-does-not-close-still-autocloses`.
- One CR agent died at the session-limit stall; all three impl worktree
  commits survived intact (salvage-check first, then resume) and the dead
  reviewer's mechanical checklist was re-run inline by the Leader.

## Open queue (unchanged unless noted)

- **#750** (new) — ASC-screenshot render test-support extraction.
- **#741** — MS board ternary-literal l10n gaps. **#747** — #721 follow-ups.
- **#716** / **#722** — product proposals (notes 3×3 grid; digit-first input).
- **#705** — blocked on per-game unique practice-id design.
- **#667**, **#479**, **#286**, **#166** — carried unchanged.

## Next session

#741 or #747 are the smallest ready items; #716/#722 await owner scheduling;
tonight's Upkeep run may open a fresh report round — triage it against its
own `_Generated_` timestamp per the new rule.
