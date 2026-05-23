# Settings Visual Polish (PR-A) — impl-notes (re-dispatch)

Branch: `chore/settings-visual-polish-2` (off `main` @ `83f6dfe`)
Scope: PR-A only — F1.1 / F1.5 / F2.2 / F2.3. Toast migration (F1.2/F1.3) and snapshot host fix (F1.4) explicitly excluded per dispatch.

This is a re-dispatch: prior branch's working-tree edits were clobbered by Leader's mid-flight `git restore` during a parallel-dispatch race. Only the impl-notes file survived. Code edits below are freshly re-applied to `main`.

## Items addressed

| ID | Item | Status |
|---|---|---|
| F1.1 | Rename Section "Remove Ads" → "Purchases" | Y |
| F1.5 | Leading SF Symbols (sage tint) on IAP rows | Y |
| F2.2 | Trailing `chevron.right` on Restore Purchases row | Y |
| F2.3 | `.frame(minWidth: 60)` on trailing slot for layout stability | Y |

## SF Symbol final choices

- **Remove Ads** leading: `nosign`, `.foregroundStyle(theme.accent.primary.resolved)`
- **Restore Purchases** leading: `arrow.clockwise`, same sage tint
- **Restore Purchases** trailing (idle): `chevron.right`, `.font(.footnote.weight(.semibold))`, `.foregroundStyle(.tertiary)`
- Trailing is wrapped in `Group { … }.frame(minWidth: 60, alignment: .trailing)` on both rows so `ProgressView` ↔ price / chevron swaps don't shift the row's right edge.

## Sage tint application

Applied per-symbol via `.foregroundStyle(theme.accent.primary.resolved)` on the leading `Image(systemName:)` — NOT via row-level `.tint()`. `.tint()` would propagate into the `Button` label text inside a `Form` row, over-coloring "Remove Ads" / "Restore Purchases" titles which should stay system foreground.

`@Environment(\.theme)` injected per-row (`RemoveAdsRow`, `RestorePurchasesRow`); matches existing per-view environment-resolve idiom in `SudokuUI/`.

## Snapshot baselines re-recorded

Count: **2**

Paths:
- `Packages/SudokuKit/Tests/SudokuUITests/__Snapshots__/SettingsIAPRowTests/snapshotIPhoneLightUnpurchased.SettingsView-iPhone-light-unpurchased.png`
- `Packages/SudokuKit/Tests/SudokuUITests/__Snapshots__/SettingsIAPRowTests/snapshotIPhoneLightPurchased.SettingsView-iPhone-light-purchased.png`

Procedure: flipped `SnapshotMode.recordMode` `.missing` → `.all`, ran `swift test --filter "SettingsIAPRowTests"`, restored `.missing`, re-ran `--filter "Settings"` for green assertion. Final `SnapshotConfig.swift` is unchanged from `main`.

## Verification

- `swift build` → `Build complete! (2.77s)`, no errors. Pre-existing GameKit deprecation warning unrelated.
- `swift test --filter "Settings"` → **14 / 14 passed** (`SettingsView — behavior`, `SettingsView — Remove Ads + Restore Purchases rows`, plus Home-suite tests caught by "Settings" substring).

## §未決 (Open questions)

1. **F1.4 host artifact** — empty top half of iPhone snapshots remains; root cause in `SnapshotConfig.swift / hostingView(...)` (Form-as-grouped-list not honored under bare `NSHostingView`). Deliberately deferred per dispatch; production `RootView` wraps correctly so no shipping bug.
2. **`chevron.right` on macOS** — chevron on Restore (absent on Remove Ads where price fills the slot) is iOS-list idiomatic; on macOS Form-as-grouped-list it may read as redundant. SettingsView is iOS-primary per spec; revisit if Mac feedback surfaces.
3. **Toast migration (PR-B)** — `MonetizationLabel` / `monetizationMessage(for:)` / inline `Section { Label … }` feedback rows in `SettingsView.swift` are untouched; they'll be removed in the toast-migration PR-B.
4. **Pre-existing working-tree mods on main** — `Packages/SudokuKit/Package.resolved` and `docs/foundations.md` show as `M` in `git status` but were not touched by this dispatch (debris from prior session). Leader to decide whether to discard or stash before commit.
