# Impl Notes — swiftui-footguns-skill (2026-05-20)

Status: COMPLETE
Owner: Developer (skills)
Dispatched by: Leader
Trigger: Issue #15 Bug 1 + Bug 2 — two SwiftUI interaction bugs slipped past Phase 8 Code Reviewer.

## 設計決定 (Design decisions)

- **Scope = pure-code-review blind spots, not all of SwiftUI** — Existing `swiftui-expert-skill` already covers Instruments / hang profiling. This skill stays narrow: bugs that look correct in code but fail at runtime, which is exactly the class a pure-code reviewer (no simulator, no smoke test) cannot catch by reading. Keeps the checklist greppable and the invocation criteria sharp.
- **Frontmatter description names the file-path triggers** — `Sources/.../SudokuUI/` and `*View*.swift` are the project's actual conventions. Letting the description carry the auto-invocation rule means future Code Reviewer dispatches don't need to manually remember to add this skill to the brief.
- **Two extra bullets added beyond brief** — View identity / `if-else` and `@Observable` + `@Bindable`. Both are common-enough footguns to belong here; flagged in §未決 below for Leader to validate they apply to *this* project's stack.
- **Frontmatter style matched to `ai-translated-localization/SKILL.md`** — single `name` + `description` keys; no extra metadata. Body uses `## When to invoke` / `## Checklist` / `## Sightings` / `## Related skills` structure consistent with peer skills.

## 偏離 (Deviations)

- None. Brief's checklist sections transcribed faithfully; ordering preserved; "Sightings" section uses issue #15 wording as given.

## 折衷 (Tradeoffs)

- **Length 119 lines vs 80-150 target** — In range. Could compress further by collapsing similar items (e.g., merging "Tap target" + "Touch target minimums") but kept separate because they're conceptually distinct (hit-test plumbing vs HIG audit) and the Code Reviewer mental sweep is bullet-by-bullet.

## 未決 (Open questions)

- **View identity `if/else` bullet** — Added based on general SwiftUI knowledge. Project hasn't been bitten by this *yet* (no sighting). Leader: keep speculative, or strip until first real occurrence?
- **`@Observable` + `@Bindable` bullet** — Same status. Project uses `@Observable` ViewModels (Phase 8). No reported bug from missing `@Bindable` yet. Keep as preventive checklist item, or strip?

## 驗證 (Verification)

- File exists at `/Users/zw/GitHub/Wei18/Sudoku-spec/.claude/skills/swiftui-interaction-footguns/SKILL.md`.
- 119 lines. YAML frontmatter parses (single `---` fences, two keys).
- Constraints respected: no Swift code touched; no other skills modified; only the two files (SKILL + this impl-notes) created.
