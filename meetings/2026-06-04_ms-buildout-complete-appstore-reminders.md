# 2026-06-04 — MS build-out complete · App Store readiness · RemindersKit · status dashboard

Continuation session. Headline: the **Minesweeper mirror-Sudoku build-out epic (#293) shipped end-to-end (6/6)**, the App Store submission-readiness effort was structured + advanced, the first approved feature (RemindersKit) got its foundation, and a living HTML status dashboard was introduced. Leader + dispatched Developer / Designer / Code-Reviewer subagents, worktree-isolated, each merged through the review triad.

---

## Phase A — Minesweeper mirror-Sudoku build-out (epic #293) — COMPLETE 6/6

Drove the epic to completion, one feature at a time (serial — all touch overlapping MS files), each Developer → CR (+ Designer for visual surfaces) → merge.

| Piece | PR | Notes |
|-------|----|------|
| Theme system #278 T1 | #294/#295/#296 | Theme protocol+tokens+env → GameShellUI (Sudoku byte-identical, neutral default); Sudoku `cell` split to `\.sudokuCell`; `MinesweeperTheme` (slate-blue, verbatim from prototype) applied to board. Designer Aligned + CR APPROVE. **Fixed the "ugly/flat" root cause.** |
| Home + reachable hubs #288/#289 | #302 | `MinesweeperHomeView` mode-card entry; Daily/Practice now navigable; `.newGame`-as-route redesign (Home is root, NewGameView untouched); Leaderboard card disabled-stub until #291. |
| Daily model #290 | #307 | Date-seeded trio, deterministic per UTC-day (faithful Sudoku `dailySeed`/`StableHash` mirror; `UTCDay` byte-mirrored, not imported — shared TimeKit extraction → #305). |
| Leaderboard / Game Center #291 | #312 | GC client wired; submit-best-time-on-win (latched, non-blocking); GC dashboard modal (#49 side-effect, not a route); Home card enabled. Added a game-agnostic `submitScore(leaderboardId:elapsedSeconds:)` to shared GameCenterKit — Sudoku's typed method delegates to it, behavior-identical. ASC leaderboard-ID registration = user-owned. |
| Completion screen #292 | #314 | Themed Completion overlay (result hero + best-time + leaderboard slice + CTAs) replacing the plain `terminalOverlay`. Extracted `MinesweeperCellButton`/`InteractionMode` (verbatim, under 400-line lint). reveal-all-mines-on-loss deferred to #298. |
| Game-view polish + Mac side-rail #298 | #316 + `55f4dc2` | Mac side-rail (centered board + 260pt rail, mirror Sudoku macLayout); reveal-all-mines-on-loss (no engine change — snapshot exposes `cell.isMine`); VoiceOver row/col + flag action; `.task(id:)` ticker replacing the TimelineView 1Hz hack; mine glyph `xmark.octagon.fill`. Designer Aligned + CR APPROVE. |

### The bevel finale (Leader-local)
The 2 deferred #298 cosmetics (covered-cell contrast/bevel + the public→internal import) were blocked for the subagent only because **the agent sandbox couldn't `rm` the stale snapshot PNG + run record-mode** — but the Leader can. Implemented a conservative raised-tile treatment (token-derived top highlight + thin edge), deleted the 2 covered-board baselines, ran record-mode, and **Read the regenerated PNG to verify visually** (raised/tappable, more depth — the flat-cell gap is closed). Compact `VStack(spacing:12)` intentionally kept (layout constant; migrating churns the baseline for no visual gain).

MS now mirrors Sudoku across every surface except minesweeper gameplay, themed in slate-blue. Tails tracked: snapshot coverage #303/#308/#315, launch-time GC auth #313, clear-cache #284.

---

## Phase B — App Store submission readiness (#236 umbrella, reopened)

#236 was closed (review-notes scope done) then **reopened as the submission-readiness umbrella** when the user clarified the broader intent. Children:
- **#304** (earlier) — review notes both apps + MS metadata listings (7 locales) + ASC metadata-API plan.
- **#309** ✅ — completed the ASC metadata field set: per-app `app-meta.yaml` (copyright "2026 Wei18" from LICENSE, Games > Puzzle/Board categories + sub-categories, structured `review_information`). Cross-checked against a real Fastlane `deliver` structure (the gap was the global fields; per-locale was complete). User decisions: review name = git user.name "Wei18"; **email = the GitHub noreply, FLAGGED — noreply does NOT receive mail, must be swapped for a monitored inbox before submission**; phone = secret (null in doc, injected from secrets/ at apply). Fixed a pre-existing YAML parse bug in `iap/remove-ads.yaml`.
- **#310** (in progress) — `ASCRegister metadata` subcommand (Yams reader + MetadataConfig + ASCClient+Metadata + Reconciler), runs read-only `plan` against Sudoku's ASC app to resolve the Unconfirmed prereqs; `apply` user-owned.
- **#311** — screenshots sourced from snapshot-test PNGs (symlink into submission dir) — user's idea; depends on snapshot coverage.
- **#306** — Sudoku v2.5 whats_new refresh. **#132** — TestFlight + submit (user-owned).

Key insight (user): #310 only needs the schema, not finalized content — so it didn't have to wait for #309's values.

---

## Phase C — Approved-proposal features (post-build-out)

- **RemindersKit #287** — foundation shipped (#318): new leaf package, value types + the two protocol seams + Live (UNUserNotificationCenter, confined to Live files) + Noop/Fake + 12 tests. CR APPROVE-WITH-NITS. Non-Sendable `UNUserNotificationCenter` handled by fetching `.current()` per-call (computed property, never stored) → legitimately Sendable, no `@unchecked`. Platform floor **iOS 26/macOS 26** (user pick, sibling consistency). Phase 2 = primer UI (GameShellUI) + Sudoku U1 wiring + telemetry seam → a **usage-flow visual** was commissioned to drive that design. Follow-up #319 (Live trigger-type test).
- **CaptureGuardKit #286** — research doc: the black-on-capture `isSecureTextEntry` secure-layer trick is **viable in 2026** (iOS 26.2 via ScreenShieldKit; `_UITextLayoutCanvasView` stable since iOS 15) but private/fragile/Simulator-incapable/second-camera-bypassable/App-Store-unblessed → ship behind a kill-switch + graceful no-op + telemetry. Netflix's effect = FairPlay media-only (N/A to UI). Provided a real-device P4 spike checklist (Unconfirmed → Resolved-conditional).

---

## Phase D — Living HTML status dashboard (process change)

Introduced `docs/status/build-status.html` — a single self-contained dashboard the Leader regenerates at each milestone, opened with `open`, versioned in git (history = timeline). Iterated per feedback: it must carry the **narrative** (CR verdicts + the specific nit + decisions + follow-up routing), not just issue titles; and the content is **zh-Hant** (refs/code/proper-nouns kept verbatim). Codified in memory [[feedback-html-status-dashboard]].

---

## Cross-cutting decisions / memory
- Leader-local snapshot re-record is the unblock for "agent sandbox can't `rm`/record" deferrals — implement + re-record + Read the PNG to verify.
- App Store review-contact email cannot be a GitHub noreply (it doesn't receive mail) — flagged for swap before submission.
- Post-each-merge: `git pull` + the dashboard regen; periodic main sweep (GameShell 8 / SudokuKit 167 / MinesweeperKit 71 / MinesweeperCoreKit 75 — all green).
