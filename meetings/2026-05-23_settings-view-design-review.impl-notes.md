# SettingsView Design Review — 2026-05-23

## Overall verdict

The screen feels "不自然" because three independent rendering accidents stack on top of each other: (1) the section structure looks **broken** in the snapshots — `Section("About")` and `Section("Storage")` headers render as inline body rows next to `LabeledContent`, suggesting the snapshot host is rendering `Form` without `NavigationStack`/grouped-list chrome (no card backgrounds, no section dividers, no inset). (2) The new "Remove Ads" section header **duplicates** its first row's label ("Remove Ads" → "Remove Ads $2.99"), creating an echo effect that no other section has. (3) The success / failure feedback is a phantom `Section` with a single `Label` floating below "About", which appears bolted-on rather than belonging anywhere in the IA. Combined with the IAP rows being styled as plain `Button` labels inside a `Form` (so they look like informational rows but behave as actions, with no chevron / no visual affordance) the screen reads as a half-finished list. The native-Form decision in `08-settings.md` §f is still correct — but the IAP additions in PR #84 broke its rhythm.

## Findings (severity-ranked)

### S1 (visible eyesore — must fix)

- **F1.1** `SettingsView.swift:30` — Section header "Remove Ads" + first row label "Remove Ads" creates a duplicate echo. Either (a) rename section to "Purchases" (or drop the section header entirely if only one IAP exists) **or** (b) drop the row's `Text("Remove Ads")` and let the section header carry the name, with only the price on the right. Recommended: rename section to **"Purchases"** — future-proof and removes the echo.

- **F1.2** `SettingsView.swift:37-42` — The monetization feedback `Section { Label … }` is a header-less section appended after the IAP block, which produces an orphaned-card look. Per PR #85's existing `ToastView` infra (`Components/ToastView.swift`), this is **exactly** the use case for a toast: transient success/failure that does not deserve a permanent slot in the IA. Switch to `ToastController` + `.toastOverlay()` mounted at `RootView`. Keep `latestMessage` as VoiceOver source-of-truth per ToastView's documented contract, but remove the inline `Label` row.

- **F1.3** `SettingsView.swift:56-61` — Same problem as F1.2 for `clearCacheConfirmation`. The "Cache cleared" success surfaces as a floating sectionless `Label` between Storage and end-of-form. Route through the same `ToastController`.

- **F1.4** Snapshots `SettingsIAPRowTests/snapshotIPhoneLight{Purchased,Unpurchased}` — sections render with **no card backgrounds, no grouped-list inset, headers inline with `LabeledContent`**. Either the snapshot host is missing `NavigationStack { … }.formStyle(.grouped)` wrapping, or the `Form` is being snapped on macOS-style chrome. This is the single biggest "不自然" contributor. Verify the test host wraps in `NavigationStack` and renders on iOS trait collection; re-record snapshots after fix. (If production `RootView` does wrap correctly, then this is a test-only artifact but still misleading reviewers.)

- **F1.5** `SettingsView.swift:114-156` — Both IAP rows use a `Button { … } label: { HStack … }` pattern with no leading SF Symbol and no trailing chevron / disclosure. They look **identical to informational `LabeledContent` rows** (compare to "Version 1.0.0"). Tap affordance is invisible. Add leading SF Symbol per design-system §SF Symbols inventory: `Remove Ads` → `nosign` or `rectangle.slash`; `Restore Purchases` → `arrow.clockwise`. Symbol tint = `theme.accent.primary` (sage) to mark them as actions and reuse the brand accent role.

### S2 (polish — should fix)

- **F2.1** `SettingsView.swift:39, 58, 99-108` — Strings `"Remove Ads"`, `"Restore Purchases"`, `"Ads removed"`, `"Restored"`, `"Cache cleared"` are bare `String` literals, not in `App/Resources/Localizable.xcstrings`. Verified by grep: only `"Clear cache"` exists. Migrate to `LocalizedStringKey` and add zh-Hant translations per `ai-translated-localization` skill (7 locales).

- **F2.2** `RestorePurchasesRow` (line 138) — When `restoreInFlight == false`, the row shows only "Restore Purchases" left-aligned with empty trailing space; the `Spacer()` plus absent right content creates an asymmetric row vs. `RemoveAdsRow` (which has a `$2.99` on the right). Add a subtle trailing affordance — either a chevron `Image(systemName: "chevron.right").foregroundStyle(.tertiary)` (matches list-row convention) or a single-word hint `Text("Tap to restore").foregroundStyle(.secondary)` (avoid: too verbose). Recommend chevron.

- **F2.3** `SettingsView.swift:124-130` — `ProgressView().controlSize(.small)` replaces the price text during purchase. Acceptable but the row height jitters because `$2.99` and the spinner have different intrinsic widths. Wrap both branches in `.frame(minWidth: 60, alignment: .trailing)` to lock the trailing slot width and stop layout shift.

- **F2.4** `SettingsView.swift:96` — `tint(theme:)` resolves `theme.status.success` / `theme.status.error` for the inline `Label`. Once F1.2/F1.3 move to toast, this helper can be deleted; `ToastView` already does the styling internally.

- **F2.5** `08-settings.md` wireframe (line 11-34) defines sections: Account, Statistics, Appearance, Storage, About, Privacy policy. The shipped `SettingsView` is missing Account (GC), Statistics (puzzles solved), Appearance (language), and Privacy policy. This is a §How.5.1 scope question, not a design bug — but the absence makes the screen feel **sparse and bottom-heavy** (only 3 short sections, lots of empty bottom space — visible in both snapshots). At minimum, the Privacy policy row and an Account section should ship; otherwise this view feels like a debug screen.

### S3 (nit)

- **F3.1** `SettingsView.swift:84-87` — `generatorLabel` returns `viewModel.generatorVersion.rawValue` ("v1"). User-facing label "Generator: v1" is opaque to non-power-users. Consider hiding behind a debug build flag or moving to a "Developer" section per `08-settings.md` §f rationale (it's a power-user / bug-report identifier, not daily-use info).

- **F3.2** `SettingsView.swift:46` — `"Version"` label + `viewModel.appVersion` value of `"1.0.0"` only — design spec shows `"1.0.0 (42)"` including build number. Append `(buildNumber)`.

- **F3.3** No `accessibilityLabel` on `RestorePurchasesRow` (vs. `RemoveAdsRow` line 134 which has one). Add `.accessibilityLabel("Restore Purchases")` + a hint about what gets restored for VoiceOver users new to IAP.

- **F3.4** `confirmationDialog` (line 70-81) message string `"Generated puzzles will be re-derived next play. Saved games are not affected."` is bare; also not localized.

## Proposed visual mockup (ASCII)

**Before** (current shipped):
```
┌──────────────────────────┐
│ < Settings               │
│                          │
│  Remove Ads              │  ← header
│  ┌────────────────────┐  │
│  │ Remove Ads   $2.99 │  │  ← row label echoes header
│  │ Restore Purchases  │  │  ← no trailing affordance, asymmetric
│  └────────────────────┘  │
│  ┌────────────────────┐  │
│  │ ✓ Ads removed      │  │  ← orphan section, no header
│  └────────────────────┘  │
│  About                   │
│  ┌────────────────────┐  │
│  │ Version      1.0.0 │  │
│  │ Generator       v1 │  │
│  └────────────────────┘  │
│  Storage                 │
│  ┌────────────────────┐  │
│  │ Clear cache        │  │
│  └────────────────────┘  │
└──────────────────────────┘
       (lots of empty space)
```

**After** (proposed):
```
┌──────────────────────────┐
│ < Settings               │
│                          │
│  PURCHASES               │
│  ┌────────────────────┐  │
│  │ 🚫 Remove Ads $2.99│  │  ← sage symbol = action
│  │ ↻  Restore         │  │  ← parallel symbol, chevron
│  │    Purchases    ›  │  │
│  └────────────────────┘  │
│  ABOUT                   │
│  ┌────────────────────┐  │
│  │ Version    1.0.0(42)│ │
│  │ Privacy policy  ›  │  │  ← from spec
│  └────────────────────┘  │
│  STORAGE                 │
│  ┌────────────────────┐  │
│  │ Clear cache        │  │
│  └────────────────────┘  │
│                          │
│         [✓ Ads removed]  │ ← toast, bottom-center, auto-dismiss
└──────────────────────────┘
```

## Snapshot tests that need re-recording

| Test | Reason |
|---|---|
| `SettingsIAPRowTests/snapshotIPhoneLightUnpurchased` | F1.1 rename section + F1.5 add leading symbol + F1.2 remove inline Label feedback row |
| `SettingsIAPRowTests/snapshotIPhoneLightPurchased` | Same; also F2.2 trailing chevron on Restore row |
| (new) `SettingsViewTests/snapshotIPhoneLight` — full screen, no IAP | None currently — add to lock down baseline before IAP variants |
| (new) `SettingsViewTests/snapshotIPhoneDarkUnpurchased` | Dark-mode coverage missing; sage accent contrast must be verified per design-system §Color tokens contrast table |
| `ToastTests` snapshots | Likely already cover toast appearance; verify they cover both `.success` and `.failure` for SettingsView's reuse |

## Cross-references

- `docs/designs/08-settings.md` §b wireframe and §f rationale — spec is correct, implementation drifted
- `docs/designs/design-system.md` §Liquid Glass usage — confirms SettingsView is **No glass** (native Form). Do not add glass during fix.
- `Components/ToastView.swift` — infrastructure ready; SettingsView is the intended first consumer per its own header doc
- `App/Resources/Localizable.xcstrings` — only `Clear cache` currently translated; 5+ strings need adding
- PR #84 introduced rows; PR #85 deferred toast adoption — this review consolidates the deferred work
