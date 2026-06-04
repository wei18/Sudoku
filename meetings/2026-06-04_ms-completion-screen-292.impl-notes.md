# MS Completion Screen (#292) — impl notes

Date: 2026-06-04
Branch: feat/ms-completion-screen-292

## Goal
Replace the inline `terminalOverlay` (plain Text on material) on MinesweeperBoardView
with a real themed Completion surface mirroring Sudoku's `CompletionView` +
`CompletionViewModel`: result hero (You won / Boom), elapsed time, a GC leaderboard
slice centred on the local player, graceful loading/unauthenticated/failed states,
and CTAs (New Game, Retry, View leaderboard → native GC modal).

## Key reads (mirrored)
- SudokuUI/Completion/CompletionView.swift + CompletionViewModel.swift — the shape.
- MinesweeperBoardView.swift — current `terminalOverlay` (lines 210-220), `isTerminal`,
  `status`, `elapsedSeconds`.
- MinesweeperLeaderboardID.bestTime(for:) — per-difficulty leaderboard id.
- MinesweeperGameCenterDashboard.present(leaderboardId:) — native GC modal CTA.
- GameCenterClient.fetchLeaderboardSlice(... aroundLocalPlayer: Bool, limit:) — #150 narrowed.
- MinesweeperTheme tokens.

## Design decisions / deviations

### D1 — Presentation: overlay, NOT a pushed route
Sudoku presents Completion as a *pushed* `.completion` AppRoute via `LiveRouteFactory`,
because Sudoku's board/daily flow drives navigation through the route stack. MS's board
owns its win/lose state INLINE (the board already renders `terminalOverlay` on top of
itself via `.overlay`); MS has NO `.completion` AppRoute and the board is constructed
directly (not always via a path). Introducing a completion route + threading a path
binding into the board would be a much larger, non-surgical change touching AppRoute /
RouteFactory / every board callsite.

Decision: present the Completion surface as a **full-board overlay** in place of the
existing `terminalOverlay`, gated on `viewModel.isTerminal`. This keeps the Tier-0 board
layout intact, is surgical, and matches "replace/upgrade the inline terminalOverlay".
The CompletionViewModel still owns the leaderboard-slice/auth/CTA logic exactly like
Sudoku's — only the *mounting* differs (overlay vs route push), which the spec
explicitly allows ("overlay or pushed").

### D2 — aroundLocalPlayer: true (per #150)
Sudoku's CompletionViewModel fetches with `aroundLocalPlayer: false` (top-3). The #292
spec says the MS slice should be **centred on the local player** (`aroundLocalPlayer: true`).
Following the spec → MS VM passes `aroundLocalPlayer: true`. Otherwise the VM is a
near-verbatim mirror.

### D3 — best-time display
The spec mentions "elapsed time + best-time". Sudoku's CompletionView hero shows ONLY
elapsed (no separate best-time store; the leaderboard slice IS the best-time context).
MS has no local best-time persistence either (MVP GameViewModel has no persistence).
The "best time" for a win is the just-played elapsed time submitted to the leaderboard;
the leaderboard slice rows ARE the best-time comparison. So the hero shows elapsed
(labelled as the player's time) and the leaderboard slice shows the field's best times,
mirroring Sudoku. No new persistence introduced (out of scope / would be speculative).

### D4 — CTAs
- New Game → routes to root (calls an injected `onNewGame` closure).
- Retry → restart same difficulty (injected `onRetry` closure).
- View leaderboard → `MinesweeperGameCenterDashboard.present(leaderboardId:)` (native modal).
The board owns a fresh-session reset for Retry; New Game dismisses to root. Since the
overlay lives inside the board, the board supplies these closures. To keep the board
self-contained (it's constructed with difficulty+seed and has no path binding), Retry
rebuilds the session in-place; New Game is wired via an optional closure the Root/Home
can pass (defaults to no-op for previews).

### D5 — Degrade non-blocking
A failed slice fetch → `.failed` state shows hero + Retry; never blocks the win moment
or the New Game CTA. `.unauthenticated` → hero + Sign in CTA. Mirrors Sudoku verbatim.

### D6 — reveal-all-mines-on-loss → DEFERRED to #298
The #298 critique listed "reveal all mines on loss" as a board-grid concern. It requires
the engine/session to expose the full mine layout on loss and the board grid to render
it — a board-rendering change, not a Completion-surface change. It does not fit naturally
inside the Completion overlay (which sits ON TOP of the board). Deferring to #298 to keep
this PR surgical (Completion surface only, no board-grid restyle).

## Tests (CompletionViewModel)
- win → completion state shown (board isTerminal drives overlay; VM bootstrap → loaded)
- elapsed label formatting
- slice load (loaded) + degrade (failed/unauthenticated via setStateForTesting seam,
  mirroring Sudoku — FakeGameCenterClient has no fetch-error knob)
- aroundLocalPlayer: true is passed to fetch
- CTA: viewLeaderboardTapped reaches GC dashboard (smoke; native singleton not assertable)
