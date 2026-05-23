# M11 LivePersistence Actor — Code Review — 2026-05-24

## Verdict

**APPROVE.** The conversion from `final class @unchecked Sendable + NSLock`
to `actor` is mechanically clean and behaviourally equivalent. All three
lazy slots (`_gateway`, `_savedGameStore`, `_personalRecordStore`) are now
serialised by actor isolation, matching the other 5 actor-based persistence
modules. The single `nonisolated` escape hatch (`monetizationStateStore()`)
is sound by inspection: its body touches no actor state and returns a fresh
store with a self-owned gateway provider. Caller diff is zero, build green,
tests green. The trade-off documented in impl-notes (per-instance gateway
for the monetization store) is conscious, well-reasoned, and acceptable
given CloudKit's idempotent zone/subscription semantics.

## Soundness checklist

| Check | Pass |
|---|---|
| NSLock removed (no `lock.lock()` / `defer { lock.unlock() }` left in file) | ✓ |
| Actor isolation enforces serial access on `_gateway` / `_savedGameStore` / `_personalRecordStore` | ✓ |
| `nonisolated monetizationStateStore()` touches no actor state — only calls `LiveMonetizationStateStore.init(gatewayProvider:)` with a fresh `@Sendable { LivePrivateCKGateway() }` closure | ✓ |
| `bootstrap()` re-entry — `gateway()` called once locally (let-bound), then `provisionZone()` + `installSubscriptionIfNeeded()` on the cached `LivePrivateCKGateway` actor; concurrent task interleaving safe via outer actor + inner gateway-instance bools | ✓ |
| `PersistenceProtocol` conformance — all 9 methods already `async throws`, no signature drift; protocol stays `Sendable` and existential `any PersistenceProtocol` still crosses actor boundaries | ✓ |
| Caller sites updated — verified via `rg "LivePersistence\b"`: `AppComposition/Live.swift` (init + `.monetizationStateStore()` sync via `nonisolated`), `CompositionTests.swift` (mirror string match), `SaveIdentityRoutingTests.swift` (test name string). Zero call-site diffs needed. | ✓ |

## Detailed notes

### nonisolated factory soundness (line 147–151)

```swift
public nonisolated func monetizationStateStore() -> LiveMonetizationStateStore {
    LiveMonetizationStateStore(
        gatewayProvider: { LivePrivateCKGateway() }
    )
}
```

Reads no actor-isolated state (no `self._gateway`, no `self.telemetry`,
no `self.puzzleLoader`). Captures nothing from `self`. The returned closure
is `@Sendable () -> any PrivateCKGateway` and constructs a brand-new
`LivePrivateCKGateway` per call (lazily, inside the monetization store).
This is the textbook `nonisolated` use case — a pure factory.

### bootstrap() re-entry (line 71–75)

```swift
public func bootstrap() async throws {
    let gateway = gateway()
    try await gateway.provisionZone()
    try await gateway.installSubscriptionIfNeeded()
}
```

The implementation reads `_gateway` exactly once (via the local `gateway()`
call) and let-binds the result. Subsequent awaits operate on the captured
local, not on a re-fetched slot. Two concurrent tasks invoking `bootstrap()`
on the same `LivePersistence` instance:

1. Both enter the actor; one runs `gateway()` to completion (sync, no
   suspension inside `gateway()` itself) — `_gateway` is populated.
2. The second `gateway()` returns the cached instance.
3. `provisionZone` / `installSubscriptionIfNeeded` are guarded inside
   `LivePrivateCKGateway` by its own `zoneProvisioned` / `subscriptionInstalled`
   bools, and the CloudKit `modifyRecordZones` / `modifySubscriptions` calls
   are server-side idempotent.

No TOCTOU. No double-init.

### Per-instance gateway for monetization store

Acknowledged trade-off (impl-notes §未決 #2): `LiveMonetizationStateStore`
constructs a separate `LivePrivateCKGateway`, not the facade's slot. This
is safe today because:

- `LiveMonetizationStateStore` never calls `provisionZone()` /
  `installSubscriptionIfNeeded()` (only `fetch` / `save` on
  `monetization-state` record), so the per-instance bootstrap-flag drift
  cannot diverge.
- Even if it did, CloudKit `modifyRecordZones` / `modifySubscriptions` are
  idempotent server-side.

If a future feature ever wants the monetization store to observe the
facade's gateway state, the right move is to make
`LiveMonetizationStateStore`'s provider contract `async` — not to re-introduce
a `nonisolated` lock here. Logged in impl-notes already; no action this PR.

### Caller site count

Total `rg "LivePersistence\b"` hits: **7** in production + test sources.

| File | `await` required? |
|---|---|
| `AppComposition/Live.swift:40` (init) | No — `init` is `nonisolated` by default for actors |
| `AppComposition/Live.swift:51` (`monetizationStateStore()`) | No — `nonisolated` |
| `CompositionTests.swift:32` | No — `String(describing:)` reflection |
| `SaveIdentityRoutingTests.swift:26` | No — test name string |
| Doc-comment mentions ×3 | No — comments only |

Caller diff: **0**. Matches impl-notes claim.

## Required changes

None.

## Nits (non-blocking)

- 💭 The comment on line 30 ("Actor isolation serialises the first-touch
  races that previously required an explicit `NSLock`") is helpful — keep it.
- 💭 Consider a brief inline `// nonisolated: pure factory, touches no actor
  state` annotation next to line 147 to make the soundness obvious without
  having to read the doc-comment block. Optional.

## Praise

- The decision to keep `monetizationStateStore()` sync via `nonisolated`
  (over making it `async` and breaking the synchronous composition root)
  shows good judgment — minimises blast radius, preserves the
  test-callability invariant of `AppComposition.live()`.
- impl-notes §未決 anticipates the exact questions a reviewer would ask
  (re-entry, per-instance gateway, `nonisolated` soundness). Excellent
  hand-off discipline.
