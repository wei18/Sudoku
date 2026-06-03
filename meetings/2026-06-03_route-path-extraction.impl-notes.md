# Impl Notes — Route-path injection extraction (#240) (2026-06-03)

Status: COMPLETE
Owner: Developer subagent
Dispatched by: Leader
Started: 2026-06-03

## 設計決定 (Design decisions)

- **Helper shape: generic value-type struct `RoutePath<Route>`** — Issue #240 asks
  for the `localPath + injected-Binding<[Route]>? + computed-path` idiom (hand-rolled in
  HomeViewModel / DailyHubViewModel / PracticeHubViewModel) to be extracted to ONE generic
  helper in `GameShellUI`. Chose a **generic-over-`Route` struct** that wraps the optional
  `Binding<[Route]>?` + a `localPath` store, exposing `effectivePath` get/set + `append`.

  Why a struct (not a class / not a property wrapper):
  - The three VMs are `@MainActor @Observable final class`. With `@Observable`, observation
    tracking is per stored property. Storing the helper as a **non-`@ObservationIgnored` `var`**
    means any mutation of its `localPath` flows through the synthesized `@Observable` setter of
    the wrapping property → SwiftUI still re-renders on local-stub navigation. A struct's
    value semantics make "mutate the struct" == "set the property", which is exactly what
    `@Observable` instruments. A reference type would NOT get this for free (mutating an inner
    class field doesn't trip the outer property's observation).
  - The injected `Binding<[Route]>` lives inside the struct as a plain stored value. The
    binding's *target* (RootViewModel.path) is observed at its own site; the VM only needs to
    forward writes. So no `@ObservationIgnored` gymnastics are needed on the binding — it just
    rides inside the struct.

  Net: VM declares `private var routePath: RoutePath<AppRoute>` and keeps a thin public
  `path` computed property forwarding to `routePath.effectivePath`. Public `path` get/set
  behavior + observable surface are byte-identical to today.

## 折衷 (Tradeoffs)

- **Rejected: property wrapper (`@RoutePath`)** — SwiftUI/`@Observable` + custom property
  wrappers interact badly (observation of wrapped storage is fragile; `@Observable` macro does
  not compose cleanly with arbitrary wrappers, and a binding-backed wrapper would fight the
  observation machinery #197 cares about). Too much risk for zero behavior gain.
- **Rejected: base class (`RoutePathHostViewModel<Route>`)** — the three VMs already subclass
  nothing and are `final`; forcing a shared superclass coupling unrelated VMs (Home has no
  services; Daily/Practice have providers) for ~6 lines of shared state violates SRP and the
  "surgical change" rule. Also `@Observable` + inheritance has sharp edges.
- **Rejected: protocol-with-default-impl** — a protocol can't add stored properties; it would
  need an associated stored requirement the conformer still declares by hand, so the
  duplication (the `localPath`/`externalPath` decls) would NOT actually go away. Fails the
  success criterion ("no longer each declare localPath/externalPath").
- **Picked: value-type struct** — only option that (a) removes all three stored-property
  duplications, (b) preserves `@Observable` tracking for the local-stub branch for free,
  (c) doesn't touch public `init` signatures, (d) is trivially `Sendable` when `Route: Sendable`.

## Sendable note (swift6-concurrency)

`Binding` is not `Sendable`. The struct is only ever constructed + used inside `@MainActor`
VMs, so it does NOT need to be `Sendable`; it is `@MainActor`-isolated by virtue of living on
`@MainActor` VM stored properties. We do not mark it `Sendable` (can't — `Binding` blocks it),
matching how the VMs already hold a non-Sendable `Binding` today. No new concurrency surface.

## 未決 (Open questions)

- None load-bearing. Behavior is asserted identical by the existing #171 interaction tests
  (11 tests across the three hubs), which are the safety net.
