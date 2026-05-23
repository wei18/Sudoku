# iOS MobileAds Fix — Code Review — 2026-05-23

## Verdict

**APPROVE.** The fix correctly diagnoses and resolves the root cause: the code targeted AdMob v12 / UMP v3 Swift-friendly symbol names, but `Package.swift` pins v11.13.0 / v2.x whose xcframeworks ship pure ObjC headers (no `NS_SWIFT_NAME(MobileAds)` overlay). Every renamed symbol was verified against the installed `.xcframework` headers, every signature matches, the isolation contract is preserved, and all three verification reruns succeed.

## Per-file

| File | Symbol changes | Match v11/v2.x ObjC? |
|------|----------------|----------------------|
| `LiveAdMobBridge.swift` (L37–41) | `MobileAds.shared.start { _ in … }` → `GADMobileAds.sharedInstance().start { _ in … }` | ✓ — `GADMobileAds.h:31` declares `@interface GADMobileAds`; `:34` declares `+ (nonnull GADMobileAds *)sharedInstance`; `:80` declares `- (void)startWithCompletionHandler:` (Swift trailing-closure form correct, discarded `GADInitializationCompletionHandler` parameter with `_` is intentional) |
| `UMPConsentPresenter.swift` (L76) | `RequestParameters()` → `UMPRequestParameters()` | ✓ — `UMPRequestParameters.h:4` declares `@interface UMPRequestParameters : NSObject <NSCopying>`; default init OK |
| `UMPConsentPresenter.swift` (L78, L93) | `ConsentInformation.shared` → `UMPConsentInformation.sharedInstance` | ✓ — `UMPConsentInformation.h:49` declares `@interface UMPConsentInformation`; `:52` declares `@property(class, nonatomic, readonly, nonnull) UMPConsentInformation *sharedInstance` (Swift sees as static property, no parens — code matches) |
| `UMPConsentPresenter.swift` (L78) | `requestConsentInfoUpdate(with:completionHandler:)` | ✓ — `:79` declares `- (void)requestConsentInfoUpdateWithParameters:(nullable UMPRequestParameters *)parameters` with completion taking `NSError *` → Swift `Error?`; closure shape matches |
| `UMPConsentPresenter.swift` (L93) | `consentStatus == .required` | ✓ — `:58` `@property(nonatomic, readonly) UMPConsentStatus consentStatus`; enum bridges to Swift `.required` |
| `UMPConsentPresenter.swift` (L102) | `ConsentForm.loadAndPresentIfRequired(from: nil) { error in … }` → `UMPConsentForm.loadAndPresentIfRequired(from: nil) { … }` | ✓ — `UMPConsentForm.h:14` declares `@interface UMPConsentForm`; `:24` declares `+ (void)loadAndPresentIfRequiredFromViewController:(nullable UIViewController *)viewController completionHandler:` (Swift label `from:` correct; nil accepted by `nullable`) |

## Verification re-runs

- **iOS BUILD** (`xcodebuild -workspace Sudoku.xcworkspace -scheme Sudoku -destination 'generic/platform=iOS' build`): **BUILD SUCCEEDED**
- **macOS BUILD** (`xcodebuild -workspace ... -destination 'platform=macOS' build`): **BUILD SUCCEEDED** — no #101 regression
- **AppMonetizationKit test** (`cd Packages/AppMonetizationKit && mise exec -- swift test`): **87/87** in 13 suites, 0.018s
- **Isolation grep** (`rg -c "^internal import GoogleMobileAds|^import GoogleMobileAds" Packages/AppMonetizationKit/Sources/`): **1** hit (`LiveAdMobBridge.swift`) — contract holds

## Required changes

None. The fix is minimal, correct, and surgical — exactly the 11 lines needed across 2 files, no incidental refactoring.

## Polish recommendations (non-blocking)

1. **§未決 #3 from impl-notes** — the subagent self-flagged that `AdMobBridge.swift` and `UMPConsentPresenter.swift` header comments may still imply a Swift-friendly entry-point. Reading both files: `LiveAdMobBridge.swift:32–36` *already* explicitly documents the v11 ObjC reality with a clear pointer to the 12.x bump path; `UMPConsentPresenter.swift:71–75` *also* already documents the UMP 2.x parallel. The doc drift is in fact resolved by this diff. No further polish needed — the impl-notes §未決 entry is overcautious. (Cited file:line in both bridge files; closing this item.)

2. **§未決 #1 (SDK 12.x upgrade)** — legitimate follow-up. Suggest filing as a backlog item under `docs/foundations.md §9.1` rather than blocking this PR.

3. **§未決 #2 (CI gap)** — legitimate methodology-level finding. Route to `docs/methodology.md §Backlog` per backlog-routing convention; require iOS xcodebuild destination in PR-CI workflow.

## Notes on review process

- Headers verified directly against installed xcframeworks at
  `Packages/AppMonetizationKit/.build/artifacts/swift-package-manager-google-mobile-ads/GoogleMobileAds/GoogleMobileAds.xcframework/ios-arm64/GoogleMobileAds.framework/Headers/GADMobileAds.h`
  and `…/swift-package-manager-google-user-messaging-platform/UserMessagingPlatform.xcframework/ios-arm64/UserMessagingPlatform.framework/Headers/UMP{ConsentInformation,ConsentForm,RequestParameters}.h`.
  No reliance on subagent's claim alone.
- `internal import` retained on both files — H1 confirmed not applicable; the original compile error was type lookup, not visibility.
- Completion-handler bridging: ObjC `(NSError *)` → Swift `Error?` shorthand `if let error` is idiomatic; `Never` vs `Error` continuation generic types in each call site match what the underlying selector can produce (start: no error; UMP calls: error possible).
