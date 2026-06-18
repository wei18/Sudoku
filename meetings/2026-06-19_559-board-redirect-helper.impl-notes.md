# Impl Notes — 559 board-redirect helper (2026-06-19)

Status: IN_PROGRESS
Owner: Developer (Sonnet)
Dispatched by: Leader
Started: 2026-06-19T00:00:00Z

## 設計決定 (Design decisions)

- **Free function vs method** — Chose a top-level `@MainActor public func boardDestination(...)` free function in `GameBoardRedirect.swift` (same file, same module). A free function requires no `self`, matches the call pattern cleanly, and avoids introducing a new type. Alternative: static method on `GameBoardRedirect`; rejected — forcing callers to write `GameBoardRedirect.boardDestination(...)` adds noise vs a module-scoped function that reads identically to an extension.

- **Generic Route constraint** — `Route: Hashable & Sendable` mirrors `GameBoardRedirect`'s existing constraint. Matches the `RouteFactory.Route` protocol constraint (Hashable). Added `Sendable` because `GameBoardRedirect` already requires it and `onPresentBoard` is `@MainActor`.

- **`buildInline` closure return type** — `AnyView` (not `some View`) so callers can wrap any heterogeneous view without a generic explosion on the function signature. Consistent with `RouteFactory.view(for:path:) -> AnyView`.

- **MS `.replayDailyBoard` case included** — Minesweeper has 3 board-redirect cases, not 2. `.replayDailyBoard` uses the same `if let onPresentBoard, path != nil` guard as `.board` and `.resumeBoard`. All 3 migrate.

## 偏離 (Deviations)

None. The helper exactly encodes the existing guard (onPresentBoard != nil AND path != nil → redirect; else → buildInline) with no behavioral change.

## 折衷 (Tradeoffs)

- **Single file vs new file** — Added helper to `GameBoardRedirect.swift` (same conceptual unit) rather than a new `BoardDestination.swift`. File stays well under the 400-line limit post-addition (~80 lines total). Keeps the two related pieces together so future readers understand the contract without jumping files.

- **`@autoclosure` vs regular closure for buildInline** — Chose regular `() -> AnyView` because call sites already have multi-line view construction that doesn't benefit from autoclosure syntax. Avoids adding trailing closure complexity.

## 未決 (Open questions)

None — spec is unambiguous; all 3 factories have been read and all redirect cases confirmed.

Status: COMPLETE
