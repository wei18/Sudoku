# Settings PR-B Toast Migration — Code Review — 2026-05-24

## Verdict

**APPROVE.** The diff delivers F1.2 (orphan monetization `Label` removal +
toast push via the already-wired `MonetizationStateController`) and F1.3
(clear-cache confirmation routes through `ToastController`) exactly as
scoped in `2026-05-23_settings-view-design-review.impl-notes.md`. Wiring
chain is symmetric with the PR #85 precedent, dead code is removed cleanly
with no orphan references, snapshots were re-recorded, and the
backward-compatible optional parameter keeps existing test fixtures
untouched. The four §未決 items are documented out-of-scope follow-ups, not
blockers.

## Per-file scorecard

| File | Intent met | Risk | Notes |
|------|------------|------|-------|
| `AppComposition/Live.swift` | ✅ F1.2/F1.3 wiring | Low | Single forward of the same `toastController` instance already passed to `RootView` + `monetizationController`. Symmetric with Preview. |
| `AppComposition/Preview.swift` | ✅ | Low | Mirrors Live. Same shared `ToastController()` reused — Preview path is non-nil, not no-op, which matches PR #85 convention. |
| `SudokuUI/Navigation/RouteFactory.swift` | ✅ | Low | Optional `toastController` defaults to `nil`; forwarded to `SettingsViewModel` on `.settings` only. No other routes need it (correct scope). Doc comment matches v2.4.6 naming used in source headers. |
| `SudokuUI/Settings/SettingsView.swift` | ✅ F1.2 + F1.3 orphan removal | Low | `MonetizationLabel` helper, `monetizationMessage(for:)`, and outer `@Environment(\.theme)` all removed. Two surviving `@Environment(\.theme)` are in `RemoveAdsRow` (L83) / `RestorePurchasesRow` (L113), both still used by `theme.accent.primary.resolved` — correct. |
| `SudokuUI/Settings/SettingsViewModel.swift` | ✅ F1.3 | Low | Optional `toastController` default `nil` preserves existing test calls (3 sites in `SettingsViewTests.swift`). `@ObservationIgnored` correctly applied to both stored deps (Observation perf hygiene). `clearCacheConfirmation` retained per a11y requirement from design review. |

## Wiring chain trace

Verified end-to-end:

```
AppComposition.live()        Live.swift:103   ToastController() created
  └─> stored on AppComposition.toastController  AppComposition.swift:54
  └─> MonetizationStateController(toastController:)  Live.swift:109/141
        └─> .show(Toast(.success, "Ads removed"))      MSC.swift:127, 153
        └─> .show(Toast(.success, "Purchases restored")) MSC.swift:183
        └─> .show(Toast(.failure, reason))             MSC.swift:132, 159, 162, 167, 187
  └─> LiveRouteFactory(toastController:)             Live.swift:126  (new)
        └─> SettingsViewModel(toastController:)        RouteFactory.swift:128 (new)
              └─> .show(Toast(.success, "Cache cleared")) SettingsViewModel.swift:63 (new)
```

Preview mirrors the same shape with a shared `ToastController()` (Preview.swift:39, 62).
`RootView` overlay is unmodified (per impl-notes; out of scope).

## §3 verification — MonetizationStateController toast push (claim audit)

impl-notes claim that PR #85 already wired toast push on purchase / restore
is **confirmed** by direct read of `Components/MonetizationStateController.swift`:

- `.adsRemoved` → 2× `toastController?.show(Toast(.success, "Ads removed"))` (L127, L153)
- `.failure` paths → 4× `.show(Toast(.failure, reason/literal))` (L132, L159, L162, L167, L187)
- `.restored` → `.show(Toast(.success, "Purchases restored"))` (L183)

`latestMessage` is set on every same site — the VoiceOver / test source-of-truth
invariant from the design review §F1.2 holds. No work needed in this PR for F1.2 — Developer correctly diagnosed Leader's task description was based on the pre-PR-#85 state.

## §4 verification — dead-code removal soundness

`grep -rn "monetizationMessage\|MonetizationLabel" Packages/` returns **zero
hits** outside the deleted lines. `clearCacheConfirmation` still has 2 test
asserts (`SettingsViewTests.swift:48,55`) — intentional per design review's a11y
contract. `@Environment(\.theme)` outer-scope removal verified: only two
remaining references are in `RemoveAdsRow`/`RestorePurchasesRow` and both use
`theme.accent.primary.resolved`.

## §5 test coverage assessment

- `clearCacheConfirmation` assert (`SettingsViewTests.swift:48,55`) covers
  the a11y source of truth. Pre-existing.
- No new test asserts `toastController.show` was called from `clearCache()`.
  This is **acceptable** given:
  - The push is a single unconditional line after the persistence write.
  - `MonetizationStateController` toast-push paths *do* have explicit tests
    (the impl-notes flake reference `purchasedEvent_flipsFlagTrue_andPushesSuccessToast`
    confirms a test pattern exists in `MonetizationStateControllerTests`).
  - Optional injection means production wiring is the only gap, and the
    wiring chain trace above covers that.
- Snapshot re-record (2 baselines, mtime 2026-05-24 01:43) executed because
  `SettingsIAPRowTests` snapshots host the full `SettingsView` (L168–187),
  not just the IAP rows — confirms impl-notes §Snapshots re-recorded was
  required, not optional. ✅

**Optional follow-up (non-blocking):** a `MonetizationStateController`-style
toast-push assert for `SettingsViewModel.clearCache()` would close symmetry.

## §6 a11y preservation

`latestMessage` (MSC) — preserved, set alongside every toast push.
`clearCacheConfirmation` (SettingsViewModel) — preserved, set before the
toast push (L62 before L63). Both invariants from the design review hold.

## §7 snapshot staleness

Re-recorded today. `SettingsIAPRowTests` host renders full `SettingsView`,
which lost two `Section` blocks → re-record was correct and is on disk.

## §8 — §未決 resolution

| # | Item | Blocker? | Resolution |
|---|------|----------|------------|
| 1 | `clearCacheConfirmation` still `public` on view-model | No | Required by test asserts + a11y contract. Reducing visibility belongs in a separate a11y-tests-refactor PR. |
| 2 | Toast copy strings duplicated across two controllers | No | YAGNI — 4 sites total, 2 controllers. A `ToastCopy` table can wait for a third source. |
| 3 | `toastController: ToastController? = nil` default | No | Symmetric with `MonetizationStateController`. Removing the default would force every test fixture (3 in `SettingsViewTests` + any future) to construct a controller — net loss. |
| 4 | F1.4 Form-chrome render in snapshot host | No | Explicitly out of scope per PR-B definition; test-host investigation, not a Settings code issue. |

None block merge. Items 1+2 are worth adding to `docs/foundations.md §Backlog`
under "Telemetry / Toast copy unification" if not already tracked.

## Required changes

**None.** This is a clean, surgical, scope-faithful PR.

## Recommended follow-ups (post-merge, non-blocking)

1. Add a `SettingsViewModelTests` case asserting `clearCache()` invokes
   `toastController.show` once with `.success` style and `"Cache cleared"`
   message — symmetry with MSC test coverage.
2. Backlog items §未決 #2 (toast copy unification) into `docs/foundations.md`
   once a third toast source appears.
