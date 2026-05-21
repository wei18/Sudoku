# AppMonetizationKit Code ↔ Design Audit — 2026-05-21

## Verdict

**Yellow.** The package faithfully implements the spec's contract: the isolation contract is intact, the AdGate frequency logic matches design.md §How.3 line-by-line (including the dismissed-today rule, purchase-trumps-all precedence, and 7-day grace boundary handling at one-second resolution), the IAP shape is the single-product Remove Ads non-consumable with a Restore-Purchases path that calls `AppStore.sync()`, and 82 tests / 13 suites are real. Architecture and seams are clean — the bridge/protocol pattern is consistently applied to both `StoreKit` and `GoogleMobileAds`/UMP/ATT, giving full unit-testability without hitting Apple/Google globals. The reason it isn't Green: (a) the v2.2 `LiveAdMobBridge.loadBanner()` is a stub that synthesizes a handle without actually calling the SDK — a placeholder the file itself flags, but it means "loaded" in production currently has no visual reality; (b) two material semantic deviations from the design.md AdGate spec (the "lastShownDate gates daily cap" wording vs. actual code, and the absence of `firstLaunchAt` bootstrap responsibility documentation) need to be either reconciled in the spec or fixed in code; (c) `AdPresentationAnchor` uses `@unchecked Sendable` over `AnyHashable` with a documented-but-unenforced invariant.

## Isolation contract

- **GoogleMobileAds imports**: ✓ exactly **1** real import — `Sources/AdsAdMob/LiveAdMobBridge.swift:6`. Two other matches are comment text in `AdMobBridge.swift` and `UMPConsentPresenter.swift` referencing the audit rule. Pass.
- **UserMessagingPlatform imports**: ✓ exactly **1** real import — `Sources/AdsAdMob/UMPConsentPresenter.swift:2`. Pass.
- **StoreKit imports**: ✓ exactly **1** real import — `Sources/IAPStoreKit2/LiveStoreKitBridge.swift:1`. Pass (not part of foundations.md §9.1 but consistent with §How.2 "不暴露 StoreKit.Product").
- **MonetizationCore purity**: ✓ Pass. The four MonetizationCore files (`AdGate.swift`, `AdProvider.swift`, `IAPClient.swift`, `AdPresentationAnchor.swift`) import only `Foundation`, `UIKit`/`AppKit` (anchor only, conditional, public — see N3), and own-target types. No AdMob / UMP / StoreKit / ATT references in the core's protocol surface. `AdProvider` returns `AdBannerHandle` (UUID wrapper), `IAPClient` returns `IAPProduct` (plain struct) — no SDK leak.
- **`internal import`** discipline: ✓ All SDK/Apple-framework imports use `internal import` (StrictConcurrency/InternalImportsByDefault upcoming feature is on in Package.swift). No `public import GoogleMobileAds` etc.

## Findings (severity-ranked)

### B (Blocker — must fix before any further v2 work)

**B1. `LiveAdMobBridge.loadBanner()` returns a synthetic handle without invoking the SDK.**
`Sources/AdsAdMob/LiveAdMobBridge.swift:47-64` creates an `AdBannerHandle()` and immediately reports `.loaded(handle)` without ever instantiating a `GADBannerView`, loading a `Request`, or wiring a delegate. The comment acknowledges this is "v2.2 minimum-viable" with real lifecycle deferred to v2.3, but in its current state `LiveAdMobAdProvider.refreshBanner()` reports success to `BannerSlotView` consumers when **no ad has actually been fetched**. This is a silent-failure trap — telemetry will show "loaded" status while users see nothing, and there's no way for the UI layer to detect the deferred state. Either (a) make `loadBanner()` throw `AdMobBridgeError.loadFailed(reason: "not yet implemented (v2.3)")` until the SDK wiring lands, or (b) report `.loading` indefinitely so consumers visibly notice the gap.

**B2. `firstLaunchAt` bootstrap responsibility is unspecified and untested.**
`AdGateState.firstLaunchAt` is non-optional and `AdGate.shouldShowBanner` reads it as authoritative for the 7-day grace window. The comment in `AdGate.swift:9-10` says "Set once by the concrete store on the first `loadState()` call when no record exists" — but there is no concrete store yet (the CloudKit-backed `LiveMonetizationStateStore` is design.md §How.7, not in this package), and `FakeAdGateStateStore.loadState()` simply throws `notSeeded` when no state was scripted. Consequence: if `AdGate` is wired to a real store on first launch and the store returns "no record", the cache stays empty and `shouldShowBanner` returns `false` (the catch-all error branch at line 86–88) **forever**, never bootstrapping `firstLaunchAt`. This is consistent with design.md §How.3 "set once on first ever launch" only if some bootstrap path actually does the set. Add either (a) a bootstrap method on `AdGate` (`initializeFirstLaunchIfNeeded(now:)`) called by `AppComposition.live()`, or (b) make the protocol contract explicit that `AdGateStateStore.loadState()` must synthesize a default state with `firstLaunchAt = .now` on miss. Either way: add a test.

### M (Medium — fix in v2 stabilization)

**M1. `AdGate.shouldShowBanner` semantics deviate from design.md §How.3 spec text.**
The spec text says (design.md:132–134): rule #4 is *"lastShownDate == today AND not yet dismissed → keep showing"* (banner persistent, no daily-cap-counted re-shows). The actual code does not use `lastShownDate` in `shouldShowBanner` at all — it only updates it in `recordBannerShown`. The runtime behavior is correct (banner persistent until dismissed), but the spec implies `lastShownDate` is read as part of the gate. The header comment at lines 51–54 acknowledges this divergence ("`lastShownDate` is recorded for telemetry … but does NOT itself gate display"). Decision needed: either update `design.md §How.3` to remove the misleading rule #4 wording, or reintroduce a daily-cap check. Right now the spec contradicts the code.

**M2. Error swallowing in `AdGate.mutate(_:)` is silent.**
`Sources/MonetizationCore/AdGate.swift:121-132` catches all errors from `store.saveState(state)` and discards them with a comment "Persistence error is surfaced via telemetry by the live store". But there is no Telemetry handle in this actor — the live store (in the Sudoku App's persistence layer, not in this package) would have to instrument itself. Until that live store exists and is instrumented, a CloudKit save failure is **completely invisible**. Inject an optional `onPersistenceError: (@Sendable (Error) -> Void)?` closure (no Telemetry dependency leak — just a closure) so the host can route failures into its observability stack.

**M3. `LiveStoreKit2IAPClient.purchase` synthesized-product fallback hides catalog desync.**
`Sources/IAPStoreKit2/LiveStoreKit2IAPClient.swift:54-65` — if a purchase succeeds but the post-purchase product re-fetch returns empty, the code synthesizes an `IAPProduct` with `displayName = id` and `displayPrice = ""`. This is reasonable for not-blocking the entitlement flip, but the empty `displayPrice` will render badly in any UI that displays it post-purchase ("Receipt: ", "Thanks for purchasing  for "). At minimum: log this branch (it implies catalog instability) and consider returning a "Restore Purchases will refresh details" hint instead of an empty string.

**M4. No timezone-shift test.**
`AdGateLogicTests` has a `dismissedTodayHonorsInjectedCalendarTimezone` test (line 162) but it only verifies same-timezone same-day handling. There is no test for the case "user dismisses at 23:30 UTC, then flies to UTC-8 and queries at 16:00 local (which is now the next UTC day)" — which is the actual edge case the design's "calendar-local" wording implies should be handled. Given `AdGate` takes an injected `Calendar`, the host's responsibility for choosing UTC vs current-locale is unspecified. Add a test covering the user-relocates-across-date-line scenario and document the expectation.

**M5. No system-clock-manipulation defense.**
`shouldShowBanner(now:)` trusts the caller's `now` parameter (and `Date.now` is wall-clock). A user who moves their device clock back to 1970 would bypass the 7-day grace forever. The audit list called this out explicitly; the code has no protection. Cheap mitigation: persist `lastSeenWallClock` in `AdGateState` and refuse to advance grace if `now < lastSeenWallClock - tolerance`. Defer to v2.x if you accept the threat model is small ("a user gaming themselves into seeing more ads is not an attacker"), but document the decision.

### N (Nit)

**N1. `AdPresentationAnchor: @unchecked Sendable` over `AnyHashable`.**
`Sources/MonetizationCore/AdPresentationAnchor.swift:16`. The invariant ("callers pass only Sendable-compatible hashable values") is documented but not enforced. Since `AnyHashable` cannot itself be `Sendable`-constrained, the alternatives are: (a) box a concrete `Sendable & Hashable` generic, (b) restrict to `UUID` (the only constructed value type used anywhere), or (c) accept the unchecked. The type is unused in any current code path (no caller resolves a window through it yet). If v2.3 wiring will use only UUIDs, narrow the type to `UUID`. If not, this is fine.

**N2. `LiveAdMobBridge` uses `final class + OSAllocatedUnfairLock + @unchecked Sendable` instead of `actor`.**
`Sources/AdsAdMob/LiveAdMobBridge.swift:20-83`. The justification (delegate callbacks fire on arbitrary queues, actor would require trampolining every event) is reasonable. The lock-based shape is fine. But note: once `loadBanner` is real (resolves B1), the actor-vs-class tradeoff should be re-evaluated — Swift 6 may make the trampolining cost negligible.

**N3. `AdPresentationAnchor` uses `public import UIKit` / `public import AppKit`.**
`Sources/MonetizationCore/AdPresentationAnchor.swift:32,49`. This is the only place MonetizationCore leaks Apple-platform UI framework symbols to consumers. Justified (the resolver methods need the platform types), but it does mean `MonetizationCore` is no longer truly UIKit/AppKit-free at the binary level. If future portability (e.g. Swift on Android) matters, gate the resolver methods behind a separate extension target.

**N4. `LiveStoreKitBridge.transactionUpdates()` uses `Task.detached(priority: .background)`.**
`Sources/IAPStoreKit2/LiveStoreKitBridge.swift:79`. `.background` is correct for ambient transaction listening, but `Transaction.updates` delivers refund/family-share events that affect entitlement state — if the user has a refund pending while playing, you want it visible promptly. Consider `.utility` or default priority.

**N5. `LiveStoreKit2IAPClient.purchaseUpdates()` and `FakeIAPClient.purchaseUpdates()` have different multi-subscriber semantics.**
Live wraps the bridge stream in a fresh `AsyncStream` per call (so multiple subscribers each get their own task spawned). Fake returns a single shared `AsyncStream` (single-consumer per `AsyncStream` semantics — second subscriber gets nothing). The comment in `FakeIAPClient.swift:9-12` flags this. Not a bug, but a footgun for tests that subscribe twice; rename to `purchaseUpdatesStream` or assert single-call in a `precondition`.

**N6. `ProtocolShapeTests` doesn't fully exercise `Sendable` constraints at compile time.**
`assertSendable<T: Sendable>(_:)` is declared but never called on the public value types (only inside the protocol-witness fixtures). Add `assertSendable(AdGateState(...))`, `assertSendable(IAPProduct(...))` etc. so accidental Sendable regression is caught.

## Test coverage report

- **`@Test` count**: 82 (matches claim)
- **Suites**: 13 (matches claim)
- **Per-suite breakdown**:
  - `AdGateLogicTests` — 13 tests, AdGate frequency policy
  - `ProtocolShapeTests` — 8 tests, compile-time protocol witness fixtures
  - `BannerLoadTests` — 8 tests, refresh/recovery
  - `AdProviderInitTests` — 6 tests, init idempotency / retry
  - `ATTPresenterTests` — 6 tests, four ATT states + flow + unsupported
  - `UMPConsentPresenterTests` — 6 tests, GDPR consent paths
  - `PurchaseFlowTests` — 12 tests, purchase / restore / updates pipe
  - `AvailableProductsTests` (file) — 10 tests across 3 suites (`IAPProductMapperTests` 4 + `AvailableProductsTests` 4 + `IAPProductIDsTests` 2)
  - `FakeShapesTests` — 9 tests across 2 suites (FakeAdProvider + FakeIAPClient)
  - `FakeAdGateStateStoreTests` — 4 tests, round-trip + Codable
- **Testable seams**: ✓ `MonetizationTesting` Fakes (`FakeAdProvider`, `FakeIAPClient`, `FakeAdGateStateStore`) are real and exercised. The bridge seams (`FakeStoreKitBridge`, `FakeAdMobBridge`, `FakeUMPBridge`, `FakeATTBridge`) live in the test targets directly (not `MonetizationTesting`) — appropriate, since they're internal to each adapter target.

### Untested Live code paths

1. **`LiveAdMobBridge.start` / `loadBanner` real-SDK branch** — only the `#if canImport(GoogleMobileAds)` arm is in code; nothing exercises it (rightly so — needs UI host + network). But also no test for `unsupportedPlatform` thrown when the SDK is absent. Add a macOS-host test that confirms `loadBanner()` throws `.unsupportedPlatform` so the platform-fencing contract is enforced.
2. **`LiveStoreKitBridge`** — entire file is untested. All tests reach `LiveStoreKit2IAPClient` via the injected `StoreKitBridge` protocol. The Apple-framework adapter (`Product.products(for:)`, `Transaction.currentEntitlements` iteration with `revocationDate` filter, `Product.purchase()` result switching including `.unverified` failure mapping, `AppStore.sync()` rethrow, `Transaction.updates` revocation-vs-purchase classification) — none of this is unit-tested. That's structurally unavoidable in unit tests, but it should be covered by a thin **StoreKit Configuration File** integration test target running against a `.storekit` file. Not present.
3. **`LiveUMPBridge` / `LiveATTBridge`** — same situation; the live SDK calls are untested. Acceptable.
4. **`AdGate` error branches**: the `catch { return false }` at line 86–89 of `AdGate.swift` is covered indirectly by `loadWithoutSeedThrows`-style scenarios in `FakeAdGateStateStoreTests` but not in `AdGateLogicTests` (there is no "store throws → shouldShowBanner returns false" test). Add one.
5. **`AdGate.mutate(_:)` catch branch** (M2) — completely untested. The cache-consistency-on-save-failure invariant the comment claims is unverified.
6. **`IAPProductMapper.map` with empty strings / extreme prices** — not stress-tested; the locale-formatted price test covers 4 currencies but no edge values (`""`, very long display name).

