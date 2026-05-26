---
name: monetization-sdk-integration
description: Invoke when adding, upgrading, or auditing any third-party monetization SDK in Sudoku (AdMob, UMP, StoreKit wrappers, RevenueCat, ironSource, etc.). Also invoke when reviewing PR diffs that touch `Packages/AppMonetizationKit/Sources/AdsAdMob/`, or when anyone proposes `import GoogleMobileAds` outside the existing live-bridge file.
---

# Monetization SDK Integration

## When to invoke

- Adding a new monetization SDK (AdMob, ATT, UMP, AdMob mediation networks, RevenueCat, etc.)
- Upgrading existing AdMob / UMP versions (e.g. v11 → v13)
- Auditing PR diff that touches `Packages/AppMonetizationKit/Sources/AdsAdMob/`
- Cross-platform SDK questions (iOS only? macOS catalyst? watchOS?)
- Anyone proposing "let's just `import GoogleMobileAds` over here too" — IMMEDIATE invoke

Skip when: changing pure values / protocols inside `MonetizationCore` (no third-party touch).

## The contract (foundations.md §9 + §9.1)

Default rule: **no third-party SDKs** in Sudoku. Apple-platform native APIs preferred (OSLog over Sentry, MetricKit over Firebase Crashlytics, GameKit over Steam-style backend, etc.).

**Break-glass exception** is granted when ALL of:
1. The capability genuinely requires the SDK (no Apple-native alternative); e.g. AdMob banner serving has no Apple-platform equivalent
2. The SDK is shippable under the project's privacy regime (PrivacyInfo.xcprivacy supports its tracking domains)
3. The SDK's import is isolated to a SINGLE source file behind a protocol seam (see §isolation contract below)
4. The dep arrow is one-way (consumer → SDK; SDK does not call back into our code beyond delegate/callback bridges)
5. iOS-only conditional compile gating (`canImport`) — macOS / Catalyst paths must build without the SDK

If any of (1)-(5) fails: deny. Reject the SDK proposal; suggest Apple-native fallback or sit it out.

## The isolation contract (§9.1)

For every accepted SDK:

### File-layout invariant
- Protocol file `<SdkName>Bridge.swift` defines the seam. Plain Swift; no SDK import.
- Live impl file `Live<SdkName>Bridge.swift` is the ONLY file allowed to `import <SDKModule>`.
- All other code uses `any <SdkName>Bridge` for DI. Test seam: `Fake<SdkName>Bridge` in the matching test target (e.g. `Tests/AdsAdMobTests/FakeAdMobBridge.swift`).

Example for AdMob (currently shipped):
- `Packages/AppMonetizationKit/Sources/AdsAdMob/AdMobBridge.swift` — protocol
- `Packages/AppMonetizationKit/Sources/AdsAdMob/LiveAdMobBridge.swift` — sole `import GoogleMobileAds` site
- `Packages/AppMonetizationKit/Tests/AdsAdMobTests/FakeAdMobBridge.swift` — test seam

### Build-time audit (run before every monetization PR merge)

Canonical regex (matches Swift 6 access-level imports too):
```bash
rg '^(internal |private |public |@_implementationOnly |@preconcurrency )*import <SDKModule>' Packages/
```

Expected count: **1** (live bridge file).

If > 1: the contract is broken. Either consolidate behind the existing bridge OR file an exception in `docs/foundations.md §9.x` documenting WHY a second import site is necessary (with prior reviewer sign-off).

Documentation references:
- `docs/v2/plan.md §v2.2.1` — audit acceptance criteria
- `docs/v2/v2.5-readiness.md §v2.5.2` — pre-submission audit step
- `docs/foundations.md §9.1` — the contract text itself

### Conditional compile invariant

iOS-only SDKs (AdMob/UMP/most monetization stack):
```swift
#if canImport(GoogleMobileAds)
import GoogleMobileAds
// ... live impl code
#else
// macOS / catalyst fallback — usually NoOp returning sensible empty values
#endif
```

The Package.swift dep arrow itself must also gate the SDK to iOS:
```swift
.product(
    name: "GoogleMobileAds",
    package: "swift-package-manager-google-mobile-ads",
    condition: .when(platforms: [.iOS])
),
```

Without `condition:`, macOS build fails on `swift build` because Google ships iOS-only xcframeworks.

### Test seam invariant

Test target (e.g. `Tests/AdsAdMobTests/`) ships `Fake<SdkName>Bridge` (actor or class). All unit tests inject the fake; real SDK only loaded at runtime via DI in `AppComposition.live()`. The `Sources/MonetizationTesting/` target ships shared test scaffolding used across both `AdsAdMobTests` and `IAPStoreKit2Tests` (e.g. `FakeAdProvider`, `FakeIAPClient`); the per-SDK bridge fakes live in their test target.

`Fake` must:
- Be `Sendable` (Swift 6 actor or @unchecked Sendable + lock-guarded)
- Have a `script(...)` or per-call setter API for deterministic test outcomes
- Not import the real SDK (zero hidden dependency)

## Real-world incidents this skill encodes

### AdMob v11 → v13 upgrade (PR #109, 2026-05)
- Symbol renames: `GADBannerView` → `BannerView`, `GADRequest` → `Request`, etc.
- Audit broke briefly when migrator missed file boundary; recovered by re-running isolation audit
- Documented in `meetings/2026-05-25_v2.5.2-admob-banner-wiring.impl-notes.md`

### Production ID swap safety (AdMob banner wiring CR nit, 2026-05-26)
- Release branch of `bannerAdUnitID` constant uses `fatalError("REPLACE_IN_v2.5.3: …")` rather than a placeholder string — prevents accidental Release build silently serving test creatives against production app ID
- Paired-flip checklist in `v2.5-readiness.md §v2.5.3` ensures Info.plist `GADApplicationIdentifier` + bridge constant flip together

### macOS conditional gating (PR #101, #106)
- Initial AdMob integration left `import GoogleMobileAds` ungated → macOS build broke
- Fix: `canImport(GoogleMobileAds)` + Package.swift `condition: .when(platforms: [.iOS])` + macOS fallback uses `NoopAdProvider` from `MonetizationCore`

### lefthook parallel deadlock — secondary effect (RCA H4, PR #136)
- Multiple SDK installs triggered concurrent `mise exec` invocations
- `lefthook.yml pre-commit.parallel: false` makes hook timing predictable

## Anti-patterns

- **"Just import it where you need it"** — NO. Single-file isolation is the contract; multiple imports = no audit signal, no clean removal path.
- **"Skip the Fake for now, we'll add it later"** — NO. Unit tests must work from day one; integrating SDK without a test seam means every test becomes integration-test territory.
- **"Macros + canImport are too verbose; let's drop conditional gating for v2"** — NO. macOS build will break the moment a maintainer runs `swift build` on a Mac, blocking PRs.
- **"Production IDs in source for ease of swap"** — NO. Use `fatalError` guard or build-config injection; hard-coded prod IDs in DEBUG/Release pivot risk accidental Release ship with wrong combination.
- **"PrivacyInfo.xcprivacy can wait until submission"** — NO. ASC will reject TestFlight + production builds without the manifest matching declared tracking. Update PrivacyInfo BEFORE adding the SDK.

## Pre-integration checklist

When proposing a new SDK, fill this in:

```
SDK: <name + version + GitHub URL>
Capability: <what it does that Apple-native can't>
Privacy domains: <list — must match PrivacyInfo.xcprivacy>
iOS-only / cross-platform: <iOS-only | iOS+macOS | etc.>
Bundle size impact: <KB / MB>
Tracking ATT required: <yes/no>
UMP consent required: <yes/no>
Test seam plan: <how Fake<SdkName>Bridge will look>
Isolation audit grep target count: <expected 1>
Fallback platform behaviour: <Noop / throw / etc.>
```

If any field is "TBD" or "?", do NOT proceed — research first.

## Documentation pointers

- `docs/foundations.md §9` — the no-3rd-party rule + break-glass exception
- `docs/foundations.md §9.1` — isolation contract text
- `docs/v2/design.md §How.8` (if exists) — monetization design intent
- `docs/v2/plan.md §v2.2` — AdMob impl phase, isolation acceptance criteria
- `docs/v2/v2.5-readiness.md §v2.5.2` — pre-submission audit step
- `Packages/AppMonetizationKit/Sources/AdsAdMob/AdMobBridge.swift` — protocol seam example
- `Packages/AppMonetizationKit/Sources/AdsAdMob/LiveAdMobBridge.swift` — single-import-site example
- `App/Resources/PrivacyInfo.xcprivacy` — tracking domains declaration
