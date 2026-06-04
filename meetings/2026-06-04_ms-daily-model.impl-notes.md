# MS Daily Model (#290) — impl notes

In-flight decision log for the date-seeded Minesweeper Daily puzzle model +
DailyHubView real-content wire. Mirrors Sudoku's Daily.

## Decisions

### UTCDay reuse vs mirror — MIRROR (minimal)
Sudoku's `UTCDay` lives in `SudokuEngine`, a Sudoku-specific package.
MinesweeperEngine importing SudokuEngine would create a wrong-direction
cross-game coupling (MS depending on Sudoku's core). The type is tiny
(one `string(from:)` over a UTC Gregorian calendar). Mirrored a copy as
`MinesweeperEngine/UTCDay.swift`, byte-for-byte the same UTC-day algorithm
so both games bucket days identically.
→ Backlog candidate: extract a shared `CalendarKit`/`TimeKit` leaf both
  game cores depend on. Routed to foundations.md §Backlog (tooling/shared
  infra). Not done here — out of scope, would touch SudokuEngine.

### Daily generation location — MinesweeperEngine (core)
Mirrors Sudoku where deterministic seed derivation sits core-adjacent
(PuzzleStore's `dailySeed` uses the engine's `StableHash`/`SplitMix64`).
Added `MinesweeperDaily` enum in MinesweeperEngine: `seed(day:difficulty:)`
(FNV-1a StableHash over generatorVersion+"daily"+day+difficulty, same recipe
as Sudoku) + `board(date:difficulty:)` → `MinesweeperEngine`. Also mirrored
Sudoku's `StableHash` (private FNV-1a) into the engine since MS lacked one.

### Daily difficulty policy — TRIO (one per difficulty)
Mirror Sudoku's daily trio: three cards, one each at beginner / intermediate
/ expert, each its own date-seeded board. Same date → same three boards for
everyone; rolls at UTC midnight via UTCDay bucketing.

### Daily puzzleId format
`daily-<YYYY-MM-DD>-<difficulty>` (e.g. `daily-2026-06-04-beginner`). Stable
string id used for completion-set matching (`fetchCompletedDailyIds`) and
as the card's Identifiable id. MS has no CrockfordBase32 puzzleId scheme;
a plain readable id is sufficient and mirrors the semantic of Sudoku's
day+difficulty-keyed daily id.

### Completed-state — WIRED (graceful-degrade)
MS `PersistenceProtocol.fetchCompletedDailyIds(for:)` exists (returns []
today — no MS daily save-flow writes completions yet). Wired it through a
`MinesweeperDailyHubViewModel` exactly like Sudoku's `DailyHubViewModel`:
fetch trio + completed-ids, mark cards. Completion-fetch failure degrades to
"none completed" (never blocks the hub). Parity-only until MS save-flow lands.

### Completion test seam — pure `mergeCards` helper (not a stub)
First attempt was a full `PersistenceProtocol` stub injecting a completed-id
set. It compiled-blocked on a `Difficulty` name collision (the test file imports
`MinesweeperEngine`; `PersistenceProtocol`'s signature uses `SudokuEngine`'s
`Difficulty`/`Mode`). Fully qualifying needed `SudokuCoreKit` as a MinesweeperKit
*test* dep — an unwanted cross-game package edge. Resolved by extracting the
trio+completed merge into `MinesweeperDailyHubViewModel.mergeCards(trio:completed:)`
(`nonisolated`, pure) and unit-testing that directly. Production still injects
`any PersistenceProtocol` exactly like Sudoku — only the test seam changed.

### Composition wire
New `MinesweeperDailyProvider` protocol + `LiveMinesweeperDailyProvider`
(thin, wraps `MinesweeperDaily`). Provided via `LiveRouteFactory` and threaded
into the hub VM at the `.daily` route. Preview/test use the same live provider
(pure, zero-IO). Persistence already threaded into the factory (#277).

### Board "first reveal" note
MS mines are placed on first reveal (first-click-safe), so the daily board is
fully deterministic only as `(difficulty, seed)` until first click — same as
any MS board. The daily contract = deterministic `(difficulty, seed)` per UTC
day. Determinism tests assert seed + pre-reveal board identity; mine layout
identity is covered once a first-click is applied (same seed+firstClick →
same layout, which the engine already guarantees).
