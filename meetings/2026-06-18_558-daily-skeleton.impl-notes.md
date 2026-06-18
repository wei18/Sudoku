# Impl Notes — 558 daily-load skeleton (2026-06-18)

Status: IN_PROGRESS
Owner: Developer (Sonnet)
Dispatched by: Leader
Started: 2026-06-18T00:00:00Z

## 設計決定 (Design decisions)

- **Skeleton home = GameShellUI** — The two-phase orchestration is pure control
  flow over injected closures: `fetchPhase1()` (sync or async, non-throwing) and
  `fetchPhase2()` (async throws). No ErrorReporter type reference is needed in
  the skeleton itself; the caller (each VM) holds `errorReporter` and passes a
  closure that calls `errorReporter.report(...)`. This keeps GameShellUI
  zero-dependency — no import of TelemetryKit, PersistenceKit, or GameAppKit.

- **Shape = free async generic function `performDailyBootstrap<Trio>`** — Lowest-ceremony shape
  that avoids new types and protocol conformances. Both VMs call it from their
  `bootstrap()` body passing game-specific closures. A generic helper type (e.g.
  `DailyBootstrapCoordinator<State>`) was considered but rejected: it would require
  the VMs to store it as a property, and it brings no benefit over a free function
  for a single-call-site idiom.

- **Phase-1 returns `Trio` (generic), threaded to `onPhase1` and `fetchPhase2`** —
  Sudoku's provider is `async throws`; MS's is sync+non-throwing. Both fit a
  `() async throws -> Trio` closure (MS wraps trivially). The fetched trio is
  returned from phase-1 and passed by the skeleton to both `onPhase1` (for immediate
  card render) and `fetchPhase2` (for overlay fill). This avoids any transient
  stored property on the VM — no `_bootstrapTrio` intermediate.

- **Phase-2 is `(Trio) async -> Void`** — Each VM encodes its own overlay fetch +
  error reporting + state mutation inside the phase-2 closure. The skeleton just
  calls it and is done. This means the skeleton never needs to know about
  `ErrorReporter` or `PersistenceProtocol`.

- **`hasBootstrapped` stays inside each VM** — The latch is per-instance state. The
  free function doesn't own it; each VM does `guard !hasBootstrapped else { return };
  hasBootstrapped = true` before calling the skeleton; the skeleton only runs after
  the guard.

- **`isOpeningCompleted` (Sudoku) stays in SudokuUI** — This is Sudoku-specific
  routing logic, not orchestration. Not moved.

## 偏離 (Deviations)

- **No state parameter threading** — The skeleton does NOT take a `state` inout
  or a state-setter closure. Instead, each VM passes a `setLoading` closure and the
  phase-1 completion closure sets state inside the caller's context. This avoids
  threading `@MainActor` state mutation through a generic free function signature,
  which would require `@MainActor` annotations on every closure parameter and
  complicate the Swift 6 concurrency picture. The design keeps state mutation at the
  VM level where it is already `@MainActor`.

- **Skeleton signature is intentionally narrow** — The function signature is:
  ```swift
  func performDailyBootstrap<Trio: Sendable>(
      setLoading: () -> Void,
      fetchPhase1: () async throws -> Trio,
      onPhase1: (Trio) -> Void,
      onPhase1Error: (Error) async -> Void,
      fetchPhase2: (Trio) async -> Void
  ) async
  ```
  `setLoading`, `fetchPhase1`, `onPhase1`, `fetchPhase2` are called in order;
  if phase-1 throws, `onPhase1Error` is invoked instead and phase-2 is skipped.
  The `Trio` result threads phase-1 output to both `onPhase1` and `fetchPhase2`
  without any stored property on the VM. This covers both VMs exactly.

## 折衷 (Tradeoffs)

- **Free function vs generic type** — Chose free function. A generic type would give
  testability of the skeleton itself but both VMs already have their own test coverage
  and the skeleton is ~12 lines; testing it in isolation would only test that
  async/await chains correctly, which is not a risk area.

- **GameShellUI vs GameAppKit** — GameShellUI preferred because: (1) zero-dep rule
  is maintained (closures are opaque to the skeleton); (2) the function doesn't
  import any framework beyond Foundation via indirect use. GameAppKit would have been
  required only if the skeleton needed an `ErrorReporter` parameter type, which it
  doesn't.

## 未決 (Open questions)

_None — all decisions made with sufficient evidence from reading both VMs._

Status: COMPLETE
