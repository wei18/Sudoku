# macOS AdMob Conditional — Code Review — 2026-05-22

## Verdict

**APPROVE** (with a recommendation on §未決 #1, no blockers).

The fix is surgical, well-scoped, and matches the documented Swift 6.2 SPM
`.condition(.when(platforms:))` shape. The iOS code path is preserved verbatim
(`LiveAdMobAdProvider()` line is unchanged — only wrapped in `#if os(iOS)`),
so iOS regression risk is bounded to "did the platform-conditional product
dep change iOS linkage?" — semantically no, since `.iOS` is the active
platform on an iOS build. `NoopAdProvider` is a clean, complete `AdProvider`
conformance. The new public type in MonetizationCore is additive and serves a
genuine platform need (acceptable departure from the v2 freeze).

## Per-file

| File | OK? | Note |
|---|---|---|
| `Packages/AppMonetizationKit/Package.swift` | ✅ | Condition syntax correct; UMP direct-dep justified inline. |
| `Packages/AppMonetizationKit/Sources/MonetizationCore/NoopAdProvider.swift` | ✅ | Full `AdProvider` conformance (`initialize`, `bannerStatus`, `refreshBanner`); actor → `Sendable`; `internal import Foundation` correct (no Foundation type leaks publicly). |
| `Packages/SudokuKit/Sources/AppComposition/Live.swift` | ✅ | `#if os(iOS)` branch identical to pre-diff wiring. No drift. |
| `Packages/SudokuKit/Tests/AppCompositionTests/CompositionTests.swift` | ✅ | Platform-conditional expectation tightens the contract (asserts `NoopAdProvider` on macOS) rather than relaxing it. |

## Required changes

None. All comments below are advisory.

### Advisory (non-blocking)

- `NoopAdProvider.swift:30` — `bannerStatus` returns `.suppressed`
  unconditionally, including before `initialize()` runs. This deviates from
  `LiveAdMobAdProvider` semantics (`.notInitialized` → `.loading` → `.loaded`).
  The impl-notes justify this as "BannerSlotView collapses `.suppressed` to
  EmptyView, which is the desired macOS UX." Accepted — but if a future call
  site distinguishes "ads suppressed by gate" vs "ads unavailable on platform"
  for analytics, revisit. Not a blocker for this PR.
- UMP direct-dep duplication (Package.swift:103-110) is **needed**, not
  redundant. Without the direct declaration the transitive UMP target from
  GoogleMobileAds links unconditionally on macOS and the build fails. The
  inline comment correctly captures this. SPM resolves both to the same
  pinned version — no conflict.
- MonetizationCore public-surface freeze: adding `NoopAdProvider` is additive
  (no removal / signature change), serves a real platform need, and avoids
  a separate thin module. Acceptable.

## §未決 recommendation

**#1 — `bootMonetization()` on macOS: recommend early-return on `#if !os(iOS)`.**

Reasoning:
1. The current macOS path emits two `.failed` telemetry breadcrumbs (UMP +
   ATT both report `unsupportedPlatform`) every cold boot. This is noise, not
   signal — the platform reality is statically known at compile time, so
   logging it at runtime as an *error* misclassifies a deterministic
   no-op as a fault. Telemetry's error channel should reflect anomalies, not
   platform invariants.
2. Early-return is cheap (one `#if` guard) and symmetrical with the AdProvider
   fix already shipped here. Keeping one branch (`bootMonetization`) noisy
   while the sibling branch (`AdProvider`) is cleanly switched creates
   asymmetric mental load for future readers.
3. If observability of "boot ran on macOS" is still wanted, emit a single
   informational breadcrumb (`source: "MonetizationBoot", code: "skipped_non_ios"`)
   instead of two error breadcrumbs.

Suggest tracking this as a follow-up task on the same branch or a fast-follow
PR — not a blocker for merging the build-fix.

**#2 — `NoopAdProvider` placement.** Keep in MonetizationCore. Splitting into a
dedicated module for a 40-line file is premature.

**#3 — UMP direct-dep duplication.** Keep as-is until Google ships a unified
package. The inline comment is sufficient documentation.
