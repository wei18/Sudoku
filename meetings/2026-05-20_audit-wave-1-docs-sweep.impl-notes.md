# Impl Notes — audit-wave-1-docs-sweep (2026-05-20)

Branch: `docs/audit-wave-1-sweep`. Docs-only sweep — no Swift / no VCS.

Status: COMPLETE

Scope: 7 audit findings (B5 / B6 / B7 / M2 / M3 / M7 / M8). Leader handles git / PR.

---

## §設計決定 (Design decisions)

### B5 — `docs/setup.md` clone URL
Replaced `Sudoku.git` → `Sudoku-spec.git` and `cd Sudoku` → `cd Sudoku-spec` to reflect the 2026-05-17 single-repo collapse (README.md L8). Single-line surgical fix.

### B6 — `docs/design.md §How.3.3` protocol drift (BLOCKER)
Mirrored the actual `Packages/SudokuKit/Sources/GameCenterClient/GameCenterClient.swift` protocol into §How.3.3, rather than re-designing. The doc was lagging behind ~3 iterations of refactors:

- `authenticate()` is now `async throws -> GameCenterAuthState` (live impl can surface real GameKit errors). The old `nonisolated var currentAuthState` and `failed(GameCenterError)` variant were removed.
- `submitScore` now takes `(puzzleId:, elapsedSeconds:, difficulty:, leaderboardKind:)` — leaderboard ID assembly stays inside `LeaderboardIDs` rather than leaking to callers (per source-file header comment).
- `reportAchievement` takes the full `AchievementProgress` value (rolled `achievementId` + `percentComplete` into one Sendable struct; dropped `showsCompletionBanner` — banner display is the live impl's call).
- `fetchLeaderboardSlice` now takes `(leaderboardId:, scope:, around player: String?, limit:)`. Renamed `topCount` → `limit`, added `around player` (replacing the implicit `aroundPlayer` scope case).
- `LeaderboardScope` cases renamed to `globalAllTime / globalToday / friendsAllTime`; `aroundPlayer` was folded into the `around player:` parameter on `fetchLeaderboardSlice`.
- `LeaderboardEntry` `formattedScore` is `mm:ss.SS` (centisecond) per PR #17 / #41; `rawScore` is removed in favor of `score: Int` (elapsed seconds — lower=better). The Sink does `seconds × 100` → Int64 centisecond at submit time, matching §How.3.1 L267.
- `PlayerSummary.teamPlayerId` replaces `Player.gamePlayerID` — naming purges GameKit terminology from the public surface.
- Added `friendsAuthorizationStatus()` / `requestFriendsAuthorization()` returning `FriendsAuthStatus` (the latter now returns the post-prompt status instead of throwing on grant).
- `GameCenterError` cases updated to actual source: dropped `authenticationCancelled / authenticationFailed / scoreOutOfRange / networkUnavailable / rateLimited`; added `cancelled / scoreSubmitFailed(reason:) / achievementReportFailed(reason:)`. `underlying` gained a `domain:` field.

PR trail cited in §How.3.3 opener: PR #30 (ms→centisecond conversion), PR #25 (recurrenceDuration PT24H), PR #17 (`mm:ss.SS` formatter).

### B7 — §How.3.1 vs §How.3.3 contradiction
The Sink pseudocode in §How.3.3 still wrote `elapsedMilliseconds: Int64(seconds * 1000)` while §How.3.1 had been migrated to centisecond / `mm:ss.SS` / 7200s cap per PR #25 + #41. §How.3.3 is now the dependent side: Sink calls `submitScore(elapsedSeconds:)` and the live impl does the `× 100` Int64 centisecond conversion internally (matching the live impl per its source). No magic numbers in the Sink pseudocode anymore.

### M2 — §Decisions empty placeholder
Picked 14 decisions that affect future contributors, each cited to a meeting log + PR/issue where possible. Skipped purely cosmetic / one-off churn (snapshot count bumps, isolated typo fixes). Each entry is one line; no narrative.

### M3 — §How.5.2 AppRoute drift
Mirrored the actual `Packages/SudokuKit/Sources/SudokuUI/Navigation/AppRoute.swift` enum (7 cases: `home / daily / practice / board(puzzleId:) / completion(puzzleId:, elapsedSeconds:) / leaderboard(leaderboardId:) / settings`). Note that `daily` and `practice` carry **no parameters** despite the original spec showing `daily(date:)` / `practice(difficulty:)` — keeping live source as canonical.

Added a footnote about issue #49 potentially removing `.leaderboard` (native GameCenter UI switch in flight via separate subagent). Did not preempt the removal — the case stays.

### M7 — methodology.md skill matrix
Added 6 new rows + promoted 3 prose-mentioned skills to matrix rows. Placed under existing groups where natural (`agent-impl-notes-log` is already a matrix row at L96; added owner/trigger for the others; collaboration skills went under a new "協作 / Review / Spec orchestration" sub-group within 實作階段).

### M8 — feature-tour.md test count + plan.md repo refs
- `feature-tour.md` L70: `336+` → `364`.
- `plan.md` L7: removed "originally framed as a sibling `Sudoku/` repo; collapsed into the spec repo per 2026-05-17 decision" parenthetical (now redundant noise — single-repo is the only truth).
- `plan.md` L90: `pointer to Sudoku-spec/` → `project root README`.
- `plan.md` L766: `GitHub Pages from Sudoku-spec/` → `GitHub Pages from this repo`.
- `plan.md` L798: `Sudoku-spec/meetings/...` and parenthetical `(spec repo, not impl repo)` collapsed to just `meetings/{YYYY-MM-DD}_{topic}.md`.

---

## §偏離 (Deviations)

None — every change is a documentation correction to match either (a) actual source files in this repo or (b) prior decisions captured in meeting logs.

---

## §折衷 (Tradeoffs)

- §Decisions is now ~14 lines instead of a "comprehensive" list. Risk: future contributors may look for a decision that's not there. Mitigation: each entry cites a meeting log so the trail is reconstructible; the §Decisions section is for "decisions that affect future contributors", not a changelog.
- §How.3.3 doc now mirrors source verbatim (minus body comments). Risk: doc drifts again when source changes. Mitigation: §How.3.3 header explicitly says it mirrors the actual protocol shape, with the PR trail. A future audit can grep the protocol against the doc.
- §How.5.2 footnote about issue #49 is deliberately soft (`§Backlog tracks`) so the doc is not invalidated whichever way #49 lands.

---

## §未決 (Open questions — Leader-resolvable)

None blocking. Three items the Leader may want to look at after merge:

1. **§How.3.5 朋友圈排名 also drifted from the new LeaderboardScope** — the prose still uses `.globalTop` / `.aroundPlayer` / `.friendsOnly` (old scope names) and references `GKLeaderboard.loadEntries(for: .global / .friendsOnly)` calls. The actual `LeaderboardScope` enum now only has `globalAllTime / globalToday / friendsAllTime`, with the "我的鄰近" window expressed via `fetchLeaderboardSlice(around player:)`. §How.5.1 L707-708 table also references old scope names. Not in the 7-finding audit list; surfacing for Leader to decide whether to roll into Wave 1 or queue Wave 2.
2. The §Decisions list could be expanded to 20+ entries if Leader prefers more granularity (e.g. include each phase's gate decisions). Current 14 was chosen as the "affect future contributors" subset.
3. `plan.md §Appendix A` `Meeting logs` row is now `meetings/{YYYY-MM-DD}_{topic}.md`. If Leader wants to add a note about `.impl-notes.md` variant (per `agent-impl-notes-log` skill), that's a separate enhancement.

---

## §驗證 (Verification)

Per-file delta:

| File | Lines changed (approx) |
|---|---|
| `docs/setup.md` | +1 / -1 (B5) |
| `docs/design.md` | +~80 / -~85 (B6 §How.3.3 rewrite + B7 sink + M2 §Decisions populate + M3 §How.5.2 AppRoute rewrite) |
| `docs/methodology.md` | +~10 / -0 (M7 skill matrix rows) |
| `docs/plan.md` | +4 / -4 (M8 repo refs) |
| `docs/feature-tour.md` | +1 / -1 (M8 test count) |

§Decisions entries: 14
Skill matrix entries added: 9 (6 new + 3 promoted)

No code touched, no source files modified, no git commands run.
