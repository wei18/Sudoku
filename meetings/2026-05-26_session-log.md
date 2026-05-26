# Session log — 2026-05-26 (v2.5 cleanup + module split + CI/tooling SSOT)

## Scope

Multi-hour Leader/Developer session continuing from 2026-05-25. Theme:
ship v2.5 follow-ups, complete the module-split roadmap (Stages 1 + 2),
and consolidate CI / tooling configuration into a single source of
truth.

## Landed (chronological by merge)

| PR | Title | Notes |
|----|-------|-------|
| #144 | docs(backlog): consolidate Android entries — canonical at v1/design.md | 05-25 spillover, merged past midnight |
| #145 | docs(backlog): cancel ASCRegister IAP mode (v2 has 1 IAP — ROI not there) | 05-25 spillover, merged past midnight |
| #146 | feat(game-center): centre leaderboard slice on local player rank (closes #140) | issue-140 impl-notes |
| #147 | ci(github-actions): Phase 1 advisory workflows (PR title lint / SwiftLint+SwiftFormat / docs link check) | superseded by #159 |
| #148 | docs+cleanup: N2 paired-flip + N5 set.remove + N6 audit regex (PR #143) | AdMob nits |
| #149 | chore(tooling): add swiftformat lint to lefthook with relaxed baseline config (option b) | OBSOLETED same day — see #159 addendum |
| #151 | ci(github-actions): flip lint.yml SwiftFormat to hard-fail (PR #149 follow-up) | OBSOLETED same day |
| #152 | docs(skills): fill 4 repo-derived skills (closes #11 5-of-5 backlog item) | subagent-conflict-detection, pr-diff-verification, asc-ops-handoff, monetization-sdk-integration |
| #153 | chore(ci): integrate LicensePlist for Settings.bundle Acknowledgements | licenseplist-settings-bundle impl-notes |
| #154 | feat(modules): extract SudokuCoreKit sibling package (SudokuEngine + GameState) | Stage 1 — closes module-split #15 |
| #155 | docs(backlog): add ViewModel interaction tests + Mockable evaluation entries | doc-only |
| #159 | ci(github-actions): consolidate 3 workflows into single lint.yml with 3 jobs | + swiftformat full removal addendum |
| #160 | refactor(mise): extract 4 tool invocations into [tasks.*] SSOT | Stage 1 + 2 — file-based per `mise-tasks/` |
| #161 | refactor(modules): extract TelemetryKit package + TelemetryTesting carve-out (Stage 2, closes #16) | Stage 2 — TelemetryKit + TelemetryTesting library products |

## Module-split status (foundations.md §2)

- ✅ Stage 1: SudokuCoreKit (SudokuEngine + GameState) — PR #154
- ✅ Stage 2: TelemetryKit + TelemetryTesting carve-out — PR #161
- ⏳ Stage 3: GameCenterKit + PersistenceKit extraction — task #17 queued

## Tooling SSOT (mise tasks file-based)

`mise-tasks/<namespace>/<name>` (chmod 100755) → invoked as
`mise run <namespace>:<name>`. Lefthook, GH Actions, and Xcode Cloud
all route through `mise run …` — flag changes happen in one place.

Tasks landed:
- `lint:swift` (warn-only, lefthook) / `lint:swift:strict` (hard-fail, CI)
- `scan:secrets` (gitleaks) / `scan:hygiene` (secret-shaped filename guard)
- `gen:acknowledgements` (license-plist)

Removed: swiftformat (full purge — `.swiftformat`, mise pin,
lefthook hook, CI step). User decision: swiftlint coverage sufficient.

## GitHub Actions consolidation

Before: 3 separate workflows (`pr-metadata.yml`, `docs-link-check.yml`,
`lint.yml`). After: single `lint.yml` with 3 jobs (pr-metadata,
docs-link-check, swift-lint), all on `ubuntu-latest`, changed-files via
`gh api pulls/{n}/files` (no `fetch-depth: 0`).

Follow-up issues filed for Phase 2/3: #156, #157, #158.

## Operational learnings (codified into memory / methodology)

- **Code Reviewer rule is OR not AND** — `>50 LOC` *alone* triggers CR
  even for doc-only PRs (methodology §派發契約 §8). Memory:
  `[[feedback-code-reviewer-rule-is-or-not-and]]`.
- **Project-derived skills location** — `<repo>/.claude/skills/`, not
  `$HOME/.claude/skills/`. Memory:
  `[[feedback-project-derived-skills-location]]`.
- **Leader stays coordinator** — when subagents struggle, re-dispatch
  with sharper guidance; do NOT take over Developer work. Memory:
  `[[feedback-leader-stays-coordinator]]`.
- **NO-VERIFY dispatch pattern** — emerged after 3 SudokuCoreKit
  subagent attempts died waiting on Monitor for build/test. Winning
  pattern: subagent only edits + commits + pushes; Leader handles
  `swift build` / `swift test` post-push. Builds on methodology
  §派發契約 §10 commit-early discipline.
- **Surgical per-file analysis** — TelemetryKit Stage 2 first attempt
  used over-broad sed across 16+ files; final pattern dispatched a
  fresh subagent that did per-file `import` analysis (5 pure swap, 4
  add-alongside) — committed 6 clean atomic commits, no rewrite churn.

## Pre-flight + backlog

- Pre-flight #132 reviewed; `docs/v2/v2.5-readiness.md` unchanged
  (matches user's GH issue checkboxes).
- Backlog additions (`docs/foundations.md §Backlog`):
  - ViewModel interaction tests (no new dep) — PR #155
  - Mockable evaluation (trigger-based) — PR #155
  - `docs/` + `meetings/` → GitHub Wiki migration (2 options)
    — this PR
