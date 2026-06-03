# 2026-06-03 (pm) — Prototypes, feature proposals, MS theme build-out

Continuation of the same 2026-06-03 session (earlier half logged in
`2026-06-03_followup-sweep-and-cr-audit.md`). This half: design prototypes,
two feature proposals, and the start of the Minesweeper mirror-Sudoku build-out
(theme system extraction). Leader + dispatched Developer / Designer / Code-Reviewer
subagents, worktree-isolated and verified per the review triad.

---

## Phase A — App-flow prototypes (docs/)

Goal: single-file HTML UI/UX flow prototypes (iPhone-frame canvas + SVG nav arrows
+ design-tokens panel) via the `ios-design-mockup` skill, one per app, derived from
the CURRENT shipped apps.

- **Round 1** (2d62dfb): `docs/designs/sudoku-app-flow.prototype.html` (11 screens,
  sage tokens from DefaultTheme, Leaderboard = GC modal #49) + `docs/minesweeper/
  minesweeper-app-flow.prototype.html` (honest theme-less current state). Two read-only
  alignment checkers confirmed both **Aligned** (no misrepresentation/code-gap).
- **User feedback**: (1) MS prototype "too ugly" — but that was *faithful*: MS genuinely
  lacks Home/Leaderboard, Daily/Practice hubs are unreachable, no theme. The prototype
  surfaced a real gap vs the mirror-Sudoku goal. (2) Expected Sudoku-style screens on MS.
  (3) No macOS frames shown.
- **Round 2** (5f89536): MS prototype **rewritten as the mirror-Sudoku TARGET** (Home/
  Daily/Practice/Leaderboard/Completion + shipped Board, iPhone + macOS, a PROPOSED
  slate-blue MS palette, clearly labeled TARGET-not-built vs shipped). Sudoku prototype
  **+ macOS frames** (M01-M03), then **completed Mac coverage** (M04 Daily / M05 Practice
  / M06 Completion) after the user noted the Mac flow was only 3/11.

### Decisions / discoveries
- MS "ugly" is an **app gap, not a Designer miss** — the prototype was honest.
- iPad ≈ macOS regular-size-class (shared NavigationSplitView layout) — labeled as such.
- Alignment checkers can verify HTML↔code in both directions without rendering.

---

## Phase B — Two feature proposals (PROPOSAL_APPROVED, parked)

Both produced as shared-target design proposals with prerequisite checklists (collaboration-mode
system-API rule), reviewed by Leader, approved by user, parked as backlog.

### CaptureGuardKit — anti-capture cheat-guard (#286, proposal committed)
- **Headline reality**: iOS cannot BLOCK screenshots (no FLAG_SECURE); macOS 15+
  `NSWindow.sharingType=.none` is dead vs ScreenCaptureKit → macOS is detect-only.
- **Approved scope**: (a) detect + telemetry now; seam for (c) mark-run-unranked.
  Then **user clarified they want Netflix-style "board goes black on capture"** — that's
  DRM/FairPlay protected-video (media-only, N/A to game UI); the game-applicable technique
  is the `isSecureTextEntry` secure-layer trick = proposal **option (d)**. So scope updated
  to **(a)+(d) behind a flag**, with (d) gated on the **P4 spike** (private layer, fragile,
  Simulator-fails, second-camera bypass, blanks legit screenshots, no macOS). P4 needs
  **device verification** (Simulator can't confirm).

### RemindersKit — local notification reminders (#287, proposal committed)
- **Approved**: shared target, **local** UNUserNotificationCenter (no APNs/server),
  **explicit soft-primer** permission (value-moment, not cold launch), ship **U1 Sudoku
  Daily-ready** first. All prereqs Verified except P12 (macOS Settings deep-link, non-blocking).
- **#195 rescoped to ATT-only** — its push/notification slice is subsumed here (and "push"
  was a misnomer; we use local).

---

## Phase C — MS mirror-Sudoku build-out inventory (#293 epic)

Per user ("inventory into features, then build"): filed #288 Home+Root mode-card entry,
#289 reachable Daily/Practice hubs, #290 MS Daily date-seeded model, #291 Leaderboard/GC,
#292 Completion screen; theme → #278 Tier-1. Design reference = the TARGET prototype.

---

## Phase D — Theme system extraction (#278 Tier-1) — STARTED

The most enabling MS build-out prerequisite (fixes the "ugly" root cause). Done in stages
to keep Sudoku byte-identical and reduce per-agent risk:

- **Phase 1 (#294)**: moved the `Theme` protocol + token types + `@Environment(\.theme)`
  from SudokuUI → GameShellUI. Key call: GameShellUI's env default is a palette-neutral
  `NeutralTheme` (no sage leaked); Sudoku injects `DefaultTheme` at `AppComposition.rootView`
  + `SnapshotConfig.hostingView`. CR APPROVE. Sudoku 167 tests byte-identical, no re-record.
- **Phase 2a (#295)**: pulled the Sudoku-specific `cell` bundle OUT of the now-generic base
  `Theme` into SudokuUI's `\.sudokuCell` env (base = surface/text/accent/status/difficulty/
  spacing). Sudoku byte-identical. (First Phase-2 attempt **stalled** on a 600s watchdog mid
  protocol-split → re-dispatched as the smaller 2a; clean.)
- **Phase 2b (in review)**: `MinesweeperTheme` (slate-blue palette verbatim from the prototype)
  + `MinesweeperCellTokens` + `\.minesweeperCell` + applied to `MinesweeperBoardView` (tokens
  only, Tier-0 layout intact) + **new MS snapshot harness** with 2 baselines (Beginner covered
  light+dark). Verification = Designer reads the snapshot PNGs vs prototype + CR reviews code.
  Open: revealed/number/mine states not snapshot-captured (in-body `.task{refresh()}` blocks
  deterministic capture — needs a production seam; deferred).

---

## Cross-cutting

- **Incident (recorded as memory)**: a "read-only" #150 CR ran `git checkout origin/<branch> -- .`
  then `git reset --hard` + `git clean -fd` in the SHARED main tree while two Designer agents
  were writing untracked prototype HTML there — `clean -fd` can wipe concurrent agents' output.
  main was unharmed (all merges are commits). Lesson → memory `feedback-readonly-reviewers-no-
  destructive-git`: reviewer prompts must forbid mutating git; never run a destructive-capable
  agent un-isolated alongside writers; verify a writer's reported file actually exists.
- **Session-limit hit** mid-batch: 3 agents aborted on their final report step, but their file
  outputs (atomic Write/Edit) had landed — verified each artifact complete before committing.
- **#150 merged (#285)**: LeaderboardLoader narrowed to honest `aroundLocalPlayer: Bool`.
- **Post-merge sweep** (main): GameShellKit 8 / SudokuKit 167 / MinesweeperKit 34 — all green
  after ~15 merges today.
