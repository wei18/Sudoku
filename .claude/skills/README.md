# Project Skills

> A Traditional Chinese version of this document is available at [`README.zh-Hant.md`](README.zh-Hant.md).

This directory holds the skills available in this project. It has two parts:

1. **Project-bound skills (8)** — flat `SKILL.md` directories below. These name this
   repo's specific apps (Sudoku / Minesweeper), `mise run` tasks, and
   pipelines, so they are *not* portable and live here un-namespaced.
2. **The `apple-dev-skills` marketplace (2 plugins, 32 skills)** — the portable
   Apple-platform / AI-agent-collaboration skills were extracted into
   [`wei18/apple-dev-skills`](https://github.com/wei18/apple-dev-skills), vendored
   here as a git submodule at `apple-dev-skills/` and loaded as TWO Claude Code
   plugins: **`apple-dev-skills:<skill>`** (20, Apple-platform engineering) and
   **`collaboration-skills:<skill>`** (12, Leader-Developer collaboration patterns).

---

## Project-bound skills (8)

| Skill | One-liner |
|---|---|
| [`game-factory-composition`](game-factory-composition/SKILL.md) | The shared composition template — `GameConfig<Route>` + `makeGameApp` in GameAppKit, `<Game><Concern>` naming, shared Home / DailyHub-skeleton / board-redirect / GC-dashboard; only the Game module is per-game (SDD-005) |
| [`mise-task-operations`](mise-task-operations/SKILL.md) | Index / entry point for every repo ops task — before grepping "how is X done", check here; maps each `mise run` task → invocation + safety gate + owning skill |
| [`local-testflight-upload`](local-testflight-upload/SKILL.md) | Local archive→export→TestFlight via `mise run tf:upload`; temporary Xcode-Cloud-Main-CI substitute; upload gated behind `--i-am-sure` |
| [`cloudkit-schema-ops`](cloudkit-schema-ops/SKILL.md) | Export / validate / deploy CloudKit schema via `mise run ck:schema` (`xcrun cktool`); `.ckdb` source of truth; Production promote = CloudKit Console-only (user-owned) |
| [`appstore-screenshot-pipeline`](appstore-screenshot-pipeline/SKILL.md) | Sync App Store screenshot PREVIEWS from snapshot baselines via `mise run store:screenshots`; symlink-based, PREVIEW-ONLY (not ASC submission-spec) |
| [`acknowledgements-generation`](acknowledgements-generation/SKILL.md) | Regenerate Settings.bundle Acknowledgements from the SwiftPM dep graph via `mise run gen:acknowledgements` (LicensePlist); output gitignored |
| [`asc-ops-handoff`](asc-ops-handoff/SKILL.md) | Which App Store Connect / TestFlight steps are user-owned vs Leader-orderable via the ASC API + ASCRegister |
| [`interactive-sim-ux-audit`](interactive-sim-ux-audit/SKILL.md) | Drive the running game apps in the iOS Simulator with idb (tap / describe / screenshot) to find UX + layout bugs snapshot tests cannot |

**Moved:** `screen-contract-spec` is no longer project-bound — its methodology master copy now
lives in the design-app playbook (`~/GitHub/Wei18/design-app/skills/`), installed to user-level
via `bash skills/install.sh`. This repo's `docs/screen-contracts.md` + `docs/navigation-flows.md`
remain the worked example.

---

## The `apple-dev-skills` marketplace (2 plugins, 32 skills, namespaced)

The portable skills live in the
[`apple-dev-skills`](apple-dev-skills/README.md) submodule — a Claude Code plugin
**marketplace** hosting two plugins:

- **`apple-dev-skills`** (20) — Swift 6 / SwiftPM / testing / CI / L10n / telemetry
  defaults; surfaces as `apple-dev-skills:<skill>`.
- **`collaboration-skills`** (12) — Leader-Developer collaboration patterns
  (dispatch contracts, review cycles, spec orchestration); surfaces as
  `collaboration-skills:<skill>`.

Wiring is committed and reproducible:

- **submodule** `apple-dev-skills/` pins the exact version (a commit SHA).
- **`.claude/settings.json`** (project scope) declares it as a local-path plugin
  marketplace + enables **both** plugins, so on clone + workspace-trust Claude Code
  auto-registers them — no manual `/plugin install`.

Full index of the 32: see [`apple-dev-skills/README.md`](apple-dev-skills/README.md).

> `superpowers` content lives at `docs/superpowers/` as ordinary tracked files (not
> a git submodule); `.gitmodules` declares only `apple-dev-skills`. It is not
> catalogued here.

---

## Why these skills live in the repo

- **The repo is public from day 1**, and this skill set is part of the "Claude agent
  application record" showcase.
- **Reproducibility**: any reader who clones (with submodules) + trusts the workspace
  gets the same skill set out of the box.
- **Transparent evolution**: skills evolve with the project, and PRs leave a diff trail.
