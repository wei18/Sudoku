# Impl Notes — 526 Daily Hub Offline Fix (2026-06-16)

Status: IN_PROGRESS
Owner: Developer (Sonnet)
Dispatched by: Leader
Started: 2026-06-16T00:00:00Z

## 設計決定 (Design decisions)

- **Two-phase bootstrap over async-let pair** — The existing code starts `trioCall` and `completedCall` concurrently via `async let`, then awaits the completion call inside an inner do/catch. This design assumes `fetchCompletedDailyIds` either resolves quickly or throws quickly. It does neither when iCloud is unsigned — CloudKit's `database.records(matching:inZoneWith:)` hangs indefinitely without throwing `notAuthenticated` at the query layer. The inner catch therefore never fires, and the hub stays `.loading` forever. Fix: decouple the render from the completion fetch entirely. Render `.loaded(cards with isCompleted=false)` immediately after the trio resolves, then apply completion overlay in a secondary async step that can degrade silently. This is the same two-phase pattern that `MinesweeperDailyHubViewModel` already uses (explicit `var completed: Set<String> = []` + optional persistence guard).

- **No timeout wrapper** — A timeout (e.g. 5s) would also fix the hang, but would delay rendering by 5s on every signed-out launch. The two-phase approach renders immediately and never blocks regardless of how long CK takes. Simpler and better UX.

- **No changes to PersistenceKit** — The hang is CK platform behavior, not a bug in our gateway code. Fixing it at the VM layer (the call site that owns the UX contract) is the right layer per design.md §How.5.4 (hub must never block).

- **Completion fill-in as detached Task** — After `.loaded` is set, a secondary `Task { await fillCompletionOverlay() }` fires. If it succeeds, cards with completion=true update state. If it hangs or errors, the hub stays `.loaded` with all un-completed (graceful-degrade, M10 principle). Task is stored in a property so `bootstrap()` stays idempotent (latch guards the outer call, not the secondary task).

## 偏離 (Deviations)

- **State transitions now: `.loading` → `.loaded(uncompleted)` → optionally `.loaded(with-completion)`** — Spec comment at line 90-95 says "completion-list failure must still degrade gracefully". Previously this was implemented via inner catch. New implementation moves it earlier: trio lands → render → completion fills in. The spec intent is preserved (hub never blocks, completion failure degrades to uncompleted); only the timing changes (cards appear sooner).

- **`fillCompletionOverlay()` is a new private method** — Not in original spec. Required to encapsulate the second-phase logic and make it testable. Named to match the existing method style.

## 折衷 (Tradeoffs)

- **Timeout-on-completedCall vs two-phase** — Considered wrapping `completedCall` in a `withThrowingTaskGroup` with a 3s timeout branch. Rejected: still blocks render for up to 3s; adds complexity; doesn't match the MS reference shape.

- **Cancel-on-trio vs two-phase** — Considered using `withTaskGroup` to cancel `completedCall` when `trioCall` completes. Cleaner structured concurrency but more complex; effectively achieves the same outcome as two-phase minus the ability to fill completion later if it eventually resolves.

- **Chose two-phase** because: (a) matches MS shape exactly (mirror principle), (b) renders immediately, (c) fills completion when CK does come back (iCloud signed in later, or account delay), (d) simpler code than task-group timeout patterns.

## 未決 (Open questions)

- None. Root cause confirmed via code inspection. No open design ambiguities.

Status: COMPLETE
