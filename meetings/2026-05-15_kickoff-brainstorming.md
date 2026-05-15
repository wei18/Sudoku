# 2026-05-15 — Kickoff Brainstorming → Spec Phase Complete

Session id: `ae54f5ea-6b89-4f59-9d9f-cafb8dff08f6`
Mode: AI Collaboration Mode (Leader / Developer + Code Reviewer subagents)
Duration: ~14 hours, single session covering kickoff → full spec → code review rounds → public-repo secrets → skill extraction → skill review.

## Goal

Anchor the direction for a Sudoku iOS + macOS App, decide which spec-phase artifacts to produce, drive design.md / foundations.md / methodology.md to a user-reviewable state, then extract reusable collaboration knowledge into project-local skills.

## Timeline (milestones)

1. Kickoff brainstorming — dual deliverable (playable App + Claude-agent collaboration record) established.
2. Foundations.md §1–§7 written (Leader-led, no subagent).
3. Document pipeline trimmed from 8 files → 5 files → finalised at 6 files (adds `foundations.md`).
4. design.md §What approved by user.
5. design.md §How.1–§How.7 drafted by Developer subagent, one round per section.
6. Code Reviewer round 1 → 7 BLOCKER / 11 MAJOR / 7 MINOR; user picked OS-floor option A; 24/25 issues ACCEPTed and applied.
7. Code Reviewer round 2 → 1 regression + 2 new findings, all fixed.
8. New requirement mid-session: public repo from day 1 → foundations.md §7 Secrets added.
9. Code Reviewer round 3 (scoped to §7) → resolved remaining open item.
10. Round 4 verification + parallel dispatch: 17 project-local skills extracted, translated to English, README added, then reviewed.
11. Skill code review → 1 BLOCKER + 8 MAJOR + 2 MINOR; 10 fixes applied and independently verified.

## Decisions

### Product (design.md §What)

1. Dual deliverable: a playable Sudoku App AND a documented Claude-agent collaboration case study are both first-class.
2. Platforms: iPhone (iOS) + Mac (macOS). iPad / Watch / visionOS deferred.
3. v1 features: notes, undo/redo, error hints, save state, personal records, Game Center achievements + leaderboards.
4. Game modes: Daily Mode (3 puzzles/day, recurring daily leaderboard, UTC reset, same `puzzleId` not double-scored) + Practice Mode (Starter Pack 90 + retired Dailies auto-recycled).
5. Localization: 7 locales via AI translation flow; zh-TW + en as MVP.
6. Monetization: free, no IAP.

### Architecture & infrastructure (foundations.md + design.md §How)

7. Swift 6 language mode with complete concurrency from day 1.
8. Single SwiftPM package, thin App target, 7 production targets, DI composition root.
9. swift-testing + pointfreeco/swift-snapshot-testing; no XCTest.
10. CI: Xcode Cloud single-track only; GitHub Actions parked in backlog.
11. Logging: `os.Logger`, subsystem = bundle id, category = module name, default `.private` with explicit `.public` opt-in.
12. Analytics: Apple three-piece (ASC Analytics + MetricKit + Game Center). No third-party tracking SDK. `NoOpTrackingSink` reserved.
13. Plan format: Superpowers `writing-plans` style.
14. OS floor lifted to iOS 26 / macOS 26 (Liquid Glass adoption); recorded as deliberate deviation from the iOS 18 / macOS 15 default skill.
15. CloudKit schema: Public DB `Puzzle` + `PuzzleDeliveryLedger`; Private DB custom zone `com.wei18.sudoku.userZone` with `SavedGame` + `PersonalRecord` (mode × difficulty = 6 rows); `CKDatabaseSubscription` for change notifications.
16. Puzzle delivery: Xcode Cloud monthly schedule; `operationType=create` + RECORD_EXISTS verify-then-skip; ledger stored in CloudKit (no `consumed.json` git commit, no GitHub PAT).
17. Solver/calibrator descope: v1 only nakedSingle + hiddenSingle + nakedPair + DFS uniqueness; technique-tier solvers (xWing / swordfish / xyWing) pushed to v2; difficulty driven by human-curated labels.
18. Game Center: 3 recurring daily leaderboards; 8 achievements totalling 550 points (reserving 450 for v2); `GameCenterClient` protocol with friends authorization, async auth state, sandbox/production split; cross-midnight completion skips submission (Apple `submitScore` always targets active occurrence); score > 2h treated as abandon.
19. View layer: 8 Views with NavigationStack/SplitView swap; `GameSession.Status` state machine; `@Observable` + `@MainActor` view models; debounce token lives in VM; `Localizable.xcstrings`; A11y baseline; 18 v1 snapshots.
20. Error handling: 6 error types, per-source matrix, offline availability table, 3 iCloud account states, per-field LWW for sync conflicts, 4 UI presentation patterns.
21. Mac keyboard: `.focusable()` + `@FocusState` + `.onKeyPress(phases: .down)` + `.keyboardShortcut` on Menu commands.
22. iCloud account change signal: `CKAccountChanged` + `CKContainer.fetchUserRecordID(...)` (not `NSUbiquityIdentityDidChange`).
23. PersonalRecord race handling: `.ifServerRecordUnchanged` policy with server-tag retry; deterministic recordName with create→update auto-fallback.
24. ViewModel lifecycle: `pause()` / `abandon()` async; scenePhase `.background` pauses, `.active` does NOT auto-resume — show "Tap to resume".
25. Test pyramid: 7 production targets × 6 fields; cross-cutting Clock/UUID/RNG injection; `SudokuKitTesting` shared fake target; `.serialized` trait for shared-fake tests; v1 not-doing list explicit.

### Process & collaboration (methodology.md)

26. Main agent = PM + Lead (no implementation code). Subagent roster: Developer / Designer / Code Reviewer with skill assignments per role.
27. Handoff contract: scope + reading list + skill list + return format + verification criteria — five mandatory elements.
28. Subagent dispatch budget: up to 10 rounds per section, but treat as upper bound; round-1 cosmetic fixes applied inline by Leader rather than consuming a round (all §How.3–§How.7 sections accepted in 1 round).
29. Document pipeline (6 files): `README.md`, `docs/design.md` (spec+RFC merged), `docs/foundations.md`, `docs/plan.md` (TDD checklist), `docs/methodology.md` (living), `meetings/{date}_{topic}.md`.
30. No implementation code before design + plan approved; implementation phase uses TDD.
31. Primary doc language: zh-TW.

### Public-repo & secrets (foundations.md §7, new)

32. Public from day 1 — no "private first, open later" fallback.
33. Secret classes catalogued: CloudKit PEM, ASC API Key, signing certs, provisioning profiles, player-identifying data.
34. Defence in depth: `.gitignore` baseline → mise-managed `lefthook` + `gitleaks` pre-commit → Xcode Cloud PR CI gitleaks → GitHub Secret Scanning Alerts.
35. Leak SOP: rotate-first → `git filter-repo` → notify GitHub support → incident log; accept that forks persist.
36. `.env.example` + `docs/setup.md` provide onboarding template.
37. Privacy commitments: no PII collection, no third-party SDK, no first-party server; MetricKit / Game Center / sysdiagnose Apple-upstream telemetry disclosed in PrivacyInfo.

### Skill extraction (`.claude/skills/`)

38. Extract 17 reusable patterns from foundations.md / methodology.md / observed collaboration moves into project-local skills.
39. SKILL bodies translated to English; `name` frontmatter preserved; `description` kept multilingual (English + zh-TW trigger phrases) so Chinese prompts still match.
40. Chinese README added at skills directory root.
41. Skill review applied 10 fixes: schedule-granularity caveat on Xcode Cloud, swift6 strict concurrency wording, telemetry facade single-package boundary, methodology pattern-extractor threshold clarifications, etc. (1 MINOR skipped: ai-translated-localization wording — low value.)

## Rejected alternatives

- Implementation milestone slicing A/B/C (vertical slices / infra-first / dual-track) — out of scope; this was still spec phase.
- Methodology folded implicitly into spec/RFC/plan — user explicitly wanted a standalone living doc.
- 8-file document structure (separate spec, rfc, plan, tasks, methodology, adr, README, meetings) — over-structured for solo v1; merged spec+rfc into design.md, tasks into plan.md checkboxes, ADR deferred until actually needed.
- Random puzzle pool with "filter already completed" model — replaced by Daily 3 + Practice recycling.
- All-time and per-puzzle leaderboards as separate ladders — replaced by 3 recurring daily leaderboards.
- TelemetryDeck / Firebase tracking — Apple three-piece only; tracking SDK is `NoOpTrackingSink`.
- GitHub Actions + Xcode Cloud dual-track CI — single-track Xcode Cloud for v1.
- `consumed.json` committed to git for puzzle delivery dedupe — replaced by CloudKit `PuzzleDeliveryLedger`.
- Technique-tier solver in v1 — descoped to v2; v1 uses curated labels.
- `NSUbiquityIdentityDidChange` as iCloud account change signal — wrong primitive (iCloud Drive identity); switched to `CKAccountChanged`.
- scenePhase `.active` auto-resume — replaced by explicit "Tap to resume" to avoid surprise timer drift.
- 9-technique test surface in §How.7.1 — regression from descope; rewritten as 3-layer propagation + verifier boundary tests.
- `GameCenterSink` daily-only short-circuit — was blocking Practice achievements; achievement evaluation always runs, only `submitScore` is daily-gated.

## Hand-offs

- Developer subagent rounds for design.md §How.3–§How.7 (one round each, all ACCEPTed with Leader-applied cosmetic edits).
- Code Reviewer subagent rounds 1–4 on foundations.md + design.md (CLI disabled, WebSearch allowed).
- Subagent for foundations.md §7 Secrets draft, then Code Reviewer round 3 scoped to §7.
- Three parallel subagents at session tail:
  - Task 1: edit foundations.md OS-floor references (7 sites).
  - Task 2: extract 17 project-local skills from session learnings.
  - Task 3: produce this meeting log (current task).
- Skill translation subagent (zh-TW → English bodies, preserve multilingual descriptions).
- Code Reviewer subagent on the 17 skills (found 1 BLOCKER / 8 MAJOR / 2 MINOR).
- Skill fix-application subagent (10 fixes applied + verified).

## Open questions

- Locale scope final answer: 7 locales declared, but rollout cadence (MVP zh-TW+en vs ship all 7 at v1) not pinned.
- Difficulty-level count not locked in §What (puzzle bank implies tiers but v1 feature list does not enumerate).
- SwiftPM module split timing: split Engine package vs App target now, or after first vertical slice?
- When to `git init` this folder — proposal was "after design.md §What approved", but actual init not yet performed.
- foundations.md §7.11 residual items: `ci_pre_xcodebuild.sh` hook naming, lefthook mise plugin specifics, gitleaks custom rule set — deferred to plan.md verification.
- Xcode Cloud `ci_scripts` environment + schedule UTC alignment — to be verified at plan.md stage.

## Next session

Produce `docs/plan.md` as a TDD-ordered, Superpowers-style implementation checklist covering all design.md decisions, with explicit verification steps for the foundations.md §7.11 and §How.4.9 open prerequisites; then `git init` and push as a public repo.
