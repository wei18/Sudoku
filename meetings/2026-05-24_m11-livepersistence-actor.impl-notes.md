# 2026-05-24 — M11: LivePersistence → actor

GitHub issue #68 (Wave 3 concurrency audit). Branch
`refactor/m11-livepersistence-actor`.

## Goal

Bring `LivePersistence` in line with the other 5 actor-based persistence
modules (`SavedGameStore`, `PersonalRecordStore`, `LivePrivateCKGateway`,
`AccountMonitor`, `LiveMonetizationStateStore`). Drop the
`final class @unchecked Sendable` + `NSLock`-guarded lazy-init pattern in
favour of native actor isolation.

## Before / after shape

`Packages/SudokuKit/Sources/Persistence/LivePersistence.swift`

| | Before | After |
|---|---|---|
| Declaration | `public final class LivePersistence: PersistenceProtocol, @unchecked Sendable` | `public actor LivePersistence: PersistenceProtocol` |
| Lazy slots | `_gateway / _savedGameStore / _personalRecordStore` guarded by `private let lock = NSLock()` | same three slots, actor-isolated |
| `gateway()` / `savedGameStore()` / `personalRecordStore()` | `lock.lock() / defer { lock.unlock() } / read-or-init` | plain `if let existing { return existing }; init; cache` (actor serialises) |
| `bootstrap()` + 9 `PersistenceProtocol` methods | `async throws` (unchanged signatures) | `async throws` (unchanged signatures) |
| `monetizationStateStore()` | `public func ... -> LiveMonetizationStateStore` (sync, uses `[weak self]` closure that called `self.gateway()` synchronously) | `public nonisolated func ... -> LiveMonetizationStateStore` returning a store whose `gatewayProvider` closure is `{ LivePrivateCKGateway() }` |

`NSLock` import dropped (was implicit via `Foundation`); no other field
or signature changes.

## §monetizationStateStore design call-out

The old shape captured `[weak self]` and synchronously called the
facade's locked `gateway()` accessor so AdGate's store would *share* the
facade's `LivePrivateCKGateway`. That synchronous cross-instance call
cannot survive actor isolation (would require `await`, but
`gatewayProvider` is `@Sendable () -> any PrivateCKGateway`).

Three options considered:

1. **Make `monetizationStateStore()` `async`** and eager-construct the
   gateway inside the actor. Rejected — eager `LivePrivateCKGateway()`
   traps in test contexts (no iCloud entitlement), and
   `AppComposition.live()` is invoked from `CompositionTests`.
2. **Add a `nonisolated` lock-guarded gateway slot** alongside the
   actor-isolated one. Rejected — re-introduces the very `NSLock` the
   audit asked us to remove, for a single slot.
3. **`nonisolated monetizationStateStore()` with its own lazy
   provider** (chosen). The store owns a separate
   `LivePrivateCKGateway` instance. Behaviour stays correct because:
   - `LivePrivateCKGateway.provisionZone()` and
     `installSubscriptionIfNeeded()` are guarded by per-instance
     `zoneProvisioned` / `subscriptionInstalled` bools, and the
     server-side `modifyRecordZones` / `modifySubscriptions` calls are
     idempotent for the same zone-id / subscription-id.
   - The only caller of `LivePersistence.bootstrap()` is composition
     wiring; `LiveMonetizationStateStore` does not call provisioning,
     so the per-instance bootstrap flag drift is harmless.

The chosen option matches the "minimal call-site churn" constraint:
`AppComposition.live()` line 51 (`persistence.monetizationStateStore()`)
stays synchronous — zero diff in the call site.

## Callers updated

`rg "LivePersistence\b"` matches:

| File | Action |
|---|---|
| `Packages/SudokuKit/Sources/AppComposition/Live.swift` | None. `LivePersistence(...)` init unchanged; all protocol methods stay `async throws`; `monetizationStateStore()` stays sync via `nonisolated`. |
| `Packages/SudokuKit/Sources/Persistence/Live/LiveMonetizationStateStore.swift` | None. Doc-comment only mention. |
| `Packages/SudokuKit/Tests/AppCompositionTests/CompositionTests.swift` | None. Mirror-based reflection on type name only. |
| `Packages/SudokuKit/Tests/PersistenceTests/SaveIdentityRoutingTests.swift` | None. Test name string only. |

Net caller files touched: **0**.

## Verification

```
$ mise exec -- swift build 2>&1 | tail -3
[72/72] Compiling AppComposition Live.swift
Build complete! (4.68s)

$ mise exec -- swift test --filter "Persistence|Live" 2>&1 | tail -2
Test run with 64 tests in 15 suites passed after 0.006 seconds.
```

Full `swift test` (no `--parallel`, per issue #82 toolchain bug) — see
report.

## §未決

1. **Re-entry**: `bootstrap()` calls `gateway()` (suspension point on the
   `LivePrivateCKGateway` actor) twice within the same async function
   (`provisionZone` then `installSubscriptionIfNeeded`). Both inner
   calls are guarded by their own actor bools, so interleaved
   `bootstrap()` invocations from different tasks are safe — but the
   `_gateway` slot itself is read three times. Inside one actor hop the
   slot can only mutate while we are suspended at an `await`, and the
   first read returns a cached value, so this is benign.
2. **Per-instance gateway** (see design call-out above): chosen
   deliberately. Worth a follow-up if a future feature needs the
   monetization store to observe the facade's gateway state (e.g.
   piggy-backing on the same `subscriptionInstalled` flag); at that
   point we'd need to refactor `LiveMonetizationStateStore`'s provider
   contract to be `async`.
3. **`nonisolated` escape hatch**: `monetizationStateStore()` is the
   only `nonisolated` member of the actor. The facade itself remains
   `Sendable` via actor isolation. The factory does not touch actor
   state, only constructs a fresh `LiveMonetizationStateStore`, so the
   `nonisolated` annotation is sound by inspection.
