# v2-audit code-polish §未決 follow-ups — impl notes

Branch: `feat/v2-audit-code-polish-unsettled` (off `main`).
Scope: address the 3 §未決 from PR #97 impl-notes
(`meetings/2026-05-22_v2-audit-code-polish.impl-notes.md`).

Methodology #8 (Monetization-touching): MonetizationCore + MonetizationTesting
changed → Code Reviewer round scheduled by Leader.

## Files touched

* `Packages/AppMonetizationKit/Sources/MonetizationCore/AdGate.swift`
  — Item 1: throttle `advanceWallClock` persistence.
* `Packages/AppMonetizationKit/Sources/MonetizationCore/AdPresentationAnchorRegistry.swift`
  (new) — Item 3: actor-based weak registry + `WindowRef`.
* `Packages/AppMonetizationKit/Sources/MonetizationTesting/FakeIAPClient.swift`
  — Item 2: fan-out broadcaster matching Live multi-subscriber semantics.
* `Packages/AppMonetizationKit/Tests/MonetizationCoreTests/AdGateLogicTests.swift`
  — +2 throttle tests.
* `Packages/AppMonetizationKit/Tests/MonetizationCoreTests/AdPresentationAnchorRegistryTests.swift`
  (new) — 6 tests.
* `Packages/AppMonetizationKit/Tests/MonetizationTestingTests/FakeShapesTests.swift`
  — +2 multi-subscriber tests.

## 1. `advanceWallClock` throttle

Constant: `internal static let wallClockAdvanceMinInterval: TimeInterval = 6 * 3_600`.

Mechanics:
* Two state slots:
  * `cachedState.lastSeenWallClock` — in-session high-water mark, advances
    on every forward call (so the tamper guard keeps full precision).
  * `lastPersistedWallClock` (new private actor var) — last value actually
    written through `saveState`. The throttle compares against THIS, not
    the cached high-water mark.
* Decision: `now.timeIntervalSince(lastPersisted) >= 6h` → `mutate { … }`
  (persists + updates cache); otherwise cache-only update.
* First-call resolution: `lastPersistedWallClock ?? cachedState?.lastSeenWallClock ?? .distantPast`,
  so fresh installs (and post-load first calls) always persist the seed.

Why "last persisted" not "cached": with throttling, the cache moves every
1h-ish on a hot Home screen; if we gated by the cache, persistence would
fire on every call once we crossed 6h since seed. The intent is ≤ 4
writes/day, so the gate must be the last *write*.

Tests (2):
* `wallClockAdvanceThrottledWithin6h`: 4 calls at 0h / +1h / +5h / +6h+1s
  → `store.saveCallCount` transitions 1 → 1 → 1 → 2.
* `wallClockAdvanceStillUpdatesCacheForTamperGuard`: rewind 2 days after
  a within-6h advance still trips the tamper guard (proves the cache
  advances even when persistence skips).

Existing M5 tests (`clockMovedBackwardsRefusesGraceAdvance`,
`clockToleranceWithin24hStillShows`) still green — both exit before the
throttle path (rewind, or `now <= cachedHighWater`).

## 2. `FakeIAPClient` fan-out

Replaced the shared `AsyncStream` + `purchaseUpdatesSubscribed` precondition-flag
with a `[UUID: AsyncStream.Continuation]` broadcaster guarded by
`OSAllocatedUnfairLock` (matches the existing nonisolated-accessor pattern
in this actor).

* `purchaseUpdates()` (still `nonisolated`): allocates a fresh stream,
  registers its continuation under a UUID token, installs an
  `onTermination` hook that removes the entry on cancel / finish.
* `emit(_:)`: snapshot continuations under the lock, yield to each.
  (Yield outside the lock to avoid re-entrancy if a downstream consumer
  triggers another emit.)
* `finishUpdates()`: drain + finish all continuations atomically.
* Diagnostic: `purchaseUpdatesSubscriberCount` (replaces the old
  `purchaseUpdatesWasSubscribed` Bool — strictly more informative; the
  old name had no callers).

Why not just wrap the bridge stream the way Live does: Live has an
underlying StoreKit2 transaction sequence to multiplex from; the Fake has
no upstream — `emit(_:)` IS the upstream. A broadcaster table is the
minimal shape that lets a scripted emit reach N subscribers.

Tests (2):
* `purchaseUpdatesMultipleConcurrentSubscribersAllReceive`: 2 subscribers,
  2 events, both consumers collect both events; subscriber count == 2
  before `finishUpdates`.
* `purchaseUpdatesSubscriberCountDropsOnCancellation`: subscribe in a
  Task, cancel, verify count drops to 0 (confirms `onTermination` wiring).

Existing `purchaseUpdatesDeliversEmittedEvents` still green — single
subscriber, sequential subscribe-then-emit.

## 3. `AdPresentationAnchorRegistry`

Public surface (new file in MonetizationCore):

```swift
public actor AdPresentationAnchorRegistry {
    public init()
    public func register(_ anchor: AdPresentationAnchor, window: WindowRef)
    public func unregister(_ anchor: AdPresentationAnchor)
    public func resolve(_ anchor: AdPresentationAnchor) -> WindowRef?
    public var liveEntryCount: Int { get }  // diagnostic
}

public final class WindowRef: @unchecked Sendable {
    public init(_ window: AnyObject)
    public var isAlive: Bool { get }
    public var unsafeAnyObject: AnyObject? { get }
}
```

Design choices:
* Sendable barrier: returning `AnyObject?` directly across the actor
  boundary fails Swift 6 strict-concurrency checks (Optional isn't
  Sendable when wrapping non-Sendable types). The `WindowRef` class is
  `@unchecked Sendable` — sound because (a) every store/load goes
  through the actor's isolated mutation API, and (b) callers either keep
  the `WindowRef` on the actor side or hand the unwrapped window
  immediately to its UI framework on the main thread.
* `unsafeAnyObject` (not `unsafeUIWindow`/`unsafeNSWindow`) keeps
  MonetizationCore Foundation-only. AdsAdMob does the
  `as? UIWindow` cast at the call site (where UIKit is already
  imported, mirroring the pattern in `AdPresentationAnchor+Resolve.swift`).
* Weak storage: `WindowRef.window` is `weak var`, so a host that forgets
  to `unregister` cannot leak the window. `resolve` checks `isAlive`
  before returning; `liveEntryCount` skips weak-cleared entries.

Tests (6):
* `registerThenResolveRoundTrips`
* `resolveUnregisteredReturnsNil`
* `unregisterRemovesEntry`
* `reRegisterReplacesPriorEntry`
* `weakReferenceClearsAfterDeinit`
* `liveEntryCountExcludesDeallocatedEntries`

`StubWindow` is a plain test-local class — avoids dragging UIKit/AppKit
into MonetizationCoreTests just to exercise the weak-ref path.

## Verification

```bash
cd Packages/AppMonetizationKit && mise exec -- swift test
```
Result: **97 tests passed** (baseline 87 → 97; +10 new tests).

## §未決

(none — all 3 PR #97 §未決 addressed in this pass.)

Outstanding integration follow-up for v2.2 (NOT this PR's scope):
AdsAdMob needs to (a) instantiate `AdPresentationAnchorRegistry` at
adapter init, (b) wire `register / unregister` to scene lifecycle, and
(c) cast `resolve(...)?.unsafeAnyObject` to `UIWindow` at banner
attach. That work is gated by AdsAdMob's v2.2 banner-attach flow and
isn't blocked by this PR.
