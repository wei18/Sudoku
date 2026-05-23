# 2026-05-23 — fix/ios-mobileads-in-scope impl-notes

## Issue

GitHub #102: iOS xcodebuild fails on AdsAdMob target with `cannot find 'MobileAds' in scope` (LiveAdMobBridge.swift:37) plus two `ConsentForm` / generic-inference errors in UMPConsentPresenter.swift. Pre-existing — `swift build` on macOS silently skipped via `canImport(GoogleMobileAds) == false`, masking the bug through v2.0–v2.2.

## Root cause — new finding (none of H1/H2/H3)

The AdsAdMob code was written against **AdMob 12.x / UMP 3.x Swift-friendly API surface** (`MobileAds.shared`, `BannerView`, `Request`, `ConsentForm`, `ConsentInformation`, `RequestParameters`), but `Package.swift` pins both SDKs to **11.x** / **2.x**:

- `Packages/AppMonetizationKit/Package.resolved` → `googleads-mobile-ads@11.13.0`
- Pinned 2.0.0+ for UMP

The 11.13.0 / 2.x xcframeworks ship **pure ObjC headers only** — no Swift overlay, no `NS_SWIFT_NAME(MobileAds)` annotations. Symbols available to Swift are the ObjC-prefixed names: `GADMobileAds`, `GADBannerView`, `GADRequest`, `UMPConsentInformation`, `UMPConsentForm`, `UMPRequestParameters`. The unprefixed Swift names do not exist until SDK 12.x (AdMob) / a later major (UMP).

Verification: read `GoogleMobileAds.xcframework/ios-arm64/.../Headers/GADMobileAds.h` — no `NS_SWIFT_NAME` on the `GADMobileAds` class. Read `UMPConsentInformation.h` — `+sharedInstance` is `@property(class)`, `consentStatus` returns `UMPConsentStatus` enum (Swift sees `.required`).

H1 (drop `internal` from import) was tested in isolation — did NOT resolve. The compiler error is type lookup, not import visibility.

## Fix

Switch the two call sites to ObjC-prefixed names that exist in 11.x. Single bridge seam (`LiveAdMobBridge.swift`) remains the only switch point when the SDK pin is later bumped to 12.x.

## Files modified

| File | Lines changed | Note |
|------|---------------|------|
| `Packages/AppMonetizationKit/Sources/AdsAdMob/LiveAdMobBridge.swift` | ~5 (one call site + comment) | `MobileAds.shared.start { … }` → `GADMobileAds.sharedInstance().start { … }` |
| `Packages/AppMonetizationKit/Sources/AdsAdMob/UMPConsentPresenter.swift` | ~6 (three call sites + comment) | `RequestParameters` → `UMPRequestParameters`; `ConsentInformation.shared` → `UMPConsentInformation.sharedInstance`; `ConsentForm.loadAndPresentIfRequired` → `UMPConsentForm.loadAndPresentIfRequired` |

No changes to:
- `Package.swift` (SDK pin unchanged — `from: "11.0.0"` still correct)
- `Project.swift` (Tuist config unchanged — H3 not the cause)
- `MonetizationCore` (frozen surface untouched)
- `docs/foundations.md §9.1` (isolation contract semantics unchanged — still one real `import GoogleMobileAds` hit, still bridge-seam shielding the rest of the target)

`internal import` retained on both files — H1 not applicable.

## Verification

```
xcodebuild -workspace Sudoku.xcworkspace -scheme Sudoku -destination 'generic/platform=iOS' build
  → ** BUILD SUCCEEDED **

xcodebuild -workspace Sudoku.xcworkspace -scheme Sudoku -destination 'platform=macOS' build
  → ** BUILD SUCCEEDED **  (no #101 regression)

cd Packages/AppMonetizationKit && mise exec -- swift test
  → Test run with 87 tests in 13 suites passed after 0.017 seconds.

rg "import GoogleMobileAds" Packages/AppMonetizationKit/Sources/
  → 1 real hit (LiveAdMobBridge.swift), rest are comments — isolation contract holds.
```

## §未決

- **SDK upgrade path**: When the team chooses to bump AdMob to 12.x (Swift-friendly names + Swift 6 toolchain alignment), `LiveAdMobBridge.swift` and `UMPConsentPresenter.swift` become the single switch points. Worth scheduling a follow-up issue.
- **CI gap**: The whole bug existed because `swift build` on macOS silently skipped the iOS-only branch. The new macOS xcodebuild path (#101) now covers macOS, and this fix adds iOS xcodebuild as a known-good signal — but neither is wired into Xcode Cloud yet. Methodology §Backlog candidate: require both destinations in the PR-CI workflow.
- **Doc reference drift**: `AdMobBridge.swift` and `UMPConsentPresenter.swift` comments still describe the "modern v11+ Swift-friendly entry point" — that phrasing was aspirational. Leave for a follow-up doc pass; surgical-changes principle says don't touch what wasn't asked.
