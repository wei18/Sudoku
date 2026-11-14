# Project Skills

> A Traditional Chinese version of this document is available at [`README.zh-Hant.md`](README.zh-Hant.md).

This directory holds the skills available in this project. It has two parts:

1. **Project skills**: the flat `SKILL.md` directories listed below. They name this
   repo's apps (Sudoku, Minesweeper), `mise run` tasks and pipelines, so they are
   not portable and carry no namespace.
2. **Plugin skills**: portable Apple-platform and agent-collaboration skills from
   [`wei18/apple-dev-skills`](https://github.com/wei18/apple-dev-skills), pinned
   here as the git submodule `apple-dev-skills/`. This repo enables two of its
   plugins: `apple-dev-skills:<skill>` and `collaboration-skills:<skill>`.

---

## Project skills

| Skill | Use it for |
|---|---|
| [`mise-task-operations`](mise-task-operations/SKILL.md) | Index of every `mise run` task. Check it before running or writing an ops command |
| [`game-factory-composition`](game-factory-composition/SKILL.md) | The shared composition template (`GameConfig<Route>`, `makeGameApp`), target naming, and what is shared or per-game; adding a game |
| [`interactive-sim-ux-audit`](interactive-sim-ux-audit/SKILL.md) | Repo setup for driving the apps in the iOS Simulator: build and install, DEBUG launch arguments, sign-in states |
| [`local-testflight-upload`](local-testflight-upload/SKILL.md) | Archive, export and upload to TestFlight with `mise run tf:upload`; the upload is gated by `--i-am-sure` |
| [`cloudkit-schema-ops`](cloudkit-schema-ops/SKILL.md) | Export, validate and deploy the CloudKit schema with `mise run ck:schema`; Production promotion is the user's Console step |
| [`appstore-screenshot-pipeline`](appstore-screenshot-pipeline/SKILL.md) | Capture the live board, build the App Store Connect screenshot frames, preview and upload them |
| [`acknowledgements-generation`](acknowledgements-generation/SKILL.md) | Regenerate the `Settings.bundle` license page with `mise run gen:acknowledgements` |
| [`asc-ops-handoff`](asc-ops-handoff/SKILL.md) | Which App Store Connect, TestFlight and AdMob steps the user owns and which an agent may run; how production AdMob IDs reach a build |

`screen-contract-spec` is not a project skill; it is installed at user level.
`docs/screen-contracts.md` and `docs/navigation-flows.md` are its worked example.

---

## Plugin skills (the `apple-dev-skills` submodule)

The submodule is a Claude Code plugin marketplace. This repo enables two of its plugins:

- **`apple-dev-skills`**: Swift 6, SwiftPM, testing, CI, localization, telemetry,
  simulator and Xcode hygiene skills, and the `swift-staff-reviewer` agent.
- **`collaboration-skills`**: Leader and Developer collaboration skills (dispatch
  briefs, review cycles, spec orchestration, PR diff verification).

The wiring is committed:

- The submodule pins an exact release of `wei18/apple-dev-skills`. Run
  `git submodule update --init` after cloning.
- `.claude/settings.json` declares the submodule as a local plugin marketplace and
  enables both plugins. After you clone and trust the workspace, Claude Code
  registers them; no `/plugin install` is needed.

The catalog of plugin skills is [`apple-dev-skills/README.md`](apple-dev-skills/README.md).
That file is the only place that lists them; this README keeps no count.

> `docs/superpowers/` holds ordinary tracked files, not a submodule. It is not
> catalogued here.

---

## Why these skills live in the repo

- The repo is public, and the skill set is part of its record of applying Claude
  agents to a real project.
- Anyone who clones with submodules and trusts the workspace gets the same skills.
- Skills change with the project, and each change is a reviewable diff.
