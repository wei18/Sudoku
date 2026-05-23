# bootMonetization() iOS-only early-return — impl notes

Date: 2026-05-23
Branch: `feat/v2-bootmonetization-ios-only`
Origin: PR #101 §未決 follow-up

## Bug

After PR #101 made AdMob+UMP deps macOS-conditional, `AppComposition.bootMonetization()` still drove the live `MonetizationBootCoordinator` on macOS. The UMP and ATT bridges inside `MonetizationBootBridges.live` are guarded by `#if canImport(UserMessagingPlatform)` / `#if canImport(AppTrackingTransparency)` and resolve to throw `.unsupported`. The coordinator's failure path then fans those into `Telemetry.observe(.errorOccurred(...))`, producing 2 spurious breadcrumbs per cold launch — misclassifying a compile-time platform invariant as a runtime fault.

## Fix

Wrapped the body of `AppComposition.bootMonetization()` with `#if !os(iOS) … return #else … #endif`. The non-iOS branch returns immediately with a comment that points back to PR #101 and explains why `NoopAdProvider` (wired in `Live.swift`) is the entirety of the macOS monetization surface.

### Why early-return (vs. injectable bridges or guarded coordinator)

- Surgical: touches a single function in a single file.
- Honest semantics: on macOS there is literally nothing to boot — neither UMP nor ATT nor AdMob has a slice. The right model is "no-op," not "run-and-fail-quietly."
- Preserves the existing iOS path verbatim — no behavioural risk to the production target.

### Final shape

```swift
public func bootMonetization() async {
    #if !os(iOS)
    // AdMob + UMP are iOS-only … Nothing to initialize here.
    return
    #else
    let bridges = MonetizationBootBridges.live(adProvider: adProvider)
    let telemetryHandle = telemetry
    let coordinator = MonetizationBootCoordinator(bridges: bridges, log: { … })
    await coordinator.boot()
    #endif
}
```

## Tests

Added one platform-conditional test in `Packages/SudokuKit/Tests/AppCompositionTests/BootOrderTests.swift`:

- **Suite**: `AppComposition.bootMonetization — non-iOS early-return` (compiled only under `#if !os(iOS)`)
- **Test**: `bootMonetization early-returns on non-iOS (no telemetry events)`
- Builds a custom `AppComposition` from `.tests()` with telemetry rewired through a `RecordingSink` (`TelemetrySink` impl backed by `OSAllocatedUnfairLock`, matching the file's existing concurrency pattern), invokes `bootMonetization()`, yields once to drain any spawned `Task`, then asserts `sink.events.isEmpty`.

The existing 6 `BootOrderTests` (which drive `MonetizationBootCoordinator` directly with scripted bridges) are platform-agnostic and remain unchanged — they validate the coordinator, not the AppComposition wrapper.

## Verify

```
swift build       → Build complete! (1.95s)
swift test --filter "BootOrder|Composition"
                  → 20 tests in 6 suites passed (0.008s)
rg "import GoogleMobileAds" Packages/AppMonetizationKit/Sources/
                  → 1 real import (LiveAdMobBridge.swift), unchanged
```

## 未決

None — the misclassified-failure-as-error contract is now expressed structurally rather than at the telemetry boundary.
