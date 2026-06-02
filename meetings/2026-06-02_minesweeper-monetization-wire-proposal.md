# Minesweeper Monetization Wire — Proposal

**Status**: PROPOSAL_DRAFT
**Author**: Developer (dispatched 2026-06-02)
**Date**: 2026-06-02

> Note: original full proposal doc lost to worktree force-remove race; this file is reconstructed from the Developer subagent's structured return summary. Decisions and Open Questions preserved verbatim.

---

## Recommendation

**3-phase plan**:
- **Phase 1**: Extract Sudoku Settings monetization UI → new `MonetizationUI` target inside `AppMonetizationKit`. Replace `@Environment(\.theme)` reads inside shared rows with `tintColor: Color` init params for theme decoupling.
- **Phase 2**: Extend ASCRegister `Config.swift` with MS IAP product entry (`com.wei18.minesweeper.iap.remove_ads`) + xcstrings mirror.
- **Phase 3**: Wire `MinesweeperAppComposition.Live` with `IAPStoreKit2` + `AdGate` + `MonetizationStateController` + `NoopAdProvider` (real `LiveAdMobBridge` deferred to U15). MS `SettingsView` consumes the extracted MonetizationUI rows.

Extraction target = **`AppMonetizationKit/MonetizationUI`** (rather than `GameShellKit/MonetizationUI`) because the rows depend on `MonetizationCore` protocols + `IAPStoreKit2` types — keeping the UI in the same package as the protocols avoids cross-package dep loops.

---

## Phase 1 LOC estimate

- **Added**: ~50 LOC (target boilerplate + `tintColor` plumbing + 3 SudokuUI call sites)
- **Modified/moved**: ~430 LOC (mechanical move of `MonetizationStateController` 218 LOC + `ToastView` 134 LOC + 3 row types ~80 LOC, plus signature edits)
- **Net new logic**: ~10 LOC (init param plumbing only)

CR threshold: > 50 LOC + touches AppComposition adjacent + MonetizationCore consumers → mandatory.

## Phase 2 LOC estimate

- ~30 LOC: 1 `IAPProduct` entry in Config.swift + 2 keys × 7 locales in xcstrings (or separate `iap-strings-minesweeper.xcstrings.patch`)

## Phase 3 LOC estimate

- ~120 LOC: MinesweeperAppComposition.Live wire (IAP client + AdGate + Controller + Toast); SettingsView consumes MonetizationUI rows

---

## Sudoku snapshot risk

**LOW-but-nonzero**. Module-boundary crossing for SwiftUI `Form` rows + Color-param-instead-of-env-read swap can trigger 1-pixel anti-aliasing class differences. Forecast: 1–3 baseline updates of `SettingsIAPRowTests` / `SettingsViewTests` / `ToastTests` snapshots.

**Mitigation**: Add SudokuUI-side convenience init that bakes Sudoku defaults so test-fixture LOC churn stays zero; explicit reviewer pixel-diff inspection if rebaselines occur.

---

## Open questions for Leader

1. **Extraction target**: `AppMonetizationKit/MonetizationUI` (recommended, dep direction wins) vs `GameShellKit/MonetizationUI`
2. **Theme decoupling**: `tintColor: Color` init param (recommended) vs new `ShellAccentColor` env key in GameShellUI
3. **MS fallback price**: mirror Sudoku's `"$2.99"`, or different
4. **MS Settings section header**: mirror `Section("Purchases")` verbatim
5. **MS iOS AdProvider this round**: `NoopAdProvider` (recommended; avoids Sudoku's v2.5.2 `fatalError` placeholder pattern) vs placeholder bridge
6. **Persistence prerequisite**: add `PrivateCKConfig.minesweeper` + wire `LivePersistence` (recommended; ~15 LOC mini-PR before Phase 3) vs UserDefaults-only stopgap
7. **Telemetry prerequisite**: wire no-op closures for `onCatalogDesync` / `onPersistenceError` this round, defer real Telemetry to its own PR
8. Explicit ack: BoardView banner deferred to U15
9. **Phase 1 snapshot rebaselining policy**: single PR with re-baselined PNGs + reviewer pixel-diff check, vs split into "extract + accept new snapshots" two-step
10. **Missing referenced doc**: dispatch cited `meetings/2026-06-02_minesweeper-sudoku-parity-audit.md`; worktree was forked before this audit landed on main. Doc IS now on main — for next dispatch, subagent will see it.

---

## Leader pre-decisions (2026-06-02, ready to dispatch impl)

Pending user confirmation:

1. ✅ AppMonetizationKit/MonetizationUI (Developer's recommendation)
2. ✅ tintColor: Color init param (cleaner than new env key)
3. **Mirror Sudoku $2.99** (mirror principle)
4. **Mirror "Purchases" verbatim** (mirror principle)
5. ✅ NoopAdProvider (U15 pending)
6. ✅ Mini-PR for `PrivateCKConfig.minesweeper` + LivePersistence wire **before** Phase 3
7. ✅ No-op closures for Telemetry this round; defer real wire
8. ✅ BoardView banner deferred to U15
9. **Single PR with re-baselined PNGs + reviewer pixel-diff** (smaller PR count, explicit visual check at review time)

---

## Next dispatch sequence

When user OKs:
- **Phase 1 dispatch** (Senior Developer + Code Reviewer): extract MonetizationUI to AppMonetizationKit + rewire SudokuUI consumers
- **Mini-PR** (Senior Developer): `PrivateCKConfig.minesweeper` + LivePersistence for MS
- **Phase 2 dispatch**: ASCRegister Config.swift + xcstrings extension for MS IAP
- **Phase 3 dispatch**: MinesweeperAppComposition.Live wire + MS SettingsView consumes shared rows
