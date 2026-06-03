# Impl Notes — ASCRegister extraction into ASCRegisterKit (2026-06-03)

Status: COMPLETE
Owner: Developer subagent
Dispatched by: Leader
Started: 2026-06-03

GitHub issue: #254 — extract the ASCRegister dev CLI out of SudokuKit into its
own sibling SwiftPM package and surface it in the Tuist workspace.

## 設計決定 (Design decisions)

- **Single-target faithful relocation (NOT the 3-way split)** — Leader's brief
  §3 says: do the faithful relocation first; the issue's aspirational
  ASCRegister / ASCClient / ASCConfig sub-target split is OPTIONAL and only to
  be done if it falls out trivially clean. It does NOT — the sources are tightly
  coupled (`main.swift` references `Config`, `Reconciler`, `ASCClient`, `JWT`,
  `XCStringsParser` directly; `Reconciler` references `ASCClient` + `Config`;
  splitting would require carving public access surfaces across 3 targets and
  re-doing the `@testable` test imports). Deferred — kept the single
  `ASCRegister` executable target + `ASCRegisterTests`. Behavior unchanged.

- **macOS-only platform** — The CLI is a macOS dev tool (ASC API ops). Brief §1
  says "macOS-only platform". SudokuKit's manifest declared both `.iOS(.v26)` +
  `.macOS(.v26)` for the ASCRegister target (inherited from the package-level
  platforms). New ASCRegisterKit declares `platforms: [.macOS(.v26)]` only —
  this is the one intentional manifest difference from a faithful copy, and it
  is correct (an executable CLI never runs on iOS).

- **Resources preserved** — `Strings/gc-strings.xcstrings.patch` +
  `Strings/iap-strings.xcstrings.patch` moved with the sources and re-declared
  as `.copy(...)` resources on the executable target, identical to the old
  manifest (lines 240-243 of old SudokuKit/Package.swift).

## 偏離 (Deviations)

- **Updated stale invocation references to the old `--package-path`** — Beyond
  the move, two committed files invoke the CLI by its old package path and would
  break after the move:
  - `secrets/README.md:29` — `swift run --package-path Packages/SudokuKit ASCRegister iap plan ...`
    → **UPDATED** to `Packages/ASCRegisterKit` (user-facing daily-use doc).
  - `.claude/workflows/asc-apply-round.js:56` — `packagePath = args.packagePath || 'Packages/SudokuKit'` default
    → **NOT updated** (edit denied by sandbox permission on `.claude/workflows/`).
    Mitigated: the workflow already accepts a `packagePath` arg override, so callers
    can pass `packagePath: "Packages/ASCRegisterKit"`. **Follow-up for Leader**:
    update the default + the line-226 read hint to the new path.
  - `.claude/workflows/asc-apply-round.js:226` — hardcoded read hint
    `Packages/SudokuKit/Sources/ASCRegister/Config.swift` → same follow-up.
  Brief §2/§4 (mise-tool-management) asked to update any reference to the old
  path; `.mise.toml`/`mise-tasks/` had none, but these invocation refs are the
  equivalent tooling-path references.
  Left untouched: `.claude/settings.local.json` (gitignored, local permission
  allowlist, not committed) and docs/skills/meetings prose mentions of
  `tools/ASCRegister` (historical/conceptual, not live build paths).

## 折衷 (Tradeoffs)

- **git mv vs delete+create** — Used `git mv` per brief §6 to preserve history
  on all 9 source files + 9 test files + 2 resource patches.

## 未決 (Open questions)

- None load-bearing. The deferred 3-target split is explicitly Leader-sanctioned
  as optional; noted in the report for a future issue if desired.
