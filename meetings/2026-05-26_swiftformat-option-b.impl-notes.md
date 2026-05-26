# swiftformat option (b): relax rules to current style + add to lefthook

## Scope
User chose option (b) over (a) mass-format (3,624 LOC churn, 204 files)
and (c) defer. Goal: author `.swiftformat` so the existing codebase
PASSES `swiftformat --lint Packages/ App/ --swiftversion 6.2` without
touching any `.swift` file, then add `swiftformat --lint` to lefthook
pre-commit so future code stays in the (relaxed but consistent) style.

## Baseline analysis (origin/main @ 8812574)
`mise exec swiftformat -- swiftformat --lint Packages/ App/ --swiftversion 6.2`
reports 204/244 files non-compliant. Grouped by rule:

| rule                          | violations |
|-------------------------------|-----------:|
| indent                        |        669 |
| redundantInternal             |        238 |
| sortImports                   |        199 |
| hoistPatternLet               |        146 |
| blankLinesAtStartOfScope      |        141 |
| spaceAroundOperators          |        117 |
| redundantReturn               |         93 |
| redundantSelf                 |         84 |
| conditionalAssignment         |         76 |
| extensionAccessControl        |         68 |
| consecutiveSpaces             |         59 |
| trailingCommas                |         51 |
| unusedArguments               |         47 |
| numberFormatting              |         38 |
| blankLinesAroundMark          |         34 |
| wrapLoopBodies                |         22 |
| wrapMultilineStatementBraces  |         17 |
| opaqueGenericParameters       |         16 |
| redundantType                 |         12 |
| (long tail < 10 each)         |        ~40 |

The `indent` 669 was mostly `#if/#else/#endif` directives placed at column 1
inside function bodies — addressed by `--ifdef no-indent`. After that
option, 16 residual `indent` violations remained (continuation-line
indent in `guard let ..., let ..., let ... else` and `for ... where`
clauses in Solver.swift / Reconciler.swift / a few tests), so `indent`
itself was also added to the disabled list to preserve current style.

## Decisions

1. **Disabled 18 high-volume rules** (rules with ≥ 10 violations each)
   plus 14 long-tail rules (< 10 each). All listed in `.swiftformat`
   with violation count as inline comment for future re-evaluation.
2. **Kept `--swiftversion 6.2` pin** in config (not just CLI flag) so
   editor integrations and future invocations stay deterministic.
3. **`--ifdef no-indent`** chosen to match dominant codebase pattern;
   reverses default `indent` behavior for preprocessor directives.
4. **No rules left in `--enable` allowlist explicitly** — relying on
   swiftformat defaults minus the disabled set keeps the config compact
   and avoids drift if a new default rule lands in 0.55+.
5. **lefthook entry placed AFTER swiftlint** within the sequential
   `pre-commit.commands` block (parallel:false per #136 RCA H4).

## Considered alternatives
- **`--enable` allowlist instead of `--disable` blocklist**: rejected
  because it would silently exclude future-added rules from enforcement
  on new code. Blocklist makes "what we DON'T enforce" auditable.
- **Per-rule auto-fix the 11 long-tail rules** (each < 10 violations,
  total ~40 files): rejected because it would still violate the
  no-source-touch constraint. Re-evaluation trigger covers this if
  reviewers care.
- **`stage_fixed: true` + drop `--lint`**: rejected — user wants
  report-only behavior so the commit FAILS rather than silently
  mutating staged content (same posture as the 2026-05-24 attempt
  documented in `meetings/2026-05-24_lefthook-swiftformat.impl-notes.md`,
  which was apparently never merged).

## Verify
- `mise exec swiftformat -- swiftformat --lint Packages/ App/` → exit 0,
  `0/244 files require formatting.` (config reads OK from repo root)
- `swiftformat --version` → 0.54.6 (matches `.mise.toml` pin)
- No `.swift` source files touched (only `.swiftformat`, `lefthook.yml`,
  `docs/foundations.md`, this impl-notes file)
- lefthook entry uses `glob: "*.{swift}"` so non-Swift commits skip the
  step (consistent with `swiftlint` command above it)

## §未決
- Should the 16 residual `indent` violations (Solver / Reconciler /
  test files) be touched in a one-off PR to flip `indent` back on?
  Park: low priority — those files are stable and the pattern is
  legible. Re-evaluation trigger in `foundations.md §7.5.1` covers
  the policy.
- Aqua-cached swiftformat install is per-user; first invocation on a
  new machine triggers download. Not blocking — `ci_post_clone.sh`
  already does `mise install` upfront.
