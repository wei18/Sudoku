# ios-board-unified-action-row

Status: COMPLETE
Branch: fix/210-ios-board-unified-action-row
Worktree: /Users/zw/GitHub/Wei18/Sudoku-ios
Date: 2026-05-30
Dispatcher: Leader

## 任務 scope (closes #210)
Consolidate iPhone BoardView's two secondary-action rows (Undo / Redo / Notes above the digit strip + Erase below) into a single unified action row positioned BETWEEN the board and the digit strip. Three independent designer/UX/SwiftUI consults converged on this MINOR_TWEAK shape.

## Leader-locked decisions (synth recommendations all accepted)
1. **Erase = icon-only** (no "Erase" text), `delete.left` glyph with `.accessibilityLabel("Erase")`.
2. **Action row order**: `↶ Undo  ↷ Redo  ✎ Notes  ⌫ Erase` (Erase rightmost = right-thumb resting zone).
3. **No migration tooltip** — icon clarity + 80pt physical move small enough for self-discovery.

## 依賴文件
- `docs/methodology.md` §派發契約 items 6, 8, 10, 11, 12
- Synth report at workflow `board-ios-redesign` (run wd9v91pyy) — verdict MINOR_TWEAK
- Mac counterpart in `DigitPadView.swift` `macLayout` (post-#211 baseline) — cross-platform consistency reference: same icons + tint behavior; only geometry diverges

## iPhone wireframe (target)

```
iPhone (compact, post-tweak)
┌──────────────────────┐
│ < Medium  ⏱ 3:21 ⏸    │
├──────────────────────┤
│   ┌── 9×9 board ──┐  │
│   └────────────────┘ │
│                      │
│   ↶   ↷   ✏   ⌫     │  ← unified secondary row, 4 × 44pt
│ ┌─┬─┬─┬─┬─┬─┬─┬─┬─┐ │
│ │1│2│3│4│5│6│7│8│9│ │  ← primary, unchanged
│ └─┴─┴─┴─┴─┴─┴─┴─┴─┘ │
└──────────────────────┘
```

## Deltas vs current `DigitPadView.compactLayout`

- Remove the standalone bottom `HStack { Spacer; Button("Erase"); Spacer }` row entirely.
- The existing above-pad control row (Undo + Redo + Notes) reorders to put Erase in (4 buttons total). Buttons remain icon-only.
- **Apply `.frame(minWidth: 44, minHeight: 44)` to each icon button** — fixes a pre-existing HIG sub-44pt tap target bug surfaced by Consult 3.
- Move the entire unified row position: place it BETWEEN board and digit strip (not below; not above — synth overruled Consult 2's "below the pad" placement, kept the digit strip in the thumb-resting bottom zone).
- Drop the "Erase" text label from the Button; keep `.accessibilityLabel("Erase")` for VoiceOver.
- Use `.tint(theme.accent.primary.resolved)` semantics on the Notes button matching the Mac branch (already done, just confirm consistency).

## iPhone SE constraint check (375pt width, 343pt usable after 16pt outer padding)
- 4 × 44pt buttons distributed across 343pt → ~77pt per slot (well above 44pt min)
- Digit strip unchanged (~29pt wide × 44pt tall cells; HIG-compliant via height compensation per existing convention)
- Vertical budget: header ~56 + board 343 + secondary row 44 + digit strip 44 + spacing ~32 ≈ **519pt** in 667pt SE height → ~148pt safe-area headroom. **Frees ~50pt vs current layout.**

## Mac branch = unchanged
The Mac `DigitPadView.macLayout` path (post-#211) is NOT touched. The Mac/iPhone divergence is intentional: Mac has 260pt of dedicated column width where a 3×3 grid fits + side-rail design works; iPhone needs horizontal + thumb-zone placement.

## 設計決定
- `compactControlRow` carries all 4 secondary actions in a single `HStack(spacing: 0)`; each child uses `.frame(maxWidth: .infinity, minHeight: 44)` on the label and an outer `.frame(minWidth: 44, minHeight: 44)` on the Button. Result: equal distribution across the 343pt usable width (~85pt per slot) with HIG-compliant 44pt minimum tap targets.
- The unified row visually sits BETWEEN board and digit strip because BoardView's iPhone `compactLayout` sequences `boardWithOverlay → (banner?) → digitPad`, and the unified row is now the first row inside `DigitPadView.compactLayout` (`compactControlRow` before `digitRow`). No BoardView change required — kept the modification surface to a single file.
- Notes tint behavior reuses the existing `pencilMode ? theme.accent.primary.resolved : theme.text.primary.resolved` foregroundStyle on the pencil glyph (unchanged from prior compactControlRow). Matches Mac branch tint semantics symbolically; geometry diverges intentionally (icon-only on iPhone vs Label+text on Mac, per Leader-locked decision 1).
- Header comment updated to reflect new iPhone topology and to drop the stale `pencil.slash` reference (the icon was retired in #211; the comment was the only residue).

## 偏離 spec
- None. All 3 Leader-locked decisions implemented as specified. Step order from synth followed verbatim.

## 折衷
- `HStack(spacing: 0)` (rather than the prior `spacing: 24`) — relying on `.frame(maxWidth: .infinity)` per button for even distribution. Equivalent visual to "evenly spaced with padding" but simpler / more responsive across iPhone SE 375pt and iPhone 16 Pro Max 430pt widths without bespoke spacing math.
- Did not change Button.buttonStyle — default `.bordered`-equivalent system styling renders consistently with the digit strip (see snapshot). Considered explicit `.buttonStyle(.bordered)` for consistency but the default rendering on iOS 18 produces the expected pill shape, so kept the change surface minimal (Karpathy §3 surgical changes).

## 未決
- None. All 5 verification steps green.

## Files changed
| File | + | − | Note |
|---|---|---|---|
| Packages/SudokuKit/Sources/SudokuUI/Board/DigitPadView.swift | 23 | 16 | compactLayout: remove standalone Erase row; compactControlRow: 4-button unified row with 44pt frames; header comment refresh |
| Packages/SudokuKit/Tests/SudokuUITests/__Snapshots__/BoardViewTests/*iPhone*.png | — | — | 6 baselines re-recorded (3 scenarios × 2 themes); Mac baselines untouched |

## Verification
- [x] `swift build` clean — "Build complete! (30.95s)"
- [x] `swift test --filter BoardView` passes — 20/20 after re-record
- [x] **Mac snapshot tests unchanged** — `git status` shows zero Mac .png in diff; all 6 Mac snapshot tests passed on the failing iPhone run, confirming Mac branch logically untouched
- [x] `rg --type swift 'pencil\.slash' Packages/SudokuKit/` returns 0 results (the prior comment hit was scrubbed)
- [x] Visual verification via snapshot rendering: Undo · Redo · Notes · Erase row distributes evenly across digit-strip width, icon-only, sits between board and digit strip per wireframe (see `snapshotInProgress_iPhone_light.png`)
- [x] iPhone SE budget: layout in spec fits within 667pt height per impl-notes calculation; snapshot rendering at iPhone 16 width confirms no clipping
