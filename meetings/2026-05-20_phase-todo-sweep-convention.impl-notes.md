# Impl Notes — phase-todo-sweep-convention (2026-05-20)

Status: COMPLETE
Owner: Developer (docs)
Dispatched by: Leader
Started: 2026-05-20

## 設計決定 (Design decisions)

- **Where to place the convention in `methodology.md`** — Added under §Sub-agent roster's 派發契約 as a new item #7 (closing-the-loop rule that fires at *phase completion*, not at dispatch time). The dispatch contract is the natural anchor because the sweep is the Leader's counterpart obligation to the subagent's impl-notes log (item #6). Putting it under §運作模式 would have been too vague; the contract block is where actionable Leader checklists already live.

- **Also added a §Pattern entry under 累積中的模式** — Style-matched the existing patterns (Trigger / Action / Outcome / Next-time adjustment / Sightings). The §Sightings line cites the Phase 8 sidebar stub as a *negative* example (formatted "反例" to be unambiguous; existing Phase 2.7 anti-example in the heavy-phase pattern uses the same word). Pattern entry duplicates the rule rather than just cross-referencing because every other §Pattern is self-contained — readers don't have to bounce.

- **Grep command choice** — Final command:
  ```
  rg -n --no-heading -e 'TODO|FIXME|XXX|HACK|stub|placeholder|Phase [0-9]+ Part' Packages/<target>/Sources/
  ```
  Picked `rg` (ripgrep) over `grep -rn` because:
  1. The project already uses `rg` in subagent dispatches (it's mise-managed-adjacent and faster on large trees); `grep -rn` would re-walk node_modules-equivalents on first run.
  2. `rg` defaults to respecting `.gitignore`, so generated / vendor folders don't pollute output.
  3. `-e` with `|` alternation is `rg` literal-by-default, fewer escape footguns vs `grep -E`.
  Token list:
  - `TODO|FIXME|XXX|HACK` — standard comment markers.
  - `stub|placeholder` — case-sensitive to avoid matching e.g. `StubData` test fixtures that are legitimately named; readers can lowercase the flags themselves if they want broader sweep. (Actually settled on case-sensitive because the Phase 8 example used `sidebarPlaceholder` with capital P — case-sensitive still catches it. Lowercase `stub` and `placeholder` are conventional comment language. False-positive risk: a `Stub` test fixture with capital S would not match; identifier `placeholder` in SwiftUI's `TextField(placeholder:)` *would* match. That's acceptable — the reviewer eyeballs matches anyway.)
  - `Phase [0-9]+ Part` — catches the specific Phase-X-Part-Y "I'll get back to this later" comment shape that bit us. Generic `Phase [0-9]` would match e.g. `// Phase 1 design.md says…` documentation comments too freely; `Phase [0-9]+ Part` is tight enough to flag real deferral notes while not exploding on prose.
  Dropped the user's draft `Phase [0-9]` token in favour of `Phase [0-9]+ Part` for that reason — recorded the deviation below.

- **`<target>` placeholder, not a hardcoded path** — The convention has to survive new SwiftPM target additions (SudokuKit, SolverKit eventually, future SwiftUIComponents). Hardcoding `Packages/SudokuKit/Sources/` would silently miss future packages. Phrased the doc copy as "run against the phase's diff scope" with `<target>` as a stand-in.

- **`subagent-review-cycles` skill placement** — Added a new section "Phase TODO sweep checklist" after "Verification checklist" rather than folding it in. The existing verification checklist is per-round (each review round); the TODO sweep is per-phase (once, at phase completion). Mixing them would conflate granularity. Section ordering: When to invoke → triad → round structure → cosmetic rule → dispatch contract → accept/reject → anti-patterns → verification checklist → **phase TODO sweep** → related skills. Sweep sits next to verification because they are sibling close-the-loop activities.

- **Skill matrix update in methodology.md** — Left the matrix row for `subagent-review-cycles` unchanged. The matrix lists *when to invoke* skills, and the skill is already listed for "模組初版完成、PR 前". Adding "phase TODO sweep" as a separate trigger would either bloat that single cell or require a new row. The 派發契約 item #7 and the §Pattern entry both already reference the skill by name — that's sufficient discoverability without matrix churn. Recording this as an explicit decision-not-to-edit.

## 偏離 (Deviations)

- **Dispatch suggested grep token `Phase [0-9]`; shipped `Phase [0-9]+ Part`** — See grep design decision above. The looser regex would generate too many prose-comment matches and train reviewers to skim past them. Tighter regex still catches the exact Phase 8 sidebar shape.
- **Dispatch said "grep -rn"; shipped `rg -n --no-heading`** — Same intent (recursive line-numbered match), faster + respects `.gitignore`. Documented in §設計決定.
- **Dispatch listed "(Optional, only if natural)" skill-matrix note as task #3; declined** — Reasoned above (single-cell bloat; already covered by §派發契約 + §Pattern). Explicit decline rather than silent skip.

## 折衷 (Tradeoffs)

- **Tighter regex vs. wider net** — Wider regex (`Phase [0-9]`) catches more potential debt at the cost of false positives. Tighter regex (`Phase [0-9]+ Part`) catches the specific shipped-stub shape. Picked tighter because the convention's job is to *create a discipline*, not to be an exhaustive lint — the reviewer can run a wider sweep ad-hoc if a phase smells. Recorded in §設計決定 so a future Leader can widen if the discipline lapses.
- **Case-sensitive `stub|placeholder`** — Misses `Stub` (capital), catches `Placeholder` and `placeholder`. Picked case-sensitive to avoid noisy `StubXxx` test-fixture matches. The Phase 8 sidebar stub used `sidebarPlaceholder` (capital P), which would not be caught by a case-sensitive `placeholder`. **Re-checked**: `rg` is case-sensitive by default but matches substring, so `placeholder` matches inside `sidebarPlaceholder`. Verified — `rg -n 'placeholder' <<<'sidebarPlaceholder'` matches. So case-sensitive is fine.
- **Per-phase vs. always-on lint** — Considered making this a lefthook pre-commit hook. Rejected: most legitimate TODO comments are valid mid-phase and would create constant friction. Per-phase manual sweep with documented justification is the right granularity.

## 未決 (Open questions)

_None._ The convention is actionable as written. If the discipline holds, the §Sightings line will accumulate positive sightings (sweep-caught debt) over time; if it doesn't hold, the §Sightings line will accumulate negative sightings (shipped stubs) and trigger a methodology revision.

## 驗證 (Verification beyond compile)

- **Markdown parses**: both files re-read after edit; no broken table rows, code fences balanced, list indentation consistent with surrounding sections.
- **No duplicate Pattern**: scanned existing 11 §Pattern entries; none cover phase-completion TODO sweep. Closest is "Post-execution doc sweep after structural changes" (which targets *docs* drift, not *code* TODO debt) — kept both, cross-referenced implicitly via the §Sightings reference to Phase 8 (the same phase that triggered the doc sweep pattern).
- **Style match — methodology.md**: zh-TW first with English tech terms (TODO / FIXME / stub / placeholder / Backlog / Leader kept English), terse phrasing, single-line bullets where possible. Pattern entry follows the existing Trigger/Action/Outcome/Next-time/Sightings five-line shape.
- **Style match — `subagent-review-cycles` SKILL.md**: English first per skill convention; section header matches existing `##` level; bullet style matches.
- **Actionability**: convention names (a) the exact command, (b) where to run (Packages/<target>/Sources/), (c) when (before declaring phase complete), (d) what to do with each match (resolve / move to §Backlog with file:line / log as intentional with follow-up issue). All four "what command / where / when / how to act" criteria satisfied.
