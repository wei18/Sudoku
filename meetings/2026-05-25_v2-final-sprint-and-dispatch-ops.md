# 2026-05-25 — v2 Final Sprint + Dispatch-Ops Crisis & Resolution

> Session span: 2026-05-25 12:30 GMT+8 → 2026-05-26 00:00+ GMT+8
> Branch: main throughout
> Final main: `ed9a0c8` (+ AdMob wiring still in flight)

## §1. Outcome — what shipped

12 PRs merged into main this session (PRs #129–#141, skipping #131/#140 issues):

| PR | Topic | Notes |
|---|---|---|
| #129 | M5 typed Mode enum (closes #65) | landed before this session via prior dispatch; merged early today |
| #130 | docs(v2) plan rewrite — reflect shipped reality | DRAFT → IN-PROGRESS; status table + per-step PR refs |
| #133 | docs(v2.5) pre-flight checklist tick (issue #132) | All 4 pre-flight items user-completed; AdMob production IDs noted inline |
| #134 | docs(rca) swift-test hang + lefthook deadlock RCA | reconstructed after Leader accidentally `git clean -fd`'d the original |
| #135 | fix(monetization) Fix B — split bootstrap() (RCA H1) | MonetizationStateController leaking `Task { for await ... }` per test instance |
| #136 | fix(lefthook) serialize pre-commit (RCA H4) | `parallel: true → false`; `mise exec swiftlint` + `gitleaks` deadlock resolved |
| #137 | docs(methodology) sub-agent dispatch ops manual | §派發契約 §9–12 + 3 patterns + 4 anti-patterns from this session |
| #138 | feat(error-funnel) UserFacingError + ErrorReporter (closes #67) | Code Reviewer APPROVE-WITH-NITS; S-1/S-2/S-4 inline-applied |
| #139 | feat(settings) Option A polish + AdsRemovedRow | User-driven UX redesign; Designer ↔ RD flow worked |
| #141 | feat: wire-or-delete dead Persistence + GameCenter infra (closes #64) | Round 1 REJECT (B-1 gateway translation missing) → Round 2 APPROVE-WITH-NITS |
| (#3 task) | feat(admob) banner wiring v2.5.2 | In flight at session end — 3 commits on subagent worktree, awaiting verification |

Also opened (not yet merged):
- Issue #140 — around-player range centring follow-up (carved off #64 N-1)
- Issue #132 — v2.5 user-owned ops tracking (pre-flight done; sandbox + AdMob test + submit pending user)

## §2. The dispatch-ops crisis

Mid-session, two interrelated infrastructure bugs surfaced simultaneously, exposing brittleness in the Leader↔subagent contract:

### 2.1 swift-test full-suite deadlock (RCA H1)

`MonetizationStateController.bootstrap()` unconditionally spawned a `Task { for await event in iapClient.purchaseUpdates() }` whose lifetime ran until `deinit`. swift-testing keeps suite instances alive for the full run; `FakeIAPClient.finishUpdates()` was called by zero tests. 19 leaked `@MainActor` tasks deadlocked against 17 `@MainActor` snapshot suites.

Symptom: `swift test` (no `--filter`) hung 18–68+ min, required `kill -9`.

**Fix B (PR #135)**: split `bootstrap()` (one-shot reads) from new `startListeningForLifetimeOfApp()` (the lifecycle subscription); tests that exercise updates teardown via `defer { Task { await iap.finishUpdates() } }`.

### 2.2 lefthook pre-commit deadlock (RCA H4)

`lefthook.yml` had `pre-commit.parallel: true`. Concurrent `mise exec swiftlint` + `mise exec gitleaks` deadlocked on mise's process-level cache lock.

Symptom: `git commit` froze at 0:00.02s CPU indefinitely; subagent sandbox could not `kill` to recover.

**Fix (PR #136)**: `parallel: false`. Lefthook now runs gitleaks → hygiene → swiftlint sequentially in ~1s total. Empirically validated by every commit after #136 landed.

### 2.3 Subagent sandbox limit discoveries

Across multiple aborted dispatches, the following sandbox restrictions emerged. None are documented by the harness — they had to be discovered the hard way:

| Operation | Allowed for Leader | Allowed for subagent |
|---|---|---|
| `cd` into other worktree | ✓ | ✗ |
| `git -C <other-worktree> ...` | ✓ | ✗ |
| `git rebase main` (cross-branch) | ✓ | ✗ |
| `git merge main` (cross-branch) | ✓ | ✗ |
| `kill` / `pkill` | ✓ | ✗ |
| `mise trust <path>` | ✓ | ✗ |
| push to origin | ✓ | (allowed, but Leader-only by convention) |

Implication: **Leader pre-flight is mandatory before every subagent dispatch.** Items 11/12 of methodology §派發契約 (PR #137) codify this.

### 2.4 Worktree wipe before commit

`isolation: "worktree"` auto-cleans worktrees with no commits. Subagents that batch all edits then run verification before committing risk losing all work if the verification hangs/crashes/times out.

Lost-work events this session:
1. RCA doc (Leader's own `git clean -fd` mishap during cleanup)
2. Fix B first attempt — subagent fully validated (full `swift test` exit 0!) but never committed; worktree wiped
3. #64 Phase 2 third attempt — subagent had 11 dirty files + 7 passing wiring tests; commit hung on lefthook H4; worktree wiped

**Discipline (PR #137 §派發契約 §10)**: commit early & often, including protective `--no-verify` WIP commits during work.

## §3. Patterns codified into methodology.md

PR #137 added 3 new patterns + 4 new anti-patterns + 4 new §派發契約 items, all sourced from this session's incidents.

### Patterns
- Leader pre-flight before each dispatch
- Scope-split heavy refactors into 3–5 file batches
- Adversarial pre-mortem before dispatch

### Anti-patterns
- Leader takes over Developer work when subagent struggles
- lefthook `parallel: true` causing mise deadlock (RCA H4)
- `swift test` full-suite as first verification command (RCA H1)
- Worktree wipe before commit causes lost work

### §派發契約 additions (items 9–12)
9. Environment prerequisite by Leader (mise trust / rebase / kill orphans)
10. Commit-early discipline (protective `--no-verify` WIP OK; final must pass hooks)
11. Subagent sandbox limit reference list
12. swift test default command (`--filter` required; full suite only with `timeout 600` wrap)

## §4. UX redesign sub-flow worked

User reported dissatisfaction with `SettingsView` IAP rows ("About 裡面的 margin 沒對齊, 整體不協調"). Flow exercised:

1. **Leader** — current-state audit, problem framing
2. **UI Designer subagent** — full audit + Option A (surgical) + Option B (hero card) proposal
3. **User feedback request** — asked for visual mockup
4. **UI Designer second dispatch** — HTML iPhone-frame side-by-side mockup (BEFORE / Option A / Option B × purchased + unpurchased)
5. **User decision** — Option A + Designer's recommended receipt strip
6. **Senior Developer subagent** — 40 LOC impl + snapshot baseline regen
7. **Merge as PR #139** — no Code Reviewer needed (under threshold + not in mandatory CR module list)

End-to-end ~2 hrs, but most of that was waiting on subagent runtime. No iteration cycles needed.

## §5. Code Reviewer round-trip on #64

#64 round 1 verdict: **REJECT** with 2 blockers + 3 must-address nits.

| Finding | Resolution |
|---|---|
| B-1 `LivePrivateCKGateway.save` missing `CKError.serverRecordChanged → .syncConflict` translation | Added via `Self.translate(error, recordName:)` helper + `LivePrivateCKGatewayTests` |
| B-2 stale `docs/v1/plan.md:400+434` references to deleted files | Strikethrough + HTML-comment deferral banner |
| N-1 `around: player` Phase 10 deferral (correctness gap masked as verification) | Tracked TODO ref → issue #140 |
| N-2 §How.6.7 callout overstates live wiring | Tightened to reflect post-B-1 reality |
| N-3 missing merge-correctness wiring test | Added `savedGameMergePicksResolverOutputOnResubmit` |

Round 2 verdict: **APPROVE-WITH-NITS** (only the `TBD-around-player` → `#140` swap blocked merge; trivial Leader fix).

This validates the round-1-Reject / round-2-Approve cadence the subagent-review-cycles skill describes. Total cycle: ~4 hours including dispatch + 2 reviews + fix.

## §6. Decisions

- **D-2026-05-25-01**: For #64 wire-or-delete, Leader chose conservative scope (delete 3, wire 2) over Developer's proposed wire-4. Rationale: AccountMonitor + LocalCache require net-new ICloudAccountProvider+Keychain Live impls — feature-scope, not cleanup-scope. Deferred post-v2.5 in `design.md §How.6.5`.
- **D-2026-05-25-02**: `UserFacingError` + `ErrorReporter` placed in `Telemetry/` target (not `AppComposition/` per original spec). `Telemetry` is already transitive dep of all catch-site targets — no Package.swift dep-graph churn.
- **D-2026-05-25-03**: `MonetizationStateController.bootstrap()` and `startListeningForLifetimeOfApp()` are split; `AppComposition.live` calls listener eagerly at composition; Views continue calling `bootstrap()` from `.task` (preserves single-listener-per-app intent).
- **D-2026-05-25-04**: Settings page redesign Option A + purchased receipt strip (`✓ Ads Removed · Active`) — buyer sees proof of purchase; preserves page vertical rhythm.
- **D-2026-05-25-05**: AdMob `bannerAdUnitID` constant via `#if DEBUG` pivot (test ID in dev, production ID in release builds). Production ID swap deferred to v2.5.3 user step.

## §7. Open questions / handoffs

- **Task #3 AdMob wiring** still in flight at session end. Subagent has 3 commits on its worktree (Info.plist + LiveAdMobBridge real impl + impl-notes); full-suite verification pending. Next session: verify subagent return, push branch, dispatch Code Reviewer (mandatory — AdsAdMob target in CR module list), open PR, merge.
- **Issue #140 around-player range centring** filed but unscheduled. Code Reviewer flagged it as a real correctness gap, not verification debt.
- **Issue #132 v2.5.2/v2.5.3** still user-owned (TestFlight sandbox IAP test, AdMob real-device test, ASC review submit). Pre-flight done.
- **methodology §Backlog**: GitHub App (bot) identity transition — now unblocked (2 in-flight tasks done); user-side App creation is next user step.

## §8. Patterns observed but not (yet) codified

Worth watching across future sessions to confirm before promoting to §Patterns:

- **Code Reviewer round-1 REJECT → Leader inline-files follow-up issues**: when round-2 fixes everything except a "file an issue" item, Leader filing the issue + a one-line TODO ref swap is faster than a third subagent round. Hit twice in this session (#64 N-1, #67 S-2 deferred but not filed).
- **Designer proposes → user asks for visual → Designer HTML mockup → user decides**: two-stage Designer dispatch (proposal markdown → HTML mockup) worked smoothly. Previously Designer dispatched once with both deliverables would've been longer cold-start.
- **Subagent late completion notification**: multiple subagents this session returned with truncated terminal output (e.g., "OK — main is at..." or "test still building/early. I'll wait for the monitor notification.") that arrived hours after Leader had already moved on. Sometimes the work was still valid; sometimes the notification was just stale. Need a convention for "subagent reports late; trust its final commits, not its truncated prose."

## §9. Stats

- PRs merged: 10 (this session)
- Commits to main: 10 squashed merges + multiple subagent branches
- Subagent dispatches: ~15 (including retries after abort)
- Subagent aborts: ~7 (mostly sandbox limit hits before §派發契約 §9 codified)
- Tools added to memory: `feedback-leader-stays-coordinator`, `admob-production-ids` (project memory)
- Lines added to `docs/methodology.md`: 74 (PR #137)
- Process improvement: from "subagents keep aborting on infra issues" to "5-step Leader pre-flight then dispatch lands first try" within one session
