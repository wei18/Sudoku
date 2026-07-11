# 2026-07-11 — backlog burn wave (#755 #771 #716 #705 #722)

Session id: n/a (background job, same-day follow-on to the #741/#747 closeout)
Mode: AI Collaboration Mode (Leader/Developer, dual review on every PR)

Arc: owner pointed at the queue ("get gh issues, pick one", then "continue
next backlog issue" after each close). Five issues closed end-to-end, five
PRs merged, one follow-up filed and then also closed within the wave
(#755 review finding → #771). Every PR passed dual review in one round;
three review findings were applied pre-push (never post-merge).

## #755 → PR #776 (merged 6ecdae8)

- Cross-app: the board-cell VoiceOver coordinate prefix ("Row R, Column C")
  was bare interpolation in BOTH `MinesweeperCellButton` and Sudoku's
  `BoardCellView`. One shared format key `Row %lld, Column %lld` × 7 locales
  in both catalogs (mirror principle: identical entries).
- Terminology split is deliberate: zh-Hant 「第 %lld 列，第 %lld 欄」 vs
  zh-Hans 「第 %lld 行，第 %lld 列」 (Taiwan vs Mainland row/column words —
  same divergence Excel ships).
- Review catch (sonnet): the commit's "en assertions stay green via key
  fallback" was an overstatement — `BoardViewTests.labelFor(cell:)`
  re-implements the label in English and never exercises catalog routing.
  Message amended before push.
- Review catch #2: `MinesweeperE2ETests` full-label query comment claimed
  locale-independence — false since #741/#755. Folded into #771's scope.

## #771 → PR #777 (merged f9f7111)

- Sudoku half of #756's bug class: `conflict/given/value/Empty` state
  suffixes in the same accessibilityLabel. 4 keys × 7 locales, Sudoku
  catalog only (`conflict %lld` / `given %lld` / `value %lld` / `Empty`);
  `Empty` reuses the MS catalog's translations verbatim for cross-app
  glossary consistency.
- Leader catch on the dev's E2E comment rewrite: it still claimed the
  digit-pad labels ("Digit 1"…"Digit 9") are hardcoded English — they are
  catalog-routed via `Digit %lld` (ja 「数字 %lld」 etc.). Only
  `game.completion.hero` (an accessibilityIdentifier) is genuinely
  locale-independent. Fixed pre-commit; both E2E headers now say the suites
  are valid under the simulator's default en locale only.

## #716 → PR #778 (merged b4a5291) — premise refuted, not implemented

- The issue (from #688 item 4 / audit-sud-13) claimed pencil notes render as
  a "top-left vertical list". False against all of history: `PencilNotesGrid`
  has rendered the positional 3×3 mini-grid (digit N fixed in quadrant
  (N-1)/3,(N-1)%3) since its introduction in 99f38ea and was never modified;
  it is the only notes renderer with a single call site.
- Root cause the false finding survived: zero snapshot coverage of notes
  rendering — every board fixture passed `noteMask: 0`.
- Disposition: test-only PR adding `BoardViewPencilNotesTests` with
  visually diagnostic patterns ({1,5,9} diagonal, {2,4,6,8} edge midpoints,
  1–9 full grid, {3,7} corners) as the standing counter-evidence +
  regression lock. The sonnet reviewer was explicitly tasked to REFUTE the
  already-implemented conclusion and could not (renderer reality, history,
  test-path fidelity, rendered pixels, docs all corroborate).
- Process note: new test split into its own file — `BoardViewTests.swift`
  sits at the SwiftLint 400-line ceiling (422 with the test inlined).

## #705 → PR #779 (merged 99ef09b)

- MS practice personal bests. Dev's design improvement over the dispatch
  spec, verified before adoption: reuse the board's existing generation
  `seed` (already `UInt64.random` once per new practice game at both
  production callsites, already persisted verbatim through save/resume
  because it reproduces the mine layout) instead of adding a new snapshot
  field. Result: zero schema change, no version bump, no legacy-decode
  fallback; resume+win dedups as the same game for free.
- Id format mirrors Sudoku: `practice-{crockfordBase32(seed)}-{difficulty}`.
  Sudoku's encoder is `internal`, so MS carries a byte-identical private
  copy pinned by 7 shared test vectors (0→"0" … UInt64.max→"FZZZZZZZZZZZZ")
  against cross-app drift.
- `submitDailyTimeIfWon()` → `submitWinIfWon()`; GC submission stays
  strictly daily-only (#329, permanent); the `didSubmitWin` latch now arms
  on any win (previously practice never latched — latent-bug-shaped).
- Review catch (sonnet): `.replayDailyBoard` builds `mode: .practice` with
  `personalRecordStore` nil only by parameter default — a future wiring
  would silently record unscored daily replays as practice PBs. The
  omission is now an explicit comment at the route builder.

## #722 → PR #781 (merged 8469492)

- Sudoku digit-first input, recorded default confirmed: implicit dual-mode,
  no settings toggle. Keypad tap with no selection arms the digit
  (`.borderedProminent` + `.isSelected` trait, no new strings/tokens);
  empty-cell taps place through the EXISTING `placeDigit`/`toggleNote`
  paths (mistakes/undo/completion/persistence unchanged); tapping a
  user-filled cell falls back to select-and-disarm.
- Invariant `armedDigit != nil ⟺ selection == nil`: two mutator sites
  (`select()` disarms unconditionally incl. arrow keys; `armDigit()` clears
  selection) + construction/test-seam asserts (review nit, adopted).
  `armedDigit` is never persisted.
- Edge call: compact keypad's `remaining == 0` disable now applies only
  when a selection exists, so an exhausted digit can still be armed for
  notes. Given cells stay inert while armed (no Button wrapper per #473) —
  same as cell-first; documented at the dispatcher.
- Known non-goal: macOS keyboard digit entry ignores armed state (keyboard
  flow always requires a selection; no natural arm gesture there).

## Process notes

- Dual review (haiku mechanical + sonnet fact-check/adversarial) ran on all
  five PRs; every round-1 finding was substantive and applied pre-push.
- Haiku's numeric claims need spot-checks: one report stated line counts
  (114/122/297) that disagreed with `wc -l` ground truth (63/71/246) even
  though its PASS/FAIL conclusions held.
- Subagent reviewers twice went idle without sending their report; later
  dispatch prompts say "SEND your report to main via SendMessage" explicitly,
  which fixed it.
- SudokuKit full-suite local segfault (known, pre-existing): all Sudoku
  verification ran as `--filter` batches; MinesweeperKit ran full
  (232→240 tests over the wave — only PR #779 touched MS tests. PR #779's
  own commit message says "was 218/36"; that baseline was stale, caught by
  this log's fact-check — the same self-reported-number trap the note
  above warns about).
