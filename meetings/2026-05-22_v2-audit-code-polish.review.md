# v2 Audit Code Polish — Code Review — 2026-05-22

## Verdict

**REQUEST_CHANGES.** Substantively the work is solid: 10/11 findings are correctly addressed, the `MonetizationCore` public surface is preserved (optional init params + optional struct field only), the isolation contract still holds (exactly 1 `internal import GoogleMobileAds`), and the M5 design (24h tolerance + monotonic high-water mark) is sound. However, the **`clockMovedBackwardsRefusesGraceAdvance` test passes for the wrong reason** — it asserts the M5 tamper guard, but rule #2 (`now < firstLaunchAt + 7d`) fires first and short-circuits before the tamper check is ever evaluated. Net effect: M5 has logic but **no real test coverage of the backwards-clock branch**. One required test fix; everything else is APPROVE-quality.

## Per-finding scorecard

| Finding | Intent met? | Risk | Note |
|---|---|---|---|
| M1 (spec ↔ code) | Yes | — | `docs/v2/design.md §How.3` already updated upstream (commit e957ae0); rule #4 replaced with anti-tamper, `lastShownDate`-as-telemetry-only prose in place. No drift. |
| M2 (onPersistenceError) | Yes | low | Closure typed `(@Sendable (any Error) -> Void)?`, default `nil`, default-arg preserves source compat. Cache-update-before-save invariant intact (`AdGate.swift:189-191`). `Live.swift:55-65` wires `[telemetry]`-captured detached Task → no actor blocking. |
| M3 (empty displayPrice + catalog-desync) | Yes | low | Em-dash placeholder is a sensible locale-neutral choice. `onCatalogDesync` closure shape mirrors M2. Wired in `Live.swift:74-86`. |
| M4 (timezone-shift test) | Yes | — | `dismissedTodayAcrossDateLineCrossing` (`AdGateLogicTests.swift:168-197`) uses UTC-fixed calendar, asserts the date-line crossing case correctly. Test is genuinely meaningful — exercises the actual `calendar.isDate(_:inSameDayAs:)` path. |
| M5 (clock-tamper guard) | **Partial** | **medium** | Code logic is correct; tolerance value (86_400s) is defensible. BUT: `clockMovedBackwardsRefusesGraceAdvance` (`AdGateLogicTests.swift:201-227`) uses `firstLaunch = 2026-01-01` and `rewound = 2026-01-01`, so rule #2 (`now < firstLaunch + 7d`) short-circuits → returns false before rule #4 is reached. **See Required #1.** Second test `clockToleranceWithin24hStillShows` IS correctly structured (baseline 2026-05-21, query 1h earlier, firstLaunch 2026-01-01 → past grace → tamper check is what's being exercised). |
| N1 (AdPresentationAnchor → UUID) | Yes | — | `@unchecked Sendable` dropped; `Sendable, Hashable` natural conformances; default-init `UUID()` is a nice ergonomic add. ProtocolShapeTests updated to match. |
| N2 (actor-vs-class) | Deferred (documented) | — | Tracked in §未決, no code change — fine per audit ("if not, this is fine"). |
| N3 (resolver split) | Yes | — | New file `AdPresentationAnchor+Resolve.swift` cleanly separates UIKit/AppKit dependency; original `AdPresentationAnchor.swift` is Foundation-only, supports future SwiftPM `exclude:` for portability. |
| N4 (utility priority) | Yes | — | `.background` → `.utility` for `Transaction.updates` listener. Comment justifies (refund / family-share urgency). |
| N5 (Fake subscribe semantics) | Yes (with deviation) | low | Subagent overrode the audit's "precondition OR document" suggestion based on real production-path constraint: `MonetizationStateController.startListening` cancels and re-subscribes (`MonetizationStateController.swift:110-119`). Verified — cancel happens BEFORE the second `purchaseUpdates()` call, so a precondition would trip on a legitimate restart pattern. Diagnostic-only tracking is the correct call. Doc + `purchaseUpdatesWasSubscribed` accessor is enough. |
| N6 (Sendable compile-time) | Yes | — | `valueTypesRemainSendable` (`ProtocolShapeTests.swift:138-159`) exercises 7 public value types. Test body is trivial-by-design; compile-time signal is the value. |

## Required changes

1. **`AdGateLogicTests.swift:201-227 — `clockMovedBackwardsRefusesGraceAdvance` is a false-positive test.**
   - File: `Packages/AppMonetizationKit/Tests/MonetizationCoreTests/AdGateLogicTests.swift`
   - Line: ~210 (the `firstLaunchAt: firstLaunch` arg in the `AdGateState` construction inside the test) and the test comment claim at line ~225.
   - Problem: `firstLaunch = 2026-01-01`, `rewound = 2026-01-01` → `now == firstLaunchAt < firstLaunchAt + 7d` → rule #2 (grace) returns false first; rule #4 (tamper) is never evaluated. The `#expect(... == false)` assertion holds, but it does **not** verify the M5 behavior the test name + comment claim.
   - Fix: construct a local `earlierFirstLaunch` (e.g. `2024-01-01`) so that the rewound `now = 2026-01-01` is genuinely past the 7-day grace window, AND the existing `firstLaunch` constant is no longer reused. After the fix, flipping the implementation to remove the tamper guard MUST flip this test red — that's the verification criterion.
   - Optional supporting change: add a contrast test `clockMovedBackwardsButWithinFirstLaunchGraceStillSuppresses` that locks in the precedence: if both grace AND tamper would suppress, suppression happens. Cheap insurance.

## Discretionary observations

1. **`saveFailureSurfacesViaOnPersistenceError` (`AdGateLogicTests.swift:251-285`) uses `try? await Task.sleep(nanoseconds: 10_000_000)`** to drain the detached `Task` in the sink wiring. This is brittle on slow CI hosts. Consider replacing with a `withCheckedContinuation`-based wait inside the `Sink` actor (`func waitForFirst() async`). Not a blocker — the timing margin is generous — but flake risk grows if CI saturates.
2. **§未決 #2 (write-on-every-show)** is correctly flagged. Worth noting that `AdGate.advanceWallClock` does guard with `guard now > current` (`AdGate.swift:172`), so back-to-back `shouldShowBanner` calls with the same `now` don't double-write. Real risk is per-tick polling; for v2 Home banner once-per-appear this is fine. Throttle is a v2.x decision, not v2 blocker.
3. **`Live.swift` telemetry wiring** does `String(describing: error)` for both M2 and M3. Two PII considerations: (a) CloudKit errors may include record names / zone IDs; (b) `OSLog` interpolation default is `.private` per project policy. Telemetry facade fan-out to OSLog presumably handles this — verify the Telemetry sink wraps `message:` in a `.private` interpolation before merging.
4. **M5 §未決 #1** notes the `onPersistenceError` closure runs synchronously inside the actor — confirmed safe because the Live wiring hops via `Task { await telemetry.observe(...) }`. If a future host wires it inline (no `Task`), the actor will block on Telemetry. Worth a one-line warning in the `onPersistenceError:` doc comment: "host should not `await` directly inside the closure — wrap in `Task` if Telemetry hop is needed."
5. **`AdPresentationAnchor(id: UUID = UUID())`** — the default arg is fine but means `AdPresentationAnchor()` produces a fresh, useless anchor every time. Could mark `init` as `init(id: UUID)` (no default) and add `static let unspecified` if a sentinel is wanted. Minor API hygiene.
6. **Untracked file `.claude/scheduled_tasks.lock`** showed up in `git status` — verify Leader doesn't accidentally commit it.

## Verification approach the Leader should perform after fix

```bash
cd Packages/AppMonetizationKit && mise exec -- swift test --filter clockMovedBackwardsRefusesGraceAdvance
```
After the test is fixed, temporarily comment out the rule #4 block in `AdGate.shouldShowBanner` (`AdGate.swift:122-126`) and re-run. The test MUST go red. Restore the block. This proves the test exercises the right branch.
