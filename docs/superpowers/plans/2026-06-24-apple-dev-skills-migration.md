# apple-dev-skills Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the 26 portable skills from `Sudoku-spec/.claude/skills/` into a new `apple-dev-skills` repo packaged as a Claude Code skills-directory plugin, consumed back as a git submodule; genericize during the move; leave 8 project-bound skills flat.

**Architecture:** New repo `apple-dev-skills` carries `.claude-plugin/plugin.json` + `skills/<skill>/SKILL.md`. This repo mounts it at `.claude/skills/apple-dev-skills/` (submodule → `apple-dev-skills@skills-dir`, namespace `apple-dev-skills:`). Discovery verified as depth-1 + plugin-manifest (see spec §3).

**Tech Stack:** git submodule, git filter-repo (or copy fallback), Claude Code plugin manifest, Markdown.

**Spec:** `docs/superpowers/specs/2026-06-24-apple-dev-skills-shared-plugin-design.md`

**Conventions (this repo):** commits via `git commit --no-gpg-sign -F <file>` (heredocs blocked by hooks; signing hangs); PR titles Conventional Commits, subject lowercase; after any merge from main checkout, `git fetch && git reset --hard origin/main`.

**Paths:** new repo working copy at `/Users/zw/GitHub/Wei18/apple-dev-skills`; this repo at `/Users/zw/GitHub/Wei18/Sudoku-spec`.

---

## The 26 moved skills (canonical list)

```
swift6-concurrency apple-platform-targets swiftpm-modularization
swift-testing-baseline xcode-cloud-single-track-ci mise-tool-management
oslog-logger-defaults apple-three-piece-analytics telemetry-facade-pattern
ai-translated-localization session-to-meeting-log methodology-pattern-extractor
subagent-review-cycles spec-phase-orchestration backlog-routing-by-topic
apple-public-repo-security leader-developer-handoff-contract agent-impl-notes-log
pr-diff-verification subagent-conflict-detection swiftui-interaction-footguns
build-time-secret-injection app-icon-rasterize ios-design-mockup
app-store-review-rejections monetization-sdk-integration
```

## The 8 staying skills (must NOT move)

```
game-factory-composition mise-task-operations cloudkit-schema-ops
local-testflight-upload appstore-screenshot-pipeline acknowledgements-generation
asc-ops-handoff interactive-sim-ux-audit
```

---

> **Scope: this plan is PHASE 1** (extract → genericize → consume as submodule).
> Phase 2 (README-as-SSOT agenda · npm install path · aggregate other skill repos)
> and Phase 3 (survey high-star GitHub Swift skill repos → adopt/replace/skip) get
> their own spec+plan after Phase 1 lands. See spec §2a. Two Phase-2/3 feasibility
> items (npm mechanism; nested skill-repo aggregation) are flagged in spec §3.

## Task 0: ✅ DONE — GitHub repo created (user-approved, public)

Repo created 2026-06-24: **https://github.com/wei18/apple-dev-skills** (public,
empty). User explicitly approved ("do it, its public"). Remaining tasks push into
it.

---

## Task 1: Extract the 26 skills into the new repo (history-preserving)

**Files:**
- Create: `/Users/zw/GitHub/Wei18/apple-dev-skills/` (new working copy)

**Mechanism choice:** `git filter-repo` preserves per-skill commit history. If `git filter-repo` is not installed, installing it (`pipx install git-filter-repo`) is a new-tool install → **ask the user first**. If install is declined, use the **copy fallback** (Step 3-alt) — history stays intact in this repo's log, nothing is lost.

- [ ] **Step 1: Fresh mirror clone to scratch**

```bash
cd /tmp
rm -rf adk-extract && git clone /Users/zw/GitHub/Wei18/Sudoku-spec adk-extract
cd /tmp/adk-extract
```
Expected: a full clone with history.

- [ ] **Step 2: Verify git filter-repo availability**

Run: `git filter-repo --version`
Expected: a version string. If "git: 'filter-repo' is not a git command" → STOP, ask the user about `pipx install git-filter-repo`, or go to Step 3-alt.

- [ ] **Step 3: Filter to the 26 skill dirs and rename into `skills/` (filter-repo path)**

```bash
cd /tmp/adk-extract
git filter-repo --force \
  --path .claude/skills/swift6-concurrency/ \
  --path .claude/skills/apple-platform-targets/ \
  --path .claude/skills/swiftpm-modularization/ \
  --path .claude/skills/swift-testing-baseline/ \
  --path .claude/skills/xcode-cloud-single-track-ci/ \
  --path .claude/skills/mise-tool-management/ \
  --path .claude/skills/oslog-logger-defaults/ \
  --path .claude/skills/apple-three-piece-analytics/ \
  --path .claude/skills/telemetry-facade-pattern/ \
  --path .claude/skills/ai-translated-localization/ \
  --path .claude/skills/session-to-meeting-log/ \
  --path .claude/skills/methodology-pattern-extractor/ \
  --path .claude/skills/subagent-review-cycles/ \
  --path .claude/skills/spec-phase-orchestration/ \
  --path .claude/skills/backlog-routing-by-topic/ \
  --path .claude/skills/apple-public-repo-security/ \
  --path .claude/skills/leader-developer-handoff-contract/ \
  --path .claude/skills/agent-impl-notes-log/ \
  --path .claude/skills/pr-diff-verification/ \
  --path .claude/skills/subagent-conflict-detection/ \
  --path .claude/skills/swiftui-interaction-footguns/ \
  --path .claude/skills/build-time-secret-injection/ \
  --path .claude/skills/app-icon-rasterize/ \
  --path .claude/skills/ios-design-mockup/ \
  --path .claude/skills/app-store-review-rejections/ \
  --path .claude/skills/monetization-sdk-integration/ \
  --path-rename .claude/skills/:skills/
```
Expected: history rewritten; tree now has only `skills/<skill>/SKILL.md`.

- [ ] **Step 3-alt: Copy fallback (only if filter-repo unavailable + install declined)**

```bash
cd /tmp && rm -rf adk-extract && mkdir -p adk-extract/skills && cd adk-extract && git init -q
for s in swift6-concurrency apple-platform-targets swiftpm-modularization swift-testing-baseline xcode-cloud-single-track-ci mise-tool-management oslog-logger-defaults apple-three-piece-analytics telemetry-facade-pattern ai-translated-localization session-to-meeting-log methodology-pattern-extractor subagent-review-cycles spec-phase-orchestration backlog-routing-by-topic apple-public-repo-security leader-developer-handoff-contract agent-impl-notes-log pr-diff-verification subagent-conflict-detection swiftui-interaction-footguns build-time-secret-injection app-icon-rasterize ios-design-mockup app-store-review-rejections monetization-sdk-integration; do
  cp -R "/Users/zw/GitHub/Wei18/Sudoku-spec/.claude/skills/$s" "skills/$s"
done
```

- [ ] **Step 4: Verify exactly 26 skill dirs, no stragglers**

```bash
cd /tmp/adk-extract
ls skills | sort | wc -l            # expect 26
ls skills | grep -E 'game-factory-composition|mise-task-operations|cloudkit-schema-ops|local-testflight-upload|appstore-screenshot-pipeline|acknowledgements-generation|asc-ops-handoff|interactive-sim-ux-audit' && echo "LEAK: a stay-skill moved" || echo "ok: no stay-skill leaked"
test -f skills/swift6-concurrency/SKILL.md && echo "ok: depth correct"
```
Expected: `26`, `ok: no stay-skill leaked`, `ok: depth correct`.

- [ ] **Step 5: Point origin at the new repo and push**

```bash
cd /tmp/adk-extract
git remote remove origin 2>/dev/null
git remote add origin https://github.com/Wei18/apple-dev-skills.git
git branch -M main
git add -A && git commit --no-gpg-sign -F /tmp/adk-c0.txt -q   # message file written in Step 6
```

- [ ] **Step 6: Write the extraction commit message**

Write `/tmp/adk-c0.txt`:
```
chore: extract portable skills from Sudoku-spec

26 reusable Apple-platform / AI-agent-collaboration skills extracted from
Wei18/Sudoku-spec .claude/skills, relocated under skills/ for the
skills-directory plugin layout. Genericization follows in subsequent commits.
```
(If filter-repo path was used, the per-skill history is already present and this is just the relocation commit; if copy fallback, this is the initial commit.)

- [ ] **Step 7: Move the working copy into place**

```bash
rm -rf /Users/zw/GitHub/Wei18/apple-dev-skills
mv /tmp/adk-extract /Users/zw/GitHub/Wei18/apple-dev-skills
cd /Users/zw/GitHub/Wei18/apple-dev-skills
```

---

## Task 2: Scaffold the plugin manifest + READMEs

**Files:**
- Create: `/Users/zw/GitHub/Wei18/apple-dev-skills/.claude-plugin/plugin.json`
- Create: `/Users/zw/GitHub/Wei18/apple-dev-skills/README.md`
- Create: `/Users/zw/GitHub/Wei18/apple-dev-skills/README.zh-Hant.md`

- [ ] **Step 1: Write `.claude-plugin/plugin.json`**

```json
{
  "name": "apple-dev-skills",
  "version": "0.1.0",
  "description": "Reusable Claude Code skills for AI-agent-driven Apple-platform development — Swift 6 / SwiftPM / testing / CI / L10n / telemetry defaults plus Leader-Developer collaboration patterns.",
  "author": { "name": "Wei18" }
}
```
Note: `name` becomes the skill namespace prefix (`apple-dev-skills:<skill>`). The default skills path is `skills/` at plugin root — no extra config needed.

- [ ] **Step 2: Write `README.md`** (index of the 26, grouped: Platform defaults / Process & collaboration / Ops & review). Reuse the one-liners from `Sudoku-spec/.claude/skills/README.md` for the moved rows; add a top section explaining this is a skills-directory plugin consumable via submodule, and how to add it to another repo:
```markdown
git submodule add https://github.com/Wei18/apple-dev-skills.git .claude/skills/apple-dev-skills
```

- [ ] **Step 3: Write `README.zh-Hant.md`** (mirror, reuse zh-Hant one-liners from this repo's README.zh-Hant.md).

- [ ] **Step 4: Commit**

```bash
cd /Users/zw/GitHub/Wei18/apple-dev-skills
git add .claude-plugin README.md README.zh-Hant.md
git commit --no-gpg-sign -F /tmp/adk-c1.txt -q   # "chore: add plugin manifest + index READMEs"
```

---

## Task 3: Genericize the 26 skills (commits in the new repo)

**Principle (spec §6):** strip hard dependencies that wouldn't exist in another project (repo-specific `mise run <task>` names, `Packages/...` module paths, app names that imply a fixed product); KEEP concrete lessons but reframe them as labelled examples ("real-world example: …"); demote `#NNN` issue refs to "(from a real project)" flavor, never a live link.

Most of the 26 are already project-neutral. The grep-derived inventory below lists the ones that actually carry repo-isms. Work them in order; commit per skill (or per small batch).

- [ ] **Step 1: `telemetry-facade-pattern` (light)** — two `#579` refs (in "Wiring traps" + checklist). Replace `#579` with `(real-project example)` / drop the bare number. Keep the GameCenterSink/DeferredSink lesson verbatim — it is the value.

Run after: `grep -nE '#[0-9]{2,4}|Sudoku' skills/telemetry-facade-pattern/SKILL.md` → expect no matches.

- [ ] **Step 2: `ai-translated-localization` (moderate)** — in the "scan:l10n gate scope" section: replace `mise run scan:l10n` with "your repo's L10n completeness gate"; drop `#575/#577/#594/#598` and `GameAppKit` specifics, reframing as "when a game/app adopts a shared-UI capability, its catalog can ship missing keys". Keep the two-blind-spots lesson + xcstrings text-splice footgun.

Run after: `grep -nE '#[0-9]{2,4}|mise run|GameAppKit' skills/ai-translated-localization/SKILL.md` → expect no matches.

- [ ] **Step 3: `monetization-sdk-integration` (HEAVY)** — pervasive `Packages/AppMonetizationKit/Sources/AdsAdMob/...` paths, `Sudoku`/`Minesweeper`/`SudokuUI`, and issue refs (#109/#441/#443/#101/#106/#136). Rewrite paths to neutral placeholders: `Packages/<Monetization>/Sources/<AdsBridge>/LiveAdMobBridge.swift` and "your monetization target". Reframe the AdMob-isolation gate as a general rule ("exactly one file may `import GoogleMobileAds`"). Demote all issue refs. This is the most repo-bound mover — budget the most time.

Run after: `grep -nE 'Sudoku|Minesweeper|AppMonetizationKit|#[0-9]{2,4}' skills/monetization-sdk-integration/SKILL.md` → expect no matches (the AdMob isolation rule may keep the bridge filename as an example, that's fine).

- [ ] **Step 4: `swiftui-interaction-footguns` (moderate)** — `SudokuUI` path in the description/frontmatter + many issue refs (#15/#540/#529/#531/#536/#520/#523). Replace `Sources/.../SudokuUI/` trigger with "any `*View*.swift` / your UI target"; demote issue refs to flavor. Keep every footgun — they are the value.

Run after: `grep -nE 'SudokuUI|Sudoku|#[0-9]{2,4}' skills/swiftui-interaction-footguns/SKILL.md` → expect no matches.

- [ ] **Step 5: Sweep the remaining 22 for stragglers**

```bash
cd /Users/zw/GitHub/Wei18/apple-dev-skills
grep -rlnE 'Sudoku|Minesweeper|Tiles2048|Packages/[A-Z]|mise run [a-z]|#[0-9]{2,4}' skills/ || echo "ALL CLEAN"
```
Expected: `ALL CLEAN` (or a short list to fix with the same principle). Note: `backlog-routing-by-topic` references `design.md`/`foundations.md`/`plan.md`/`methodology.md` — those are the portable spec-phase file convention (`spec-phase-orchestration`), keep them. `apple-public-repo-security` may name generic tool names (gitleaks/lefthook) — keep.

- [ ] **Step 6: Fix any `Related skills` refs that pointed at a STAY skill**

```bash
grep -rlnE 'game-factory-composition|mise-task-operations|cloudkit-schema-ops|local-testflight-upload|appstore-screenshot-pipeline|acknowledgements-generation|asc-ops-handoff|interactive-sim-ux-audit' skills/
```
For any hit (a generic skill should not depend on a project-bound one), drop that Related-skills line. Expected after fix: no hits.

- [ ] **Step 7: Commit the genericize pass**

```bash
git add skills && git commit --no-gpg-sign -F /tmp/adk-c2.txt -q   # "docs: genericize skills (strip repo-specific paths / tasks / issue refs)"
```

- [ ] **Step 8: Push the new repo**

```bash
git push -u origin main
```
Expected: branch `main` on `Wei18/apple-dev-skills`.

---

## Task 4: SMOKE-TEST GATE — verify plugin discovery (spec §3 unconfirmed item)

**This needs a Claude Code restart, which the USER performs. The agent cannot restart itself mid-session.**

- [ ] **Step 1: Mount the submodule locally in this repo (temporary, to test)**

```bash
cd /Users/zw/GitHub/Wei18/Sudoku-spec
git submodule add https://github.com/Wei18/apple-dev-skills.git .claude/skills/apple-dev-skills
```
Expected: `.gitmodules` gains a second entry; submodule checked out.

- [ ] **Step 2: USER restarts Claude Code, then confirms discovery**

Ask the user to restart and report whether skills appear as `apple-dev-skills:swift6-concurrency` (etc.) in the available-skills list.
- **PASS** → proceed to Task 5.
- **FAIL** (skills don't appear) → the bare-submodule auto-load did not work. Apply the documented fallback: add a local marketplace entry pointing at `.claude/skills/apple-dev-skills` (per Claude Code plugins-reference "skills-directory plugins" / local marketplace). Re-test. Only proceed once skills resolve.

---

## Task 5: Slim this repo — remove moved flat skills, keep the submodule, rewrite refs

**Files:**
- Delete: the 26 flat dirs under `Sudoku-spec/.claude/skills/`
- Modify: `Sudoku-spec/.claude/skills/README.md`, `README.zh-Hant.md`
- Modify: stay-skills whose `Related skills` reference a moved skill (now namespaced)

- [ ] **Step 1: Remove the 26 flat skill dirs**

```bash
cd /Users/zw/GitHub/Wei18/Sudoku-spec
for s in swift6-concurrency apple-platform-targets swiftpm-modularization swift-testing-baseline xcode-cloud-single-track-ci mise-tool-management oslog-logger-defaults apple-three-piece-analytics telemetry-facade-pattern ai-translated-localization session-to-meeting-log methodology-pattern-extractor subagent-review-cycles spec-phase-orchestration backlog-routing-by-topic apple-public-repo-security leader-developer-handoff-contract agent-impl-notes-log pr-diff-verification subagent-conflict-detection swiftui-interaction-footguns build-time-secret-injection app-icon-rasterize ios-design-mockup app-store-review-rejections monetization-sdk-integration; do
  git rm -r ".claude/skills/$s"
done
```
Expected: 26 dirs staged for deletion.

- [ ] **Step 2: Verify only the 8 stay-skills + the submodule remain**

```bash
ls .claude/skills | grep -v '^README' 
```
Expected: exactly `apple-dev-skills` (submodule) + the 8 stay skills.

- [ ] **Step 3: Rewrite this repo's READMEs** — replace the three skill tables with: (a) one table of the 8 stay skills, (b) a pointer section "Portable skills live in the `apple-dev-skills` submodule (namespace `apple-dev-skills:`) — see `.claude/skills/apple-dev-skills/README.md`", mirroring the existing superpowers-submodule note. Update the section counts.

- [ ] **Step 4: Rewrite stay→moved cross-refs to the namespaced form**

```bash
grep -rln -E 'telemetry-facade-pattern|swift-testing-baseline|swiftpm-modularization|ai-translated-localization|mise-tool-management|apple-public-repo-security|monetization-sdk-integration|build-time-secret-injection|xcode-cloud-single-track-ci' .claude/skills/game-factory-composition .claude/skills/mise-task-operations .claude/skills/cloudkit-schema-ops .claude/skills/local-testflight-upload .claude/skills/appstore-screenshot-pipeline .claude/skills/acknowledgements-generation .claude/skills/asc-ops-handoff .claude/skills/interactive-sim-ux-audit
```
For each hit, prefix the referenced moved-skill name with `apple-dev-skills:` (in prose "Related skills" lists and `mise-task-operations`'s `[[...]]` "Deeper skill" column). Leave stay→stay refs unchanged.

- [ ] **Step 5: Verify no dangling reference to a now-removed flat skill**

```bash
# any bare (un-namespaced, non-submodule) ref to a moved skill name left in a stay skill?
grep -rnE '\[\[(telemetry-facade-pattern|swift-testing-baseline|swiftpm-modularization|ai-translated-localization|mise-tool-management|apple-public-repo-security|monetization-sdk-integration|build-time-secret-injection|xcode-cloud-single-track-ci)\]\]' .claude/skills/*/SKILL.md && echo "FIX: un-namespaced ref remains" || echo "ok"
```
Expected: `ok`.

- [ ] **Step 6: Commit on a branch**

```bash
git switch -c chore/extract-portable-skills-to-submodule
git add -A
git commit --no-gpg-sign -F /tmp/adk-c3.txt -q
```
Message `/tmp/adk-c3.txt`:
```
chore(skills): move 26 portable skills to apple-dev-skills submodule

Portable Apple-platform / collaboration skills now live in the
apple-dev-skills skills-directory plugin (namespace apple-dev-skills:),
mounted as a submodule at .claude/skills/apple-dev-skills. Only the 8
project-bound skills remain flat. READMEs slimmed; stay->moved cross-refs
namespaced. No runtime change.
```

---

## Task 6: PR, CI, merge, sync

- [ ] **Step 1: Verify the diff matches intent**

```bash
cd /Users/zw/GitHub/Wei18/Sudoku-spec
git show --stat HEAD | head -40   # 26 deletions + .gitmodules + READMEs + ref edits
git diff --cached --check          # no whitespace/conflict markers
```

- [ ] **Step 2: Push + open PR**

```bash
git push -u origin chore/extract-portable-skills-to-submodule
gh pr create --title "chore(skills): extract 26 portable skills to apple-dev-skills submodule" --body-file /tmp/adk-pr.md
```
PR body `/tmp/adk-pr.md`: summarize the move, link the spec, note "depends on Wei18/apple-dev-skills being pushed (done in Task 3)", flag that this is the >50-LOC doc change implementing an approved spec.

- [ ] **Step 3: Watch CI**

```bash
sleep 20; gh pr checks <PR#>
```
Expected: L10n / Markdown-link / SwiftLint / PR-title all pass. **Note:** the Markdown link checker (lychee) may follow links into the submodule — if it flags submodule-internal links, scope it or accept per existing config. The submodule add must not break `tuist generate` (skills are not build inputs) or `swift test` (unaffected).

- [ ] **Step 4: Merge + sync (when green)**

```bash
gh pr merge <PR#> --squash --delete-branch
git fetch origin -q && git switch main -q && git reset --hard origin/main
git submodule update --init --recursive
git status --short   # clean
```

- [ ] **Step 5: Pin the submodule to a tagged release (optional hardening)**

In `apple-dev-skills`: `git tag v0.1.0 && git push --tags`. In this repo: `cd .claude/skills/apple-dev-skills && git checkout v0.1.0`, then commit the submodule pointer bump. Mirrors how `superpowers` is pinned to `v5.1.0`.

---

## Task 7: Update memory + meeting log

- [ ] **Step 1: Memory** — add a `project` memory `apple-dev-skills-submodule` (the portable skills now live in the submodule, namespace `apple-dev-skills:`, source of truth is `Wei18/apple-dev-skills`; the 8 stay-skills + the move/stay boundary). Update `MEMORY.md` index. Optionally delete the now-skill-superseded `reference/mise-macos-only-tools-need-os-guard` and `reference/snapshot-gate-strict-content-tolerant-board` memories (content folded into the moved skills) — confirm with user before deleting.

- [ ] **Step 2: Meeting log** — `meetings/2026-06-24_apple-dev-skills-extraction.md` via the `session-to-meeting-log` skill: goal, the discovery-mechanics finding, the move/stay classification, the genericize pass, the submodule wiring, and the smoke-test result.

---

## Self-review notes (author)

- **Spec coverage:** §4 topology → Tasks 1-2,5; §5 classification → the canonical lists + Task 3/5 verifications; §6 genericize → Task 3; §7 cross-refs → Task 3.6 + 5.4; §8 mechanics → Tasks 1,5,6; §3 smoke-test → Task 4; §9 non-goals respected (no marketplace publish unless Task 4 forces fallback). All covered.
- **User-owned gates:** Task 0 (repo create) and Task 4 Step 2 (restart + discovery confirm) are the only non-agent steps — both flagged.
- **Reversibility:** nothing destructive in this repo until Task 5, which is on a branch + PR; the new repo is additive.
