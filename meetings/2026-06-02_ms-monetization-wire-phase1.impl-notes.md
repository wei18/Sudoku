# Impl Notes — MS Monetization Wire Phase 1 (extract MonetizationUI) (2026-06-02)

Status: COMPLETE
Owner: Senior Developer
Dispatched by: Leader
Started: 2026-06-02
Completed: 2026-06-02

## 設計決定 (Design decisions)

- **Target placement** — Per Leader pre-decision: `MonetizationUI` lives inside `AppMonetizationKit/Sources/MonetizationUI/`. Dep direction: MonetizationUI → MonetizationCore (in-package). No new external products consumed.

- **Theme decoupling shape — rows** — Per Leader pre-decision: rows take a `tintColor: Color` *required* init param replacing every `theme.accent.primary.resolved` read. SudokuUI's `SettingsView` resolves `theme.accent.primary.resolved` and passes it through.

- **Theme decoupling shape — ToastView** — Proposal pre-decisions list only `tintColor`, but `ToastView` reads `theme.status.success.resolved` / `theme.status.error.resolved` — two distinct tints driven by `Toast.Style`. Chose to add **two** required init params on `ToastView`: `successTint: Color`, `failureTint: Color`. Same shape rolls up through the `toastOverlay(_:)` helper, which now takes `successTint` + `failureTint` alongside the controller. Sudoku's `RootView` reads both from `theme.status` and passes them in. See §未決 #1 — would a single `tintColor` API (caller picks per Toast) be preferred? Default kept the success/failure split because it preserves byte-identical rendering.

- **`removeAdsProductId` constant** — Kept as a `public let` in MonetizationUI with the literal `"com.wei18.sudoku.iap.remove_ads"`. Per proposal's "Don't change behavior. Logic moved, not rewritten." Phase 3 will revisit (parameterize or shadow per-app). See §未決 #2.

- **Row scope** — Moved: `RemoveAdsRow`, `AdsRemovedRow`, `RestorePurchasesRow`. Did NOT move: `AboutRow` (not monetization-specific, lives in About Section). Did NOT move: `BannerSlotView` (Phase 1 explicitly scopes to Settings rows + controllers; BannerSlotView is a HomeView dep, future Phase concern).

- **Test target shape** — Created `MonetizationUITests` test target carrying ToastController behavior tests (`ToastTests` core logic). Left `SettingsIAPRowTests` + `MonetizationStateControllerUpdatesTests` + the `SettingsView` snapshot tests in `SudokuUITests` because they exercise the rows in the *Sudoku* SettingsView surface (full-page snapshot) and depend on `SudokuKitTesting` (`FakeAdGateStateStore`, `FakeIAPClient` from `MonetizationTesting`). They now `import MonetizationUI`. See §折衷 #1.

- **`toastOverlay` API churn** — The `View.toastOverlay(_:)` helper signature changes from `(ToastController?)` → `(ToastController?, successTint: Color, failureTint: Color)`. Single call site in `RootView.swift`. Acceptable churn; trivially mechanical.

- **`@testable import SudokuUI`** in `ToastTests` — Replaced with `import MonetizationUI`. The toast types are `public`; nothing was `@testable`-only. Verified by checking that no test asserts on `internal` ToastController state.

## 偏離 (Deviations)

- **ToastView gets TWO tints, not one** — Spec/proposal pre-decision #2 says "`tintColor: Color` init param. No env key, no theme protocol." `ToastView` semantically requires two tints (success + failure). Implemented as `successTint` + `failureTint` init params. Net effect: still no env key, no theme protocol, just one more `Color` param.

## 折衷 (Tradeoffs)

- **Should controller/toast tests move to `MonetizationUITests`?** — Considered: (A) move all `MonetizationStateControllerUpdatesTests`, `ToastTests`, non-snapshot half of `SettingsIAPRowTests` to MonetizationUITests; (B) leave them in SudokuUITests; (C) split per-test. Picked **(B) leave in SudokuUITests** for the controller-update and settings-row tests because they depend on `SudokuKitTesting` (which depends on `PersistenceTesting`, `MonetizationTesting`, etc.) — moving them would force MonetizationUITests to drag in `SudokuKitTesting`, which is a backward dep direction. **Moved only `ToastTests`** (zero SudokuKit deps; pure ToastController + ToastView). Result: minimum diff, dep direction clean.

- **`SettingsView.swift` Sudoku-side: delete row structs vs keep file** — Picked **delete** the three row `struct`s + the `removeAdsProductId` ref. `SettingsView` keeps `AboutRow` + the body, gains `@Environment(\.theme)` read so it can pass `theme.accent.primary.resolved` as `tintColor` to MonetizationUI rows. About row's `theme.accent.primary` still resolved locally (it's not moving).

## 未決 (Open questions)

- **Q1 — Single tint or split tints for ToastView?** Picked split (`successTint` + `failureTint`) to preserve byte-identical rendering. Alternative: caller resolves the color before constructing `Toast`. Default picked has lower call-site churn (RootView passes 2 colors once vs every `controller.show(Toast(...))` site needing color). Risk if wrong: cosmetic refactor in Phase 3 if user/Leader prefer caller-resolved.

- **Q2 — Parameterize `removeAdsProductId` now?** Default: keep hardcoded Sudoku product ID in MonetizationUI as a `public let`. MS will need to either shadow with a different constant in Phase 3, or this PR parameterizes the controller to take a `productId: String` init param. Picked the conservative "Phase 1 = move only" path. Risk if wrong: Phase 3 churn in `MonetizationStateController` API.

- **Q3 — `SettingsView` reads `@Environment(\.theme)` to resolve tint** — This pulls a theme env-read into a file that previously didn't have one (the theme reads were inside the row structs, now relocated). Net behavior identical. Acceptable.

## Snapshot rebaseline justification (2026-06-02 final)

Two `SettingsIAPRowTests` baselines rebaselined:
- `snapshotIPhoneLightPurchased.SettingsView-iPhone-light-purchased.png`
- `snapshotIPhoneLightUnpurchased.SettingsView-iPhone-light-unpurchased.png`

**Diff classification**: structural, but **pre-existing stale baseline**, not a Phase 1 regression.

**Evidence**: the new render is **pixel-identical** to the SettingsViewTests
full-page baseline `snapshot_iPhone_light_unpurchased.SettingsView-fullpage-iPhone-light-unpurchased.png`
(verified via side-by-side Read). The old `SettingsIAPRowTests` baselines
predate PR X3's `SettingsShellView` extraction (which applies
`.formStyle(.grouped)` internally) — they captured an unstyled plain-list
render. After the extraction the render became grouped-form-styled, but
the `SettingsIAPRowTests` baselines were never refreshed. SettingsViewTests
(added in #181) captured the correct post-X3 render.

Phase 1's module-boundary crossing exercised the codegen path enough to
force the cache to actually re-render the snapshot, exposing the stale
baseline. Behavior is unchanged; the new baseline matches production-rendering.

Backed up the old baselines to `/tmp/baseline-{purchased,unpurchased}.png`
for CR pixel-diff reference.
