# 2026-06-24 — post-#579 skills audit + apple-dev-skills extraction (Phase 1)

Mode: AI Collaboration Mode (Leader/Developer) + multi-agent review. Single session, two arcs.

## Arc 1 — Skills audit (merged PR #600)
Reconciled `.claude/skills` against what shipped in the #579 GameCenter-pipeline session:
- `telemetry-facade-pattern`: sink wiring traps (unwired-sink = dead code, sink ordering, non-blocking completion path via DeferredSink, terminal-call ≠ sink).
- `swift-testing-baseline`: snapshot-gate strategy (strict content / tolerant board; baselines are truth; headless AX dead-end).
- `ai-translated-localization` + `mise-task-operations`: scan:l10n shared-code dotted-key gate + blind spots + xcstrings text-splice footgun.
- `mise-tool-management`: macOS-only-tool `os` guard (the #597 lesson; user later added it, "D").
- **new** `game-factory-composition`: SDD-005 shipped composition template (GameConfig + makeGameApp). Indexed in README ×2.

## Arc 2 — apple-dev-skills extraction (merged PR #602)
Goal grew across the session into a 3-phase vision: extract portable skills into a reusable repo, consumed back via submodule; later npm + aggregate other repos (P2), curate the ecosystem (P3).

### Decisions (user-confirmed)
1. Scope = move ALL 26 portable skills; 8 project-bound stay flat.
2. New repo `apple-dev-skills` (public, MIT), genericize **during** the move, both stay+move grey-zone skills move.
3. **Fresh-history copy**, not `git filter-repo` — after the filter-repo step confused the user ("這段環節我不明白"), clarified copy-vs-history tradeoff; fresh history is cleaner for a new public repo (source history stays in Sudoku-spec). → lesson `explain-unfamiliar-tooling-before-executing`.
4. Consumption = **plugin marketplace**, not bare submodule. User wanted it to "just come with the project" → committed `.claude/settings.json` (project scope) + submodule pin = git-tracked, zero manual `/plugin install`.

### Verified mechanics (Claude Code docs, via claude-code-guide agent ×2)
- Plain skill discovery is **depth-1, no recursion** → a bare submodule of skills is NOT discovered.
- The in-repo `.claude/skills/superpowers` submodule is **vestigial**; superpowers loads from the marketplace cache. Cross-repo sharing = a plugin marketplace.
- Local-path marketplace source schema (got it from CC's own `known_marketplaces.json` after a CLI `marketplace add`): `{"source":"directory","path":"./relative"}` — relative path works because the submodule is a git repo. Project-scope `extraKnownMarketplaces` + `enabledPlugins` in committed `.claude/settings.json` auto-register on trust.

### Multi-agent review
- 1 genericize Developer (sonnet) → **3-way CR**: dfs (sonnet) / bfs (haiku) / staff (sonnet). dfs+staff caught dangling `[[stay-skill]]` refs (BLOCKER); **bfs (haiku) false-negatived** them as "intentional anchors". Leader adjudicated by grep (dfs+staff correct) → re-dispatched fixes → verified clean.

### Rejected / corrected
- `git filter-repo` history extraction — dropped for fresh copy (user clarity + cleaner new repo).
- Bare-submodule auto-discovery — doesn't work; pivoted to plugin marketplace.
- `git commit -a` silently dropped the new `marketplace.json` (`-a` ignores untracked) — caught by the failed `marketplace add`; re-committed with explicit `git add` (pr-diff-verification lesson, again).

### Outcome
- `wei18/apple-dev-skills` public, **v0.1.0** (601f3f8): 26 genericized skills, plugin.json + marketplace.json, README SSOT, MIT, repo settings (topics / squash-only / branch protection).
- Sudoku-spec (PR #602 → main 231c67b): submodule at `.claude/skills/apple-dev-skills` + committed `.claude/settings.json`; 26 flat duplicates removed; 8 project-bound stay-skills' cross-refs namespaced; READMEs + CLAUDE.md updated.
- Smoke-test PASSED: `/reload-plugins` surfaces all 26 `apple-dev-skills:*`; `claude plugin details` = 26 skills enabled (project scope). ~4.7k always-on tokens/session.

### Open / Next
- **P2** (own spec later): npm install path · README-as-SSOT agenda (done) · submodule *other* specialist skill repos (aggregate). Unverified: npm distribution mechanism; nested skill-repo aggregation (depth-1 limit).
- **P3**: survey high-star GitHub Swift skill repos → adopt / replace / skip.
- Memory: `apple-dev-skills-submodule`, `explain-unfamiliar-tooling-before-executing`.
