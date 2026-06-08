# Impl Notes — #418 shared completion / game-over view (2026-06-09)

Status: COMPLETE
Owner: Senior Developer
Dispatched by: Leader
Started: 2026-06-09

## Step-0 assessment (shared vs divergent)

### Structurally identical (across Sudoku + MS)
- Result hero card: SF Symbol + large-title result label + elapsed time (`m:ss`, monospacedDigit), wrapped in `.glassEffect(.regular, in: .rect(cornerRadius: 20))`, `.accessibilityElement(children:.combine)`.
- Outer shell: `ScrollView { VStack(spacing:24){…}.padding(20).frame(maxWidth:.infinity) }.frame(maxWidth/maxHeight:.infinity).background(theme.surface.background.resolved).task{ bootstrap }`.
- Leaderboard slice section: "Leaderboard" headline + rank/name/score rows — BYTE-IDENTICAL between the two (same paddings, widths, fonts, token colors).
- `.unauthenticated` block: person-badge icon + "Sign in to Game Center…" copy. (Sudoku adds a "Sign in" button; MS does NOT — divergent, see below.)
- `.failed` block: warning triangle + "Couldn't load leaderboard." + Retry button. Identical.
- `.loading`: ProgressView large, minHeight 120. Identical.
- elapsed/score time formatting: identical `%d:%02d`.

### App-specific (divergent)
- **Outcome**: Sudoku is solve-only (hero always success "Solved!"). MS has win/loss (`burst.fill` + "Boom" + error tint + different a11y label). → inject as an *outcome* value.
- **State enum**: Sudoku has `.noLeaderboard` (#383, Practice not-ranked, neutral copy, NO CTA). MS lacks it. Per spec, give MS the shared one.
- **`.unauthenticated` CTA**: Sudoku renders a "Sign in" button (calls viewLeaderboardTapped). MS renders copy only, no button. → inject the auth-CTA action as optional closure.
- **Action buttons**: Sudoku has only "View full leaderboard" (bordered) in `.loaded`. MS has a 3-button action stack (View leaderboard / Retry / New Game) shown in ALL states. → inject an action list / closures.
- **Leaderboard CTA label**: Sudoku "View full leaderboard"; MS "View leaderboard". → inject label.
- **Reminder primer affordance + sheet**: Sudoku-only (#287). Stays in SudokuUI wrapper; NOT moved to shared body.
- **Presentation**: Sudoku = pushed `.completion` AppRoute (RouteFactory). MS = inline full-cover `.overlay` on board (#388). Both KEPT app-owned per spec.
- **Slice fetch params**: Sudoku top-3 global; MS local-player-centred limit 5. Lives in each VM, not the body.

### Coupling finding (load-bearing)
- `LeaderboardSlice/Entry/PlayerSummary` live in **GameCenterClient**. GameShellUI does NOT (and must NOT) depend on GameCenterClient — keeps GC/monetization out of the shell. → shared body must take a **plain value-type row model defined in GameShellUI**, not `LeaderboardSlice`. App wrappers map slice → shared rows.

### Localization finding (no regression, no new keys)
- Catalogs are app-level: `App/{Sudoku,Minesweeper}/Resources/Localizable.xcstrings`. `Text` literals in SwiftPM views resolve against `Bundle.main` (the app), since packages declare no resources/defaultLocalization.
- Sudoku catalog HAS all completion strings (7 locales). **MS catalog has only 9 keys — none of the completion strings**; MS completion UI is currently English-literal-fallback only. This is PRE-EXISTING.
- Moving literals into GameShellUI keeps the same `Bundle.main` resolution → Sudoku stays translated, MS stays literal-English (unchanged). I will NOT edit catalogs → scan:l10n stays green, 0 `<TRANSLATE>`.

## 設計決定 (Design decisions)

- **Keep both public app views (`CompletionView`, `MinesweeperCompletionView`) as thin wrappers** that build a shared `CompletionScreen` from GameShellUI. Rationale: snapshot tests + RouteFactory + BoardView all instantiate the public app views by name; keeping them preserves call sites AND keeps the rendered tree identical → snapshots byte-identical (goal: zero re-records).
- **Shared body API = pure config struct + injected closures + shared state enum**. No GameCenterClient import in GameShellUI.

## 偏離 (Deviations)
- **Byte-identity slots vs single `actions` slot** — Sudoku's "View full leaderboard" CTA sits ADJACENT to the leaderboard section (inside the `.loaded` group, no 24pt gap), while MS's action stack is a separate VStack(spacing:24) child shown in ALL states. A single shared `actions` slot would have inserted a 24pt gap for Sudoku → snapshot drift. Added a second injected slot `loadedAccessory` (rendered inside the `.loaded` case after the section) so each app reproduces its exact prior layout. MS leaves it empty; Sudoku leaves `actions` empty.
- **MS `.unauthenticated` had no "Sign in" button; Sudoku does** — made the sign-in CTA an optional `onSignIn` closure (nil → copy only). Preserves both surfaces exactly.
- **No GameShellKit snapshot dependency added** — spec said "snapshot the shared body across states". GameShellKit has no swift-snapshot-testing dep and no snapshot infra. Rather than pull a new test dependency + new baseline PNGs into the shell package (against Simplicity-First), the shared body is pixel-verified through the two apps' EXISTING snapshot suites (which render every state via the real wrappers and stayed byte-identical). Added a dependency-free `CompletionScreenTests` (instantiation/genericity sentinel across all states + both outcomes), mirroring the sibling `*GenericityTests` pattern already in GameShellUITests. Flag for Leader if a dedicated GameShellKit snapshot baseline is required.

## Snapshot impact
- ZERO re-records. All existing baselines pass byte-identical:
  - Sudoku CompletionViewTests: loaded / unauthenticated-zhTW / noLeaderboard / failed (4/4).
  - MS MinesweeperCompletionSnapshotTests: win-loaded / loss / loading / failed × light+dark incl. #409 dark (8/8).
  - MS MinesweeperBoardTerminalOverlaySnapshotTests: light+dark (2/2).

## 折衷 (Tradeoffs)
- **Shared state enum vs per-app enum**: chose ONE shared `CompletionScreenState` in GameShellUI carrying shared `CompletionLeaderboardRow` values, with all states both apps need (loading/loaded/unauthenticated/noLeaderboard/failed). App VMs keep their own state enums (their fetch contracts differ) and MAP to the shared one at render. Rejected unifying the VMs — out of scope, riskier, would churn VM tests.

## 未決 (Open questions)
- (none load-bearing yet)
