# 2026-07-11 — #741 board l10n + #747 acknowledgements follow-ups

Session id: n/a (continuation of the 2026-07-10 #713 reconciliation session)
Mode: AI Collaboration Mode (Leader/Developer)

Arc: owner pointed at the queue ("continue #741 when done, then look at #747");
both closed end-to-end this wave. Two PRs merged (#756, #759), two issues
closed (#741, #747), one filed (#755), one filed-then-withdrawn (#758).
Both PRs took exactly one review round-trip each — and both round-1 catches
were real (an intra-run pin drift and, on the earlier wave, a banner
contradiction), reinforcing the dual-review setup.

## #741 → PR #756 (merged)

- Fixed the two named sites plus one swept same-class site:
  Flag/Unflag context-menu + VoiceOver action (`flagToggleTitle`), a11y
  `stateDescription` (Hidden/Flagged/Mine/Empty), `statusText`
  (Ready/Playing/Paused/You won/Boom), pause-toggle (Resume/Pause).
- 8 new catalog keys × 7 locales; 5 keys reused (Flag #731, Pause/Resume
  #434, You won/Boom #421) — comments updated, no duplicates.
- Pattern confirmed: `String(localized:bundle:.main)` — the MS catalog is an
  app-target resource (`App/Minesweeper/Resources/Localizable.xcstrings`),
  so `.module` would be wrong; matches #731 byte-for-byte.
- Snapshots: 197/197 MinesweeperUITests pass with byte-identical PNGs (en
  renderings unchanged) — the safe signature for a pure l10n-plumbing PR.
- Sweep boundary honored: the `"Row R, Column C"` coordinate
  accessibilityLabel is unlocalized in BOTH apps (Sudoku's `BoardCellView`
  mirrors it), so it was filed as cross-app issue **#755** instead of being
  half-fixed in MS only.

## #747 → PR #759 (merged) + owner ruling

- **Item 2 owner-ruled won't-fix (2026-07-11): Settings.bundle Root.strings
  stays English** — the 7-locale policy does not extend to the system-Settings
  pane. Recorded on the issue.
- Item 3: test-only deps (swift-custom-dump / swift-snapshot-testing /
  swift-syntax / xctest-dynamic-overlay) excluded from both apps' generated
  Acknowledgements; page now lists runtime deps only (AdMob + UMP).
  **LicensePlist schema trap** (now in memory + yml comments): only a
  top-level `exclude:` with `- name:` dict entries works; `options.excludes`
  and bare-string lists are silently ignored. Verify via the per-package
  "was excluded according to config YAML" WARNING lines in the gen log.
- Item 1: `Packages/MinesweeperKit/Package.resolved` committed (gitignore
  negation) for mirror parity, pins byte-identical to SudokuKit's.
  **Round-1 reject was a real catch**: the Developer's `swift package
  resolve` had silently drifted 4 pins to newer versions (AdMob 13.6.0 vs
  Sudoku's committed 13.4.0) while the commit claimed identity. Fix: copy
  the reference resolved, swap only `originHash`, verify `swift build`
  leaves the md5 unchanged. **#758** (AdMob skew), filed on the drifted
  output before the reject landed, was withdrawn as wrong-premise.
- One transient API 502 killed the Developer mid-task; the worktree salvage
  + targeted-resume pattern recovered it with zero loss (pwd/branch guard in
  the resume message, per the standing incident memory).

## Open queue deltas

- Closed: #741, #747. New: **#755** (cross-app coordinate-a11y l10n, S).
- Withdrawn: #758. Everything else carries unchanged (#750, #744, #722,
  #716, #705, #667, #479, #286, #166).

## Next session

#755 is the smallest ready item (cross-app, one shared format key × 7
locales). #744 still needs owner elaboration; #716/#722 await scheduling;
#705 stays design-blocked.
