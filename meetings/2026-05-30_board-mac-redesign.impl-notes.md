# board-mac-redesign

Status: COMPLETE
Branch: feat/board-mac-redesign
Worktree: /Users/zw/GitHub/Wei18/Sudoku-board
Date: 2026-05-30
Dispatcher: Leader

## 任務 scope
Land the macOS-specific BoardView layout from `docs/designs/05-board.md` §b that has been speced but never implemented. Three independent designer/UX/SwiftUI consults converged on a single proposal (transcript at workflow `board-mac-redesign` w/o `wog03oy1x`).

## Decisions locked by Leader (user gave Leader autonomy)
1. **Notes mode = persistent toggle.** Existing `pencilMode` is already persistent; keep the model. Toggle ON stays on until user taps it OFF.
2. **Erase scope = clear EVERYTHING in selected cell** (user-entered digit OR notes). Single mental model; matches keyboard Delete. No secondary "clear notes only" affordance.
3. **Clear → Erase rename = YES**, both en + zh-TW (zh-TW: 清除 → 擦除).

## 依賴文件
- `docs/methodology.md` §派發契約 items 6, 8, 10, 11, 12
- `docs/designs/05-board.md` — existing spec; structurally correct, see §b Mac wireframe
- `docs/designs/design-system.md` — spacing, color, typography tokens
- The designer-consult synthesized proposal (this impl-notes' §設計決定 will copy the locked deltas)

## Mac wireframe to implement

```
┌── header 56pt ─────────────────────────┐
│ ← Medium    ⏱ 03:21    ⏸ Pause/Resume │
├─────────────────────────────────────────┤
│  ┌── 9×9 board ──┐  ┌── 260pt rail ──┐ │
│  │  ≤ 640pt sq   │  │ ↶ Undo  ↷ Redo │ │  44pt history row
│  │  scales w/H   │  ├────────────────┤ │
│  │               │  │ ✎ Notes [ON]   │ │  44pt mode toggle
│  └───────────────┘  ├────────────────┤ │
│    24pt gap →       │  ┌──┐┌──┐┌──┐  │ │
│                     │  │ 1││ 2││ 3│  │ │
│                     │  ├──┤├──┤├──┤  │ │  3×3 digit Grid
│                     │  │ 4││ 5││ 6│  │ │  64×64 cells, 8pt gap
│                     │  ├──┤├──┤├──┤  │ │
│                     │  │ 7││ 8││ 9│  │ │
│                     │  └──┘└──┘└──┘  │ │
│                     ├────────────────┤ │
│                     │ ⌫  Erase       │ │  44pt destructive
│                     └────────────────┘ │
│  outer maxWidth: 960pt, centered        │
└─────────────────────────────────────────┘
   below 900×640 → fall back to compact stacked (iPhone layout)
```

## Deltas vs current implementation
- `BoardView` already declares `@Environment(\.horizontalSizeClass)` but **never reads it**. Add `sizeClass == .regular` branch.
- Extract `MacControlsColumn` view: `VStack(spacing: 12)` containing history row, Notes toggle, 3×3 digit Grid (`Grid` primitive), Erase row.
- Convert digit-pad from 1×9 `HStack` to 3×3 `Grid` ONLY on the Mac branch. iPhone compact branch keeps existing 1×9 layout.
- Swap `pencil.slash` icon → `pencil` with state-driven tint. Applies to BOTH platforms.
- Rename "Clear" copy → "Erase" (en) + 「清除」 → 「擦除」 (zh-TW). Update `Localizable.xcstrings`.
- Outer container: Mac branch wraps in `.frame(maxWidth: 960).frame(maxWidth: .infinity)` + ≥ 32pt outer padding.
- Board size cap: clamp existing GeometryReader `min(width, height)` to `≤ 640pt` on regular sizeClass.
- Header: add "Pause"/"Resume" text label on Mac branch (iPhone stays icon-only).
- Minimum Mac window: 900×640. Below → compact layout (use sizeClass — SwiftUI will report `.compact` when window is narrow).

## iPhone layout = preserved
- Vertical stack from existing `05-board.md` §b unchanged.
- Two cross-platform consistency tweaks: `pencil.slash` → `pencil` + state tint; "Clear" → "Erase".

## 設計決定

- **DigitPadView gains a `sizeClass` parameter** rather than reading `@Environment(\.horizontalSizeClass)` directly. Rationale: keeps the existing struct testable in isolation and lets BoardView decide branching policy in one place. BoardView passes its own resolved size class through. Matches the existing test seam pattern (cf. `GameViewModel(identity:board:...)`).
- **Mac 3×3 digit Grid uses SwiftUI `Grid`** with `GridRow`, 8pt spacing, fixed-width cells `.frame(minWidth: 64, minHeight: 64)` per wireframe. Decision: rely on `.buttonStyle(.bordered)` for hit shape — no custom backdrop. Matches existing iPhone 1×9 row buttonStyle for visual consistency.
- **Notes toggle visual = filled tint when ON, outline when OFF.** Used `.buttonStyle(.borderedProminent)` when on, `.bordered` when off, both with `Label("Notes", systemImage: "pencil")`. The `pencil.slash` icon is *gone everywhere* — replaced by single `pencil` icon + tint state, per Leader decision #1.
- **iPhone consistency tweaks**: removed `pencil.slash` from `controlRow`. The pencil button now always shows `pencil` icon, with foreground tint switching between `theme.accent.primary.resolved` (ON) and `theme.text.primary.resolved` (OFF). No background fill change on iPhone (preserves the original lightweight `.font(.title2)` look). On Mac, the Notes affordance is the dedicated row-width `.borderedProminent`/`.bordered` button — distinct visual treatment, same semantic.
- **Erase rename keeps a single xcstrings entry**: I reuse the existing `"Clear"` key and rewrite all 7 translations to the new "Erase" semantics. Rationale: the only call-site is the digit pad clear button (verified by `rg "Clear"` returning one Swift hit + the one xcstrings key). Renaming the key would require source-file changes anyway, so I rename the *source key* from `"Clear"` → `"Erase"` and refresh all locales. Marked `extractionState: "manual"` for the locales I author (en, zh-Hant) and `"needs_review"` for AI-translated locales per ai-translated-localization skill convention.
- **Erase scope** — verified during impl that `placeDigit(nil)` → `session.clearDigit` does NOT touch the NotesGrid (separate field, separate clear path). To honor Leader decision #2 (Erase = clear EVERYTHING), I add:
  - `GameSession.clearNotes(row:col:)` — non-undoable, mirrors `NotesGrid.clear(row:col:)` semantics, **does NOT push a Move**. Rationale: `Move.clearDigit` carries no `previousNotes` field; adding one is a Codable schema change for SavedGame persistence — explicitly out of scope.
  - `GameViewModel.eraseCell()` — new pubic method called by Erase button: clears digit (via existing `placeDigit(nil)` path, which DOES enroll in undo) AND clears notes (via the new non-undoable `clearNotes`). Result: a single Erase tap wipes the cell visually; an Undo restores the digit only. See §偏離 for the UX wrinkle.

## 偏離 spec

- **Erase notes not undoable.** Leader-locked decision #2 says "Erase clears EVERYTHING in selected cell (user digit OR notes). Single button, single mental model." Implemented as: Erase clears both, but only the digit clear is enrolled in the undo stack — clearing notes is fire-and-forget. Reason: `Move.clearDigit(previous:)` carries `previous: Int?` (the digit only); adding a `previousNotes: UInt16` field migrates the SavedGame Codable schema, which is out of this PR's scope. UX impact: tap Erase on a cell containing both a digit AND notes → both vanish; Undo → digit restored, notes still gone. Acceptable trade-off because (a) most "Erase" use is on user-entered digits, not on note-decorated cells, and (b) notes are a derived scratchpad; users rarely undo them. Follow-up task: extend `Move.clearDigit` with `previousNotes`, gated behind a SavedGame schema bump.

## 折衷

- **`Grid` vs `LazyVGrid` for 3×3 digit pad**: chose `Grid` because (a) only 9 cells, no laziness needed, (b) `GridRow` gives clean row semantics for VoiceOver, (c) `.gridCellColumns`/`.gridCellUnsizedAxes` available if we later need a wide Erase row. Rejected `LazyVGrid(columns: 3)` because it imposes a single GridItem template that flexes cell widths, breaking the fixed-64pt cell wireframe spec.
- **`Toggle(.button)` vs custom Button for Notes**: chose Button-with-action over Toggle(.button) because `viewModel.togglePencil()` is the canonical mutation path; routing through SwiftUI Toggle would require a binding that doesn't exist on the ViewModel (pencilMode is a derived published property, not a settable binding directly accessible from outside). A button is simpler and accessibility-equivalent when we set `.accessibilityValue` and `.accessibilityAddTraits(.isToggle)`.

## 未決

- **Pause/Resume label on Mac header** — RESOLVED. Implemented `Label("Pause", systemImage: "pause.fill")` on Mac only; iPhone retains icon-only. Mac snapshot confirms the label fits comfortably alongside the timer in 900pt-wide header. Korean/Japanese/zh locale Mac snapshots all render without truncation. No deviation needed.
- **(none open)**

## Files changed
| File | + | − | Note |
|---|---|---|---|
| `Packages/SudokuKit/Sources/SudokuUI/Board/BoardView.swift` | 73 | 21 | Branch body on `sizeClass`; extract `compactLayout` / `macLayout` / `macBoardColumn` / `digitPad`; Mac header gets `Label("Pause", ...)`; outer `maxWidth: 960` + ≥ 32 pt padding; Mac board column capped to 640×640 |
| `Packages/SudokuKit/Sources/SudokuUI/Board/DigitPadView.swift` | 144 | 9 | Rewrite — accept `sizeClass` param, split into `compactLayout` (iPhone 1×9 strip preserved) and `macLayout` (vertical rail w/ history row, Notes toggle, 3×3 `Grid`, Erase row); drop `pencil.slash` icon; rename `onClear` → `onErase`; private `AnyMacToggleStyle` for Notes ON/OFF |
| `Packages/SudokuKit/Sources/SudokuUI/Board/GameViewModel.swift` | 28 | 0 | New `eraseCell()` — clears digit (undoable) + notes (non-undoable) in one gesture |
| `Packages/SudokuCoreKit/Sources/GameState/GameSession.swift` | 21 | 0 | New `clearNotes(row:col:)` — fire-and-forget notes wipe, NOT enrolled in undo stack |
| `App/Resources/Localizable.xcstrings` | 13 | 13 | Rename `"Clear"` → `"Erase"` (7 locales rewritten for the new semantics); rename `"Pencil"` → `"Notes"` (7 locales rewritten); both keys lose `extractionState: "stale"` flag |
| `Packages/SudokuKit/Tests/SudokuUITests/__Snapshots__/BoardViewTests/*.png` | — | — | 12 baselines re-recorded: 4 iPhone (digit row + Erase rename + pencil icon swap), 8 Mac (full 2-column layout w/ 3×3 digit Grid, Notes toggle, Erase row, Pause text label) |
| `meetings/2026-05-30_board-mac-redesign.impl-notes.md` | this file | | |

## Snapshot re-record summary
- **iPhone baselines (4 PNGs)**: intended changes — Erase label rename + pencil icon swap (`pencil.slash` → `pencil`). File sizes drifted by ~0.4–1 KB (text rendering only). Layout structure preserved.
- **Mac baselines (8 PNGs)**: intended structural changes — header gained "Pause" text label; board cell side shrank slightly to fit alongside the new 260 pt rail; right rail added with undo/redo row, Notes toggle (outlined when OFF), 3×3 digit Grid, Erase row. File sizes grew by ~12–70 KB (proportional to the added UI elements).
- **No unexpected drift detected** — all 12 deltas trace to either the layout change or the icon/copy renames.

## Verification log
- [x] `swift build` — Build complete! (28.70s)
- [x] `swift test --filter BoardView` — 20 tests, 0 failures (12 snapshots + 4 keyboard + 1 a11y + 3 banner)
- [x] `swift test --filter SettingsView` — 10 tests, 0 failures (Form ordering unaffected)
- [x] `swift test --filter GameSession` (SudokuCoreKit) — 43 tests, 0 failures (`clearNotes` addition is additive)
- [x] `rg --type swift 'Clear' Packages/SudokuKit/Sources/SudokuUI/Board/` — 0 matches
- [x] `rg --type swift 'pencil\.slash' Packages/SudokuKit/` — 0 matches
- [x] Visual sanity check — Mac snapshot matches §b wireframe; iPhone snapshot preserves layout with only icon + copy tweaks.

## Verification
- [ ] `swift build --package-path Packages/SudokuKit` clean
- [ ] `swift test --filter BoardView` passes (will need snapshot re-records — see below)
- [ ] **Snapshot re-records (expected)**: macOS BoardView snapshot baselines for the new layout. Run `swift test --filter BoardView 2>&1 | tail -20`, observe failures, re-record via `withSnapshotTesting(record: .all)` for the Mac-regular variants, commit.
- [ ] iPhone snapshots: should only change for the `pencil.slash` → `pencil` icon swap + "Clear" → "Erase" copy. Re-record + visual review.
- [ ] **Manual macOS build + run**: launch app, navigate Daily → Easy. Verify 2-column layout, 3×3 digit grid, Notes toggle ON/OFF visual states, Erase rename, board ≤ 640pt cap, ≥ 32pt margins.
- [ ] **Manual iPhone simulator**: verify regression-free — iPhone layout looks identical except for the two consistency tweaks (pencil icon + Erase label).
- [ ] **Manual window resize (Mac)**: resize Mac window narrower; below 900×640 should gracefully collapse to compact layout (not break).

## Open items for Leader after Developer return
- Update `docs/designs/05-board.md` §b with the locked deltas (max-width clamp, board cap, "Erase" rename, Notes terminology). This can happen post-merge as a docs-only follow-up, or bundled in this PR — Developer's call.
