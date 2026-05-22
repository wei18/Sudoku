# v2-audit-code-polish — impl notes

Dispatch: address M1–M5 + N1–N6 from `meetings/2026-05-21_appmonetizationkit-code-audit.impl-notes.md` (B1, B2 already landed in PRs #71, #73).

Branch: `feat/v2-audit-code-polish` (Leader handles checkout/commit/push).

## Touched targets

- `MonetizationCore` — `AdGate`, `AdGateState`, `AdPresentationAnchor`, `AdPresentationAnchor+Resolve.swift` (new)
- `IAPStoreKit2` — `LiveStoreKit2IAPClient`, `LiveStoreKitBridge`
- `MonetizationTesting` — `FakeIAPClient`
- `SudokuKit/Persistence` — `LiveMonetizationStateStore`
- `SudokuKit/AppComposition` — `Live.swift` (closure wiring)
- Tests — `AdGateLogicTests`, `ProtocolShapeTests`, `HomeViewBannerTests`
- Docs — `docs/v2/design.md §How.3` (now §How.3 / §How.3.1 / §How.3.2)

`MonetizationCore` public surface intentionally unchanged at the type level: new `lastSeenWallClock` is an optional field on the existing `AdGateState`, new `onPersistenceError` / `onCatalogDesync` are optional init parameters with default `nil`, new `AdPresentationAnchor` narrows `AnyHashable` → `UUID` (callers already use UUID). No SemVer-breaking additions.

## M1 — design ↔ code reconciliation (option a)

Picked **option a** — code behavior is correct; spec text was wrong. `docs/v2/design.md §How.3` rule #4 ("lastShownDate == today AND not yet dismissed → keep showing") removed; replaced with explicit prose that `lastShownDate` is recorded for telemetry only and not a gating predicate. New rule #4 slot occupied by the M5 clock-tamper guard (see below).

Rationale: matches the brand "honest banner" contract (persistent + dismissible, no daily-cap mid-day re-shows) and avoids re-introducing a re-show count that the existing 13-test `AdGateLogicTests` suite was never asserting against.

## M2 — onPersistenceError closure

Added `init(store:calendar:onPersistenceError:)` to `AdGate`. Closure shape:

```swift
public init(
    store: any AdGateStateStore,
    calendar: Calendar = .current,
    onPersistenceError: (@Sendable (any Error) -> Void)? = nil
)
```

`MonetizationCore` deliberately does NOT depend on `Telemetry` — the host wires the closure. Live wiring in `Packages/SudokuKit/Sources/AppComposition/Live.swift`:

```swift
let adGate = AdGate(
    store: monetizationStateStore,
    onPersistenceError: { [telemetry] error in
        Task {
            await telemetry.observe(
                .errorOccurred(
                    source: "AdGate",
                    code: "save_failed",
                    message: String(describing: error)
                )
            )
        }
    }
)
```

`AdGate.mutate(_:)`'s `catch` now calls `onPersistenceError?(error)` (was a no-op comment). Cache stays consistent on failure — the in-memory `cachedState` is updated BEFORE the save attempt, so subsequent reads in-session reflect the intended state even if persistence failed. Test added: `saveFailureSurfacesViaOnPersistenceError` in `AdGateLogicTests` (uses `FakeAdGateStateStore.scriptSaveError` + a `Sink` actor to capture).

## M3 — empty-displayPrice fix + catalog-desync telemetry

`LiveStoreKit2IAPClient.purchase` post-purchase fallback now substitutes the constant `LiveStoreKit2IAPClient.unknownDisplayPricePlaceholder = "—"` (em-dash) instead of `""`. Em-dash chosen over a localised "Refreshing…" string because the placeholder lives inside MonetizationCore-adjacent code with no L10n target; UI layer can match on the placeholder and overlay a localised hint if desired.

Catalog-desync telemetry: new optional `onCatalogDesync: (@Sendable (String) -> Void)?` init parameter, wired from `Live.swift` to `Telemetry.errorOccurred(source: "LiveStoreKit2IAPClient", code: "catalog_desync_post_purchase", message: "...productId=\(id)")`. Public default-nil parameter preserves source-compat for v2 ship.

## M4 — timezone-shift test

New test in `AdGateLogicTests`: `dismissedTodayAcrossDateLineCrossing`. Uses UTC-fixed calendar, sets `dismissedDate = 2026-05-20T23:30:00Z` (start-of-day = 2026-05-20), queries with `now = 2026-05-21T16:00:00Z`. Asserts `shouldShowBanner == true` (dismissed-today rule no longer applies — different UTC calendar day).

## M5 — system-clock-manipulation defense

### Code

- New `AdGateState.lastSeenWallClock: Date?` (Codable-compatible by default for the existing synthesised `Codable`).
- New tolerance constant `AdGate.clockTamperTolerance: TimeInterval = 86_400` (24h).
- `shouldShowBanner(now:)` adds rule #4: if `lastSeenWallClock` is set and `now < lastSeen - tolerance`, return `false` (clock moved backwards beyond tolerance).
- Successful (non-suppressed) shouldShowBanner result calls `advanceWallClock(to: now)` which monotonically bumps `lastSeenWallClock` via the same `mutate` path. `recordBannerShown` / `recordBannerDismissed` also bump it.
- Tolerance covers DST, cross-timezone travel, NTP drift.

### Persistence

`LiveMonetizationStateStore` adds `lastSeenWallClock` field:
- Encoded as `RecordValue.date` when non-nil, omitted when nil.
- Decoded via `if case .date(...) = payload.fields[...]` pattern with `else { nil }` — old records (pre-polish) parse `lastSeenWallClock` as `nil`, so first observation seeds it fresh on those devices.
- CloudKit Dashboard pre-decl NOT required — `LiveMonetizationStateStore` uses add-field-via-write as before.
- Header comment updated; impl-notes path noted inline.

### Tests

Added to `AdGateLogicTests`:
- `clockMovedBackwardsRefusesGraceAdvance` — baseline 2026-05-21, query at 2026-01-01 → returns `false`.
- `clockToleranceWithin24hStillShows` — baseline 2026-05-21T12:00, query at 2026-05-21T11:00 (-1h, within tolerance) → returns `true`.

### Side-effect note

`shouldShowBanner(now:)` now writes to persistence on every "show" decision (monotonic wall-clock advance). One existing test (`HomeViewBannerTests.dismissTap_recordsDismissedOnGate`) previously asserted `saveCallCount == 1`; updated to `>= 1` with a comment explaining the new save semantics. Caching layer in `AdGate.currentState` already prevents repeated loads from the store; only saves grow.

## N1 — AdPresentationAnchor narrowed to UUID

Grep confirmed the only construction site is `ProtocolShapeTests.swift:129` passing a `UUID`; no host registry exists yet. Replaced `AnyHashable` with `UUID`, dropped `@unchecked Sendable` (UUID is natively `Sendable`), conformed to `Sendable, Hashable`. `ProtocolShapeTests.adPresentationAnchorIsSendableAndCarriesID` updated to compare against the UUID directly (was `AnyHashable(uuid)`).

## N2 — actor-vs-class deferred

No code change. The `LiveAdMobBridge` lock-based shape is justified by delegate callbacks firing on arbitrary queues from the real SDK; re-evaluate once v2.3.5 lands real `GADBannerView` wiring and the Swift 6 trampolining cost can be measured against actor isolation. Tracked here for that re-evaluation.

## N3 — AdPresentationAnchor resolver split

New file: `Packages/AppMonetizationKit/Sources/MonetizationCore/AdPresentationAnchor+Resolve.swift`. Contains the `#if canImport(UIKit) / AppKit` extensions with `resolveUIWindow` / `resolveNSWindow`. Original `AdPresentationAnchor.swift` is now Foundation-only and contains just the value type; future Linux-side builds can SwiftPM-`exclude:` the resolver file without touching the type.

## N4 — utility priority

`LiveStoreKitBridge.transactionUpdates()` Task.detached priority `.background` → `.utility`. Inline comment explains rationale (refund / family-share events affect entitlement state and should propagate promptly).

## N5 — FakeIAPClient subscription tracking

Decision: do NOT trap on resubscription. The audit suggested "precondition OR document via assert + comment" — initial implementation used `precondition`, but it tripped legitimate production-path tests where `MonetizationStateController.startListening` cancels + re-subscribes (a real serialised resubscription pattern). Final shape: track via `purchaseUpdatesSubscribed` (`OSAllocatedUnfairLock<Bool>`) for diagnostics only, expose `purchaseUpdatesWasSubscribed` as a public computed accessor for tests that want to verify the subscriber wired up, and document the single-consumer constraint via header + inline comment instead of crashing the test process.

## N6 — Sendable compile-time coverage

`ProtocolShapeTests.valueTypesRemainSendable()` added — calls `assertSendable<T: Sendable>` on `AdGateState`, `IAPProduct`, `IAPPurchaseEvent.purchased`, `IAPPurchaseEvent.revoked`, `IAPPurchaseResult.success`, `AdBannerStatus.loaded`, `AdPresentationAnchor`. Compile-time check; runtime body is trivial.

## Verification

- `cd Packages/AppMonetizationKit && mise exec -- swift build` clean.
- `cd Packages/AppMonetizationKit && mise exec -- swift test` — **87 tests, 13 suites, all pass** (was 82; +5 = M2 saveFailure + M4 dateline + 2× M5 clock + N6 sendable batch counted as 1 test).
- `cd Packages/SudokuKit && mise exec -- swift build` clean (only pre-existing GameKit deprecation warnings on macOS 26).
- `cd Packages/SudokuKit && mise exec -- swift test` — see verification log; expected pass after `HomeViewBannerTests.dismissTap_recordsDismissedOnGate` updated for new save semantics.
- Isolation audit: `rg "^internal import GoogleMobileAds" Packages/AppMonetizationKit/Sources/` → exactly 1 match (`LiveAdMobBridge.swift:6`). Pass.
- TODO sweep: `grep -rn "TODO\|FIXME" Packages/AppMonetizationKit/Sources/` → 0 hits. Pass.

## Final test count

- AppMonetizationKit: **82 → 87** (+5)
- SudokuKit: unchanged structurally; one existing assertion relaxed (saveCount `== 1` → `>= 1`).

## §Revision-2 (Code Reviewer round 1 follow-up)

Reviewer blocker: `clockMovedBackwardsRefusesGraceAdvance` was bogus — `firstLaunchAt = 2026-01-01` and `rewound = 2026-01-01` meant rule #2 (`now < firstLaunchAt + 7d`) fired first and short-circuited before the M5 guard could be exercised. Test was passing for the wrong reason.

### Fix

`AdGateLogicTests.clockMovedBackwardsRefusesGraceAdvance` now uses a local `firstLaunchFarPast = 2024-01-01T00:00:00Z` (>1y before `rewound`), so rule #2 PASSES for the rewound `now = 2026-01-01` and rule #4 (M5 tamper-guard) is the predicate under test. Date constants:

- `firstLaunchAt        = 2024-01-01T00:00:00Z`
- `lastSeenWallClock    = 2026-05-21T12:00:00Z`
- `now (rewound)        = 2026-01-01T00:00:00Z`  (~140 days back from baseline, far beyond 24h tolerance)

### Verification (mutation test)

Temporarily replaced the M5 guard body in `AdGate.shouldShowBanner` with `if let _ = state.lastSeenWallClock, false { return false }` and ran the test — it FAILED (`Expectation failed: ... == false`), proving the test now actually exercises rule #4. Restored the guard; test passes again. `mise exec -- swift test` → 87/87 pass (unchanged from Revision-1).

### Nits

Nits 1, 2, 3 deferred per dispatch directive ("skip any that take >5 minutes; the blocker is the test fix"). None applied in this revision — each requires either a Sink-actor protocol rework (#1), cross-package Live.swift edit + telemetry review (#2), or doc comment + signature stability discussion (#3) that exceeds the 5-min budget. Tracked for v2.2 follow-up.

## §未決

1. **`onPersistenceError` runs sync inside the actor** — closure executes synchronously after the failed save call returns. The Live wiring spawns a detached `Task` to hop into Telemetry, so the actor is not blocked on the Telemetry await. If a future host wants to back-pressure on persistence failures, the closure shape needs to change to `async`; v2 ship has no such caller.
2. **`lastSeenWallClock` advance writes on every shouldShowBanner** — read-path writes are unusual; the trade-off is "always-consistent baseline" vs "extra CloudKit save per Home appear". For a Home banner that's called on view-task, this is one save per session-app-resume. Acceptable for v2; if CloudKit quota becomes a concern we can throttle (e.g. only advance once per 6h).
3. **N5 fake semantics divergence vs Live** — the Live client's per-call wrapping makes multi-subscriber legal; the Fake's shared underlying stream does not. Diagnostic-only tracking is the chosen middle ground. A future refactor could move the per-call wrapping into the Fake too, at the cost of FakeIAPClient.emit needing a fan-out broadcaster.
4. **`AdPresentationAnchor` registry shape not yet built** — N1 narrows the type to `UUID`, but the host-side registry (`AdPresentationAnchorRegistry`) is still v2.2 backlog. Resolver helpers in `AdPresentationAnchor+Resolve.swift` take `[UUID: UIWindow]` / `[UUID: NSWindow]` dictionaries; registry implementation will likely wrap one with mutation locks.
