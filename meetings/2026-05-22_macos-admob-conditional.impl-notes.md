# macOS AdMob conditional — impl notes

Branch: `fix/macos-admob-conditional`

## Summary

`xcodebuild ... -destination 'platform=macOS' build` failed because
`GoogleMobileAds.xcframework` + `UserMessagingPlatform.xcframework` ship
iOS-only binary slices, but `AppMonetizationKit/Package.swift` declared
both deps unconditionally. The App target's
`destinations: [.iPhone, .iPad, .mac]` pulled the iOS-only frameworks
into the macOS link line, failing at link time before `#if canImport`
guards could take effect.

## Files changed

| Path | Lines | Kind |
|---|---|---|
| `Packages/AppMonetizationKit/Package.swift` | +24 / −1 | edit |
| `Packages/AppMonetizationKit/Sources/MonetizationCore/NoopAdProvider.swift` | +37 | new |
| `Packages/SudokuKit/Sources/AppComposition/Live.swift` | +9 / −1 | edit |
| `Packages/SudokuKit/Tests/AppCompositionTests/CompositionTests.swift` | +9 / −1 | edit |

## Approach

1. **Package.swift**: Added `.condition(.when(platforms: [.iOS]))` to the
   `GoogleMobileAds` product dep on `AdsAdMob`. UMP was previously pulled
   in transitively from GoogleMobileAds; declared it as a direct package
   dependency so the same iOS condition can be applied
   (`GoogleUserMessagingPlatform` product). Without the direct
   declaration the transitive UMP target still linked unconditionally on
   macOS.

2. **NoopAdProvider** (in `MonetizationCore`): public actor implementing
   `AdProvider`. `initialize()` and `refreshBanner()` are no-ops;
   `bannerStatus` always returns `.suppressed`. Chose `.suppressed`
   rather than `.failed(...)` because `BannerSlotView` already collapses
   `.suppressed` to `EmptyView()` — exactly the macOS UX we want — and
   no new enum case is needed. `internal import Foundation` (not
   `public`) since no public API exposes a Foundation type.

3. **Live.swift**: `#if os(iOS)` switch — `LiveAdMobAdProvider()` on iOS,
   `NoopAdProvider()` elsewhere. `LiveStoreKit2IAPClient` stays on all
   platforms (StoreKit 2 is cross-platform).

4. **CompositionTests.swift**: Updated `liveCompositionExposesMonetizationDeps`
   to expect `NoopAdProvider` on non-iOS platforms — required because
   `swift test` runs natively on macOS.

## Choices that deviated from the prepared plan

- **UMP product name**: spec used `UserMessagingPlatform` but the SPM
  product is `GoogleUserMessagingPlatform` (the Swift module name
  `UserMessagingPlatform` is the *target* name, not the product). Used
  the product name in `Package.swift`.
- **AppComposition.swift untouched**: the prepared plan listed it as
  "if conditional storage needed". Storage is platform-uniform — both
  `LiveAdMobAdProvider` and `NoopAdProvider` conform to `any AdProvider`
  so no struct change was needed.
- **No change to `MonetizationBootCoordinator`**: it's pure Swift, lives
  in AdsAdMob but does not import any iOS-only framework. The
  `MonetizationBootBridges.live(...)` closures route through
  `UMPConsentPresenter` / `ATTPresenter`, both of which already have
  `#if canImport` guards and degrade to `.unsupported` outcomes on
  macOS. Boot runs end-to-end on macOS with three `.unsupported`-equivalent
  step outcomes; `bootMonetization()` does not need a platform branch.

## Verification

```
xcodebuild ... -destination 'platform=macOS' build  → BUILD SUCCEEDED
cd Packages/AppMonetizationKit && swift test         → 87 tests passed
cd Packages/SudokuKit && swift test --filter ...     → 25 tests passed
```

iOS Simulator builds blocked by sandbox in this session — Leader /
Code Reviewer should run the iOS regression locally before merge.

## §未決

1. `bootMonetization()` on macOS still calls UMP + ATT bridges, which
   degrade to `.unsupported` outcomes via the existing `#if canImport`
   guards. The macOS code path therefore logs three boot outcomes — one
   "succeeded" for adMob (NoopAdProvider.initialize() never throws) and
   two `.failed` for UMP / ATT with `unsupportedPlatform` errors. Should
   `AppComposition.bootMonetization()` early-return on `#if !os(iOS)`
   to silence the spurious failure breadcrumbs in Telemetry, or do we
   accept the breadcrumb as honest reporting of platform reality? Spec
   author's call.
2. `NoopAdProvider` placement: kept in `MonetizationCore` (per plan).
   Alternative: a dedicated thin module to keep `MonetizationCore`
   strictly definition-only. Deferred — single-file addition is fine.
3. Direct UMP package dependency adds a transitive-vs-direct duplication
   (GoogleMobileAds also declares UMP). SPM resolves both to the same
   pinned version; no conflict observed. Consider removing once Google
   publishes a single combined Swift package.
