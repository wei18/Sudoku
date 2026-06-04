# Impl Notes — AdMob dispose-gate (#276) (2026-06-05)

Status: COMPLETE
Owner: Developer subagent
Dispatched by: Leader
Started: 2026-06-05

## 設計決定 (Design decisions)

- **Fix (b) status: new `.disposed` case (not reuse `.suppressed`)** — Issue #276 offers
  `.suppressed` OR a dedicated `.disposed`. Chose **`.disposed`**. `.suppressed` carries
  specific gate semantics (purchased Remove Ads / grace period / dismissed-today) and is the
  value `NoopAdProvider` returns on unsupported platforms; conflating teardown with
  gate-suppression would be dishonest in the opposite direction from `.notInitialized`. A
  dedicated `.disposed` is the only fully honest signal: SDK still initialized, this handle's
  view released. Both banner views already have exhaustive switches over `AdBannerStatus`, so
  adding the case forces a deliberate UI branch (render `EmptyView()` — the slot is gone).

- **Fix (a) dispose-gating: `.onChange(of: status)` (handle-change) + `.onChange(of: dismissed)`
  (gate-close), drop raw `.onDisappear`** — Issue says keep `.onDisappear` "only if genuine
  teardown is cheaply distinguishable". In SwiftUI it is NOT cheaply distinguishable from
  transient teardown (TabView switch, List recycling, split-view churn) — that is exactly the
  `swiftui-interaction-footguns` "transient .onDisappear" class. So drop `.onDisappear` dispose
  entirely and tie dispose to the two real lifecycle events:
    1. loaded handle changes — `.onChange(of: status)`: when the previously-loaded handle is no
       longer the current loaded handle (status moved to a different `.loaded`, or to any
       non-loaded state), dispose the OLD handle.
    2. gate closes / user dismisses — `.onChange(of: dismissed)`: dispose the held handle when
       `dismissed` flips true.
  The gate itself (`shouldShow`) only resolves once per `.task` (false→hide collapses the slot
  before any handle loads), so the dismiss path is the live "gate closes mid-session" trigger.

## 偏離 (Deviations)

- **Removed `.onDisappear` dispose entirely** — Spec leaves the door open to keep it; the
  honest reading is that genuine teardown is not cheaply distinguishable in SwiftUI, so keeping
  it would re-introduce the exact thrash the issue reports. On real app teardown (process exit /
  scene disconnect) the SDK reclaims its own `GADBannerView`; the provider's `dispose` is an
  optimization, not a correctness requirement (handle is idempotent + never stale per #221).

## 折衷 (Tradeoffs)

- **Test coverage for fix (a)** — The SwiftUI view-modifier wiring is not unit-testable here
  (existing `HomeViewBannerTests` comments note SwiftUI exposes no synchronous tree-walk; macOS
  CI compiles out the live bridge). TDD applied to fix (b) instead via `BannerDisposeTests`
  (`.notInitialized` → `.disposed`). Fix (a) is verified by reading + matching the footgun
  checklist; no automated coverage feasible (same constraint the issue records).

## 未決 (Open questions)

- None load-bearing.
