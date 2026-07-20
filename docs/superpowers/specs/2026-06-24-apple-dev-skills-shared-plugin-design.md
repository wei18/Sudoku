# 2026-06-24 — `apple-dev-skills`: extract portable skills into a shared Claude Code plugin (submodule)

Status: SHIPPED (see AS-BUILT NOTE below) — the body is retained as a historical design snapshot
Author: Leader (AI Collaboration Mode)
Origin: user goal "planning 一個新 repo，像 iOS agent developer skills，把這 repo 可移植的 skills 全部挪過去，用 submodule 概念連結回來"

> **AS-BUILT NOTE (verified 2026-07-10) — SHIPPED, diverges from the plan below.**
> Landed as a marketplace with **2 plugins** — `apple-dev-skills` and
> `collaboration-skills` — totaling **32** portable skills across both, namespaces
> `apple-dev-skills:` and `collaboration-skills:`; **9** project-bound skills stay
> flat in this repo (see `CLAUDE.md` §Where truth lives). This diverges from §2's
> single-plugin / 26-skill / one-namespace plan — treat this note, not the
> historical counts below, as current truth.

## 1. Goal

Create a **separate, reusable repo** `apple-dev-skills` that holds every
project-agnostic skill currently living in `Sudoku-spec/.claude/skills/`, packaged
as a **Claude Code skills-directory plugin**, and consume it back from this repo
as a **git submodule** under `.claude/skills/apple-dev-skills/`. Project-specific
skills stay flat in this repo. The payoff: the portable skill set becomes
reusable across any future Apple-platform project (the "game factory" north star
extends to a "project factory") and evolves with its own PR trail, while this repo
keeps only what is genuinely Sudoku/Minesweeper/Tiles2048-bound.

## 2. Decisions (user-confirmed)

1. **Scope = move ALL portable skills** (maximal), not just the platform defaults.
2. **Repo / plugin name = `apple-dev-skills`** → skill namespace `apple-dev-skills:`.
3. **Grey-zone skills** (`app-store-review-rejections`, `monetization-sdk-integration`)
   **move** — their core knowledge is portable to any ads+IAP iOS app.
4. **Genericize during the move** — strip Sudoku-specific paths/task-names into
   neutral examples as part of the migration (not a deferred second PR).
5. **Namespacing is accepted** — it is forced by the submodule-plugin mechanism
   (see §4); moved skills become `apple-dev-skills:<skill>`, mirroring how
   `superpowers:<skill>` already works in this repo.

## 2a. Roadmap — three phases (user, 2026-06-24)

`apple-dev-skills` is not just a dumping ground for this repo's skills; it is meant
to become **the Swift/Apple-platform engineer-agent's professional skill library**,
composable and self-describing.

- **Phase 1 — Extract (this plan's core).** Move the 26 portable skills out of
  Sudoku-spec into `apple-dev-skills`, genericize, consume back as a submodule.
- **Phase 2 — Make it a real standalone library.** (a) `README.md` is the
  **single source of truth / agenda** — what the library is, the full skill index,
  how to consume it. (b) An **npm-based install path** so any project can pull the
  skills (mirrors the `npx <tool>` distribution pattern Claude Code skill packages
  use), in addition to the submodule path. (c) The repo can itself **submodule
  *other* specialist skill repos** (e.g. a high-quality swift-testing or
  concurrency skill set) so it aggregates best-of-breed instead of reinventing —
  a "skill library of skill libraries".
- **Phase 3 — Curate from the ecosystem.** Survey **high-star GitHub Swift /
  Apple-platform skill repos**, analyze each against our set, and decide per skill:
  **adopt** (submodule/import it), **replace** ours with theirs, or **skip**.
  Output: a documented inclusion decision per candidate.

Phases 2 and 3 are **planned, not yet designed in detail** — each gets its own
spec/plan once Phase 1 lands. Two feasibility items must be verified before P2/P3
build (see §3): the npm distribution mechanism and nested skill-repo aggregation.

## 3. Verified prerequisite — skill discovery mechanics

Confirmed against official Claude Code docs (skills.md, plugins.md,
plugins-reference.md) via the `claude-code-guide` agent:

- **Plain project-skill discovery is depth-1 only and does NOT recurse.** Skills
  must be `.claude/skills/<skill>/SKILL.md`. A submodule nesting skills at
  `.claude/skills/<lib>/<skill>/SKILL.md` (depth-2) would **NOT** be discovered as
  plain skills. → A raw submodule-of-flat-skills does not work.
- **The idiomatic cross-repo share is a "skills-directory plugin":** the shared
  repo carries `.claude-plugin/plugin.json` at its root + `skills/<skill>/SKILL.md`;
  mounted at `.claude/skills/<name>/` it auto-loads as `<name>@skills-dir`.
- **Being a plugin forces a namespace** (the `name` field in `plugin.json`).
  Un-namespaced sharing via submodule is not possible; accept `apple-dev-skills:`.
- **No collisions**: plugin-namespaced skills cannot clash with the flat project
  skills that remain.

### Phase-2/3 Unconfirmed items (verify before building those phases — NOT blocking Phase 1)

- **npm distribution mechanism.** How a Claude Code skill set is idiomatically
  installed via npm (a CLI with an `install` command that copies skills into the
  consumer's `.claude/skills/`? a postinstall script? a published plugin the CC
  marketplace pulls?). Verify against Claude Code plugin/marketplace docs + the
  `npx`-style precedents (e.g. claude-mem) before committing P2 to a mechanism.
- **Nested skill-repo aggregation.** Whether a plugin can surface skills that live
  in *its own* git submodules (depth-2 within `skills/`), given plain skill
  discovery is depth-1. Likely the aggregation must happen at the **consumer**
  level (each specialist repo mounted as its own plugin submodule) or via the
  plugin manifest declaring multiple skill sources — verify before P2(c)/P3.

### Phase-1 Unconfirmed item (smoke-test gate, not a spec unknown)

Docs are explicit on the plugin manifest requirement but **silent on git
submodules specifically**; the "`.claude/skills/<name>/` with `plugin.json`
auto-loads as `@skills-dir`" behavior is inferred from the skills-directory-plugin
spec. **Resolution:** at implementation start, scaffold the `plugin.json`, restart
Claude Code once, and confirm `apple-dev-skills:*` skills appear. This is a
documented-mechanism smoke test, not reverse-engineering a spec. If auto-load
does not occur from a bare submodule path, fall back to registering a local
marketplace entry pointing at the submodule (also documented). Either way the
plugin structure is identical; only the registration line differs.

## 4. Architecture

```
apple-dev-skills/                  ← NEW repo (source of truth, a CC plugin)
├── .claude-plugin/
│   └── plugin.json                  { name: "apple-dev-skills", version, description }
├── skills/
│   ├── swift6-concurrency/SKILL.md
│   ├── telemetry-facade-pattern/SKILL.md
│   └── … (26 skills)          ← historical plan; as-built = 32 skills across 2 plugins, see AS-BUILT NOTE
├── README.md
└── README.zh-Hant.md

Sudoku-spec/ (this repo)
└── .claude/skills/
    ├── apple-dev-skills/          ← git submodule → apple-dev-skills@skills-dir
    │   (skills surface as apple-dev-skills:<skill>)
    └── <9 project-bound skills>/  ← stay flat, un-namespaced (plan said 8; as-built = 9, see AS-BUILT NOTE)
```

This repo continues to have access to all skills; the 26 moved ones simply carry
the `apple-dev-skills:` prefix.

## 5. Classification (historical plan: 34 → move 26 / stay 8; as-built: 32 move across 2 plugins / stay 9 — see AS-BUILT NOTE)

> **UPDATE (2026-07-13):** Stay count corrected to **9** — `screen-contract-spec`
> (added to this repo after this spec was written) is also project-bound and
> stays flat; item 9 below is appended accordingly. See the AS-BUILT NOTE above.

### Stay (project-bound — names this repo's mise tasks / specific apps / pipelines)
1. `game-factory-composition` — Sudoku/MS/2048 + GameAppKit `makeGameApp`
2. `mise-task-operations` — index of THIS repo's `mise run` tasks
3. `cloudkit-schema-ops` — `ck:schema` task, `.ckdb`, the apps' containers
4. `local-testflight-upload` — `tf:upload` task
5. `appstore-screenshot-pipeline` — `store:screenshots` task
6. `acknowledgements-generation` — `gen:acknowledgements`, `license_plist.yml`
7. `asc-ops-handoff` — the repo apps, ASCRegister CLI, app-ids
8. `interactive-sim-ux-audit` — drives the three specific apps
9. `screen-contract-spec` — nav/flow spec-first methodology for this repo's screens
   *(added 2026-07-13 per the UPDATE above; not part of the original 2026-06-24 plan)*

### Move (portable — 26)
- **Platform defaults (10):** swift6-concurrency · apple-platform-targets ·
  swiftpm-modularization · swift-testing-baseline · xcode-cloud-single-track-ci ·
  mise-tool-management · oslog-logger-defaults · apple-three-piece-analytics ·
  telemetry-facade-pattern · ai-translated-localization
- **Process & collaboration (7):** session-to-meeting-log ·
  methodology-pattern-extractor · subagent-review-cycles · spec-phase-orchestration ·
  backlog-routing-by-topic · apple-public-repo-security · leader-developer-handoff-contract
- **Portable ops/review (9):** agent-impl-notes-log · pr-diff-verification ·
  subagent-conflict-detection · swiftui-interaction-footguns ·
  build-time-secret-injection · app-icon-rasterize · ios-design-mockup ·
  app-store-review-rejections · monetization-sdk-integration

## 6. Genericize-during-move principle

Goal: portable for any Apple-platform project **without losing the hard-won
concreteness** (the value is in the real examples).

- **Strip hard dependencies** that wouldn't exist elsewhere: repo-specific task
  names (`mise run scan:l10n`), module paths (`Packages/AppMonetizationKit/…`,
  `Sources/SudokuUI/…`), app names where they imply a fixed product.
- **Keep concrete lessons as labelled examples**: reframe "in Sudoku #579 the GC
  sink was unwired" as "real-world example: a telemetry sink existed but was never
  added to the live sinks list → silent no-op". The lesson stays; the hard
  coupling goes.
- **Issue references** (`#579`, `#594`): keep at most as "(from a real project)"
  flavor, never as a live link the reader is expected to resolve.
- Skills needing the heaviest pass: `telemetry-facade-pattern`,
  `ai-translated-localization` (scan:l10n gate text), `monetization-sdk-integration`
  (AdMob bridge paths), `swiftui-interaction-footguns` (SudokuUI paths),
  `apple-public-repo-security`, `backlog-routing-by-topic` (spec-file names).

## 7. Cross-reference rewrite

Skills reference each other in prose "Related skills" lists. After the split:
- **moved → moved** refs stay as bare names (same plugin) — no change.
- **stay → moved** refs must point to the namespaced form, e.g.
  `game-factory-composition`'s "Related: `telemetry-facade-pattern`" →
  `apple-dev-skills:telemetry-facade-pattern`. Enumerable set:
  `game-factory-composition` (4 refs), `mise-task-operations` (its "Deeper skill"
  column: several moved targets), the other stay skills' Related lists.
- **moved → stay** refs (rare): a generic skill should NOT depend on a
  project-bound one; if found, drop the ref during genericize.

## 8. Migration mechanics (history-preserving)

1. **Extract with history** into `apple-dev-skills` via `git filter-repo`
   (subdirectory-filter the 26 skill dirs into `skills/`), or a clean
   `git subtree split` fallback. Preserves each skill's commit trail.
2. **Genericize pass** (commits in the new repo) per §6 before first tag.
3. **Scaffold the plugin**: `.claude-plugin/plugin.json` + READMEs (full index
   moves here). Smoke-test discovery (§3).
4. **In this repo**: `git rm -r` the 26 flat dirs → `git submodule add
   <apple-dev-skills-url> .claude/skills/apple-dev-skills` pinned to a tag.
5. **Slim this repo's READMEs** to the 8 project skills + a pointer line to the
   submodule (mirror the existing superpowers submodule note).
6. **Rewrite cross-refs** per §7.
7. **Verify**: restart Claude Code; confirm 8 flat skills un-namespaced + 26
   `apple-dev-skills:*` skills all resolve; `swift test` unaffected (skills are
   docs, no build impact); `mise run scan:*` gates still green.

## 9. Non-goals / YAGNI (Phase 1 scope)

- **Phase 1 does not** build the npm install path, the README-as-SSOT agenda, or
  the aggregate-other-repos capability — those are **Phase 2** (deferred by
  design, not dropped). Phase 1 ships the submodule-consumable plugin only.
- **Phase 1 does not** survey/adopt external skill repos — that is **Phase 3**.
- **Not** promoting these to user-level (`~/.claude/skills`) — the repo-as-plugin
  keeps the public showcase + PR-trail property this project values.
- **Not** genericizing the 8 stay skills — they are deliberately repo-bound.
- **Not** changing any product/runtime code — skills are documentation only.

## 10. Risks

- **Submodule auto-load uncertainty** (§3) — mitigated by the smoke-test gate +
  documented marketplace fallback.
- **Over-genericizing** strips the concrete value — mitigated by the "keep
  lessons as labelled examples" principle (§6).
- **Two-repo drift** — a skill's project-specific addendum could get re-added to
  the wrong repo. Mitigation: the stay/move boundary in §5 is the contract;
  anything naming a `mise run` task or a specific App belongs in this repo.
- **Submodule friction for contributors** — `git clone --recurse-submodules`
  needed; document in this repo's README (mirror the superpowers note).
