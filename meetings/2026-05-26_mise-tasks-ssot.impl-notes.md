# Impl Notes — mise tasks SSOT refactor (2026-05-26)

Status: COMPLETE
Owner: DevOps Automator (subagent)
Dispatched by: Leader
Started: 2026-05-26

## 設計決定 (Design decisions)

- **Task definitions inline in `.mise.toml`** — Mission allowed `mise-tasks/` dir as alternative. Chose inline `[tasks.*]` because (a) only 4 tasks, no need for a directory of script files; (b) keeps version pins + task defs co-located (single SSOT file); (c) one task body has multi-line shell which TOML triple-quoted strings handle cleanly.

- **Task naming** — Used colon-namespaced names exactly as mission prescribed: `lint:swift`, `lint:swift:strict`, `scan:secrets`, `scan:hygiene`, `gen:acknowledgements`. Colon is mise's canonical hierarchy separator (see `pull:cli-defaults` already present in user's global tasks).

## 折衷 (Tradeoffs)

- **Strict-mode handling — picked option (b) two tasks (`lint:swift` + `lint:swift:strict`)** instead of option (a) env-flag variant.
  - Considered (a): single task `lint:swift` reading `$STRICT` and conditionally adding `--strict`. Body would be ~3 lines of shell with `if [ -n "$STRICT" ]`.
  - Picked (b): two tasks. Reason: mise tasks declare arguments inline; adding env-conditional shell logic obscures intent and forces every caller to remember the magic env var. Two tasks are self-documenting (`mise tasks` output shows both, with descriptions). Body of each is a single command — no shell branching. Lefthook YAML and CI YAML each name the variant they want; future readers don't have to grep for `STRICT=`.
  - Cost: 2 task definitions instead of 1. Acceptable given mission explicitly listed (b) as fallback "if mise doesn't support clean env-based variant" — and even though mise does support env vars, the resulting task body is uglier.

## 偏離 (Deviations)

(none — flags preserved exactly, including `--strict --quiet` in CI variant and bare `--quiet` in dev variant.)

## 未決 (Open questions)

(none load-bearing)
