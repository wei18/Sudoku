# Impl notes — MS Settings reuse shared sections (#277)

## Decisions

- **Shared component shape**: `SettingsAboutVersionRow` + `SettingsStorageSection` extracted into `GameShellUI`.
  - `SettingsAboutVersionRow(version:tintColor:)` — the icon-left/label/spacer/value-right HStack pill (mirrors `AboutRow` but parameterized by `tintColor`, no `@Environment(\.theme)` dep). Just the Version row — Sudoku's Generator row is NOT shared and stays in `SudokuUI.SettingsView`.
  - `SettingsStorageSection(clearCache:)` — `Section("Storage")` + destructive `Button` + the `confirmationDialog`. Takes an `async` close-over action.
  - Reason for splitting About vs Storage: Sudoku's About section contains BOTH a shared Version row AND a Sudoku-only Generator row. A single combined "About+Storage" section couldn't host the Generator row inline. So About is exposed as a *row* (Sudoku composes it with Generator into its own `Section("About")`), and Storage is a full `Section` (no per-game additions today).

- **No Sudoku-theme dep**: shared rows take `tintColor: Color` param, mirroring `MonetizationUI.RemoveAdsRow`. GameShellUI gains NO dependency on SudokuUI/Theme. Verified by GameShellKit Package.swift having no Sudoku dep.

- **MS clear-cache wiring decision**: closure injection, NOT a full MS settings VM.
  - Rationale: MS has no save-flow yet (LivePersistence puzzleLoader is a throwing stub; nothing writes SavedGame). A full VM mirroring `SettingsViewModel` would be 90% dead code. Instead `SettingsView` takes a `clearCache: @MainActor () async -> Void` closure + `version: String`.
  - `LiveRouteFactory` builds the closure inline against the threaded `persistence` (same `PersistenceProtocol.latestInProgress()` → `deleteAbandoned(recordName:)` shape Sudoku's VM uses). Parity-only until MS save-flow lands: today `latestInProgress()` returns nil so the delete is a safe no-op, but it IS wired to the real protocol method (NOT a fake button).

- **MS version**: `Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")` at the `LiveRouteFactory` callsite, defaulting to a fallback. Sudoku keeps its existing static `appVersion` default ("1.0.0") — behavior unchanged.

## Open questions
- None blocking.
