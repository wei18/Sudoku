# `docs/designs/` — v1 visual design artifacts

Text-based design spec for the 8 Views defined in `docs/v1/design.md §How.5.1`. No `.fig` / `.sketch` binaries — most artifacts here are reviewable in plain markdown + reproducible in a SwiftUI Preview; a couple are self-contained `.prototype.html` flow mocks (re-tagged with build-status annotations as features ship — see the Index).

## Index

| File | One-liner |
|---|---|
| [`design-system.md`](./design-system.md) | Tokens (color / type / spacing), Liquid Glass usage table, A11y baseline, SF Symbols inventory |
| [`01-root.md`](./01-root.md) | RootView — auth bootstrap + resume pill, NavigationStack vs NavigationSplitView |
| [`02-home.md`](./02-home.md) | HomeView — 4 mode cards (Daily / Practice / Leaderboard / Settings) |
| [`03-daily-hub.md`](./03-daily-hub.md) | DailyHubView — 3 puzzle cards + completion checks + empty/error states |
| [`04-practice-hub.md`](./04-practice-hub.md) | PracticeHubView — difficulty segment + "Draw new puzzle" CTA |
| [`05-board.md`](./05-board.md) | BoardView — 9×9 grid, digit pad, undo/redo, pencil, pause overlay (no glass) |
| [`06-completion.md`](./06-completion.md) | CompletionView — hero + leaderboard slice; 3 state variants |
| [`07-leaderboard.md`](./07-leaderboard.md) | LeaderboardView — scope × difficulty pickers; auth/error/empty states |
| [`08-settings.md`](./08-settings.md) | SettingsView — native Form, GC status, language, version, clear cache |
| [`captureguard-kit.md`](./captureguard-kit.md) | RFC — CaptureGuardKit, surface-scoped black-on-capture guard (screen-recording/mirroring blackout) |
| [`code/SnapshotMatrix.md`](./code/SnapshotMatrix.md) | Snapshot Matrix — tracks every PNG snapshot the snapshot-test target must produce (v1 UI baseline) |
| [`sudoku-app-flow.prototype.html`](./sudoku-app-flow.prototype.html) | HTML flow mock — Sudoku app-wide screen flow (S01–S11); re-tagged HTML, not markdown; SUPERSEDED frames annotated inline as features ship (per-frame labels, not this Index) |
| [`reminders-flow.prototype.html`](./reminders-flow.prototype.html) | HTML flow mock — RemindersKit usage flow; SHIPPED (Phase 2), re-tagged HTML per the same convention |

`code/` holds `SnapshotMatrix.md` plus a standalone SwiftPM package (`Package.swift` / `Sources/` / `Tests/`) — not `*_Designs.swift` preview files (there are none in this directory). The two `.prototype.html` files are self-contained flow mocks (iPhone-frame + navigation-arrow canvases), not markdown — see `CLAUDE.md` §Where truth lives ("Design prototypes").

## How to read these docs (Developer perspective)

For each View:

1. **§a Identity** — what this View does and what async ops trigger it. Cross-reference `docs/v1/design.md §How.5.1` table.
2. **§b ASCII wireframe** — confirm the layout structure (which elements, what order) before writing SwiftUI.
3. **§c SwiftUI preview skeleton** — copy into `docs/designs/code/<View>_Designs.swift` (or directly inline a `#Preview` in the production target). Stubs are **preview-only**: they invent placeholder ViewModels because the real protocols (`PuzzleStoreProtocol`, `PersistenceProtocol`, `GameCenterClient`) don't exist yet (per `plan.md`). When real protocols land, replace the stub VMs with the real ones.
4. **§d Spec table** — drives implementation. Token names map to `design-system.md`. Specific values (44 pt min height, 16 pt padding, `.borderedProminent`, etc.) are non-negotiable unless flagged.
5. **§e A11y** — VoiceOver labels, Dynamic Type, color-blind, reduce-motion. None of these are afterthoughts; they're part of the AA acceptance criteria.
6. **§f Rationale** — why this layout. Read this if you disagree with the spec before opening a counter-proposal.

## Cross-links

- Architecture / state machines / View map → `docs/v1/design.md §How.5`
- Module / target boundaries → `docs/foundations.md §2`
- Swift 6 / Sendable / `@MainActor` rules → `docs/foundations.md §1` + skill `swift6-concurrency`
- Snapshot baseline (58 images per `code/SnapshotMatrix.md` §Coverage summary; the 25-image count at plan.md §8.11 is a historical v1-lock snapshot, since grown — see `docs/v1/design.md §How.5.8`)
- L10n hook policy → `docs/v1/design.md §How.5.6` + skill `ai-translated-localization`
- A11y baseline → `docs/v1/design.md §How.5.7` + `design-system.md` (this folder)

## Preview compilation note

The SwiftUI snippets in each per-View doc are designed to compile **standalone** — they only depend on `SwiftUI` and stub types defined in the snippet itself. They do **not** import `SudokuKit`, `SudokuEngine`, `GameState`, `Persistence`, `PuzzleStore`, `GameCenterClient`, or `Telemetry`, because none of those targets exist yet at this point in `plan.md`. Each snippet has `// DESIGN PREVIEW ONLY` at the top to mark this status.

When real targets land, port the layouts (not the stubs) into `Sources/SudokuUI/`.

## Decision log

All initial `<USER-INPUT-NEEDED>` markers have been resolved. See:
- `design-system.md` §Decision log — surface warmth, accent anchor, cell-digit rounded design
- `05-board.md` §c — user-digit weight (regular + accent tint)

Future open questions surface as `<USER-INPUT-NEEDED>` or `<DESIGNER-DECISION>` markers inside the relevant file; grep this folder for either tag.

## What is NOT in this folder

- Production Swift code (lives in `Sources/SudokuUI/` once `plan.md` reaches that phase)
- Binary design files (`.fig`, `.sketch`, `.psd`) — the v1 brand color anchor is recorded in `design-system.md` §Decision log (sage `#5C7A4F` / `#9BB87E`); a human visual designer may want to take a pass
- Animation timing tuning curves beyond named durations — defer to implementation; designer specifies "100 ms ease-out", developer chooses `.easeOut(duration: 0.1)` literal
- Marketing screenshots / App Store assets — out of scope for v1 visual spec
