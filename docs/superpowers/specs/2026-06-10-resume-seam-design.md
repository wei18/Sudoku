# Game-agnostic resume seam — design (#455)

_2026-06-10. Approach A (approved). Scope: the resume seam + Sudoku migration. MS store / CloudKit schema / MS wiring are downstream #455 steps._

## Problem

The Home "Resume" pill flows through one type, `SavedGameSummary`, which is **Sudoku-typed**:

- `mode: SudokuEngine.Mode` (`daily | practice`) — Minesweeper has no mode.
- `difficulty: SudokuEngine.Difficulty` (`easy | medium | hard`) — Minesweeper is `beginner | intermediate | expert`.

That type is returned by `PersistenceProtocol.latestInProgress()` **and** consumed by `GameAppKit.GameRootViewModel`'s `resumeRoute: ((SavedGameSummary) -> Route)?`. So Minesweeper cannot produce a truthful resume candidate, and `GameRootViewModel` is coupled to the Sudoku-typed persistence surface. (The existing MS placeholder already lies: `SavedGameSummary(mode: .daily, difficulty: .easy)` for a `"…-beginner"` puzzle.)

Decision (confirmed): make the seam **N-game reusable** — a future 3rd game plugs in for free.

## Approach A — game-agnostic resume DTO at the GameAppKit seam

Draw the game-agnostic boundary at GameAppKit (the resume seam), **not** at PersistenceKit. The pill only needs a label + a destination; that is genuinely game-agnostic. Persisted state stays per-game. Sudoku's `SavedGameSummary` / `PersistenceProtocol` / store / CloudKit are untouched (zero shipping risk).

### Components

**1. New — `GameAppKit/ResumeCandidate.swift`**
```swift
public struct ResumeCandidate<Route: Hashable & Sendable>: Sendable, Equatable {
    public let title: String      // game-mapped, e.g. "Resume Beginner" / "Resume Easy"
    public let subtitle: String   // e.g. "3:42"
    public let route: Route       // where tapping navigates
    public init(title: String, subtitle: String, route: Route)
}
```
(`Route: Hashable & Sendable` so the unconditional `Sendable` conformance compiles; both apps' `AppRoute` are value-type enums and already satisfy it.)

**2. `GameAppKit/GameRootViewModel<Route>` — replace the Sudoku-typed resume with a closure**
- Remove: `resumeCandidate: SavedGameSummary?`, `resumeRoute: ((SavedGameSummary) -> Route)?`, and the direct `persistence.latestInProgress()` call.
- Add: `fetchResume: (() async throws -> ResumeCandidate<Route>?)?` (injected; `nil` ⇒ resume disabled — replaces the `supportsResume`/`resumeRoute != nil` derivation). Throwing so `GameRootViewModel` owns the error funnel in one place (matching today's `latestInProgress` catch).
- `resumeCandidate` becomes `ResumeCandidate<Route>?`.
- `bootstrap()` keeps `persistence.bootstrap()` (the #450 CloudKit-zone provisioning fix) + Game Center auth; then `if let fetchResume { resumeCandidate = await fetchResume() }`. Failures funnel to `errorReporter` and leave `resumeCandidate == nil` (same tolerance as today's `latestInProgress` catch).
- `resumeTapped()`: `guard let c = resumeCandidate else { return }; path.append(c.route)`.
- `persistence: any PersistenceProtocol` dependency **stays** — still required for `bootstrap()`. It no longer feeds resume; that decoupling is what unblocks MS.

**3. `GameAppKit/ResumePill.swift` — render the DTO**
- Takes `title` / `subtitle` (+ `onTap`) directly instead of `SavedGameSummary`.
- The `"Resume \(difficulty)"` + `%d:%02d` elapsed formatting **moves out** into each game's `fetchResume` mapping.
- Rendering (icons, layout, paddings, theme) stays byte-identical so Sudoku snapshot baselines do not change.

**4. Sudoku migration (reference consumer)**
Composition injects:
```swift
fetchResume: {                                     // async throws — VM catches+funnels
    guard let s = try await persistence.latestInProgress() else { return nil }
    return ResumeCandidate(
        title: "Resume \(s.difficulty.rawValue.capitalized)",
        subtitle: elapsed(s.elapsedSeconds),           // moved-out "%d:%02d"
        route: .board(puzzleId: s.puzzleId)
    )
}
```
`SavedGameSummary` / `PersistenceProtocol` / `SavedGameStore` / CloudKit untouched. `RootView`'s `rootContent` reads `viewModel.resumeCandidate` (now the DTO) and builds `ResumePill(title:subtitle:onTap:)`. The `elapsed()` `"%d:%02d"` helper (deleted from `ResumePill`) lands as a small private helper in Sudoku's `AppComposition` (next to the `fetchResume` closure) — single home, so the byte-identical string is not re-implemented divergently.

**5. Minesweeper**
Stays `fetchResume: nil` today (no MS store yet). When the MS store lands (downstream #455 steps), MS injects its own `fetchResume` returning `ResumeCandidate(title:"Resume \(msDifficulty)", subtitle:…, route:.board(difficulty:seed:mode:))`. **No further GameAppKit change** — the seam is ready; MS resume becomes one injection away.

## Data flow

`bootstrap()` → (`fetchResume?()`) → `resumeCandidate: ResumeCandidate<Route>?` → game's `rootContent` renders `ResumePill(title, subtitle)` in the Home header → tap → `resumeTapped()` → `path.append(candidate.route)`.

## Error handling

`fetchResume` throw/failure → `errorReporter.report(…, source: "GameRootViewModel.bootstrap.resume")`; `resumeCandidate` stays `nil` (no pill). Mirrors the current `latestInProgress` catch. Resume is never allowed to block Root (design.md §How.5.1).

## Migration checklist (all compile-breaking consumers — from CR audit)

The `resumeCandidate: SavedGameSummary? → ResumeCandidate<Route>?` and `resumeRoute → fetchResume` change breaks these — every one must be migrated or the build fails:

| File | Change |
|---|---|
| `GameAppKit/GameRootViewModel.swift` | primary: drop `resumeRoute`/`SavedGameSummary` resumeCandidate + `latestInProgress()` call; add `fetchResume`; `resumeCandidate` → DTO |
| `GameAppKit/ResumePill.swift` | API → `(title:subtitle:onTap:)`; delete `elapsedLabel`/difficulty computation |
| `SudokuKit/AppComposition/Live.swift` (~177-182) | `resumeRoute:` → `fetchResume:` closure + `elapsed()` helper |
| `SudokuKit/AppComposition/Preview.swift` (~54-59) | **second composition site** — same `resumeRoute:` → `fetchResume:` |
| `SudokuKit/SudokuUI/Root/RootView.swift` (109-110) | `resumeCandidate` is now DTO; `ResumePill(candidate:)` → `ResumePill(title:subtitle:onTap:)` |
| `SudokuKit/Tests/SudokuUITests/RootViewTests.swift` (7× ctor + `:101`) | inject `fetchResume:`; **`:101 #expect(resumeCandidate == summary)` must change** (DTO ≠ `SavedGameSummary`) |
| `GameAppKit/Tests/GameRootViewModelTests.swift` (5 tests incl `:155,:208`) | **rewrite**: `resumeRoute:`→`fetchResume:`; `resumeCandidate == summary` assertions → DTO; `StubPersistence.resumeCandidate` no longer drives the VM (keep for `latestInProgress` conformance only) |
| `MinesweeperKit/MinesweeperRootViewModel.swift:17` | none (typealias); stays `fetchResume: nil` |

**Confirmed out-of-scope (CR-verified independent):** `SudokuUI/Settings/SettingsViewModel.swift` (its own `resumeCandidate: SavedGameSummary?` for clear-cache) + `SettingsViewTests`; `MinesweeperUI/.../LiveRouteFactory.swift:255` clear-cache `latestInProgress`; all PersistenceKit `SavedGameSummary` sites.

## Testing

- **GameAppKit unit tests** (rewrite the existing 5): `fetchResume == nil` ⇒ no fetch, `resumeCandidate == nil`, `resumeTapped()` no-ops. `fetchResume` returns a candidate ⇒ `resumeCandidate` set, `resumeTapped()` appends `candidate.route`. `fetchResume` throws ⇒ `nil` + error funneled. Use a tiny test `enum Route: Hashable & Sendable`.
- **Sudoku `RootViewTests`:** inject a `fetchResume`; resume-pill snapshot stays byte-identical (same "Resume Easy" + elapsed) ⇒ no PNG re-record.
- **No production behavior change for Sudoku** — same pill, same navigation.

## Out of scope (downstream #455)

- MS in-progress board persistence + an MS saved-game store (blocked on the Sudoku-coupled `LivePersistence`/`PersistenceProtocol` — MS gets its own store/fetch).
- `cloudkit/minesweeper.ckdb` `SavedGame` record type + `ck:schema` deploy (**user-owned**; the `.ckdb` is user-seeded, absent from the repo).
- Wiring MS's `fetchResume` into its composition.

After this seam ships, those remain — but the GameAppKit side is done and N-game-ready.
