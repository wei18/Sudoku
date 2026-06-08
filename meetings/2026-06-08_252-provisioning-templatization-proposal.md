# Proposal — #252 templatize provisioning walkthroughs

Status: PROPOSAL_DRAFT (Developer → Leader for discussion). Not implemented.

## TL;DR recommendation

**Option C-refined (templates + mise renderer), with a thin Option-D skill deferred to "when app #3 lands".**

Build a `mise run new-app:provisioning` task that renders three parameterized
HTML templates to `~/GitHub/Wei18/tmp/`. This mirrors the existing
`mise-tasks/ck/schema` / `mise-tasks/store/screenshots` precedent almost
exactly (same `--app` dispatch, same `container_for()` lookup, same
"public IDs OK in code, secrets only via `secrets/.env`" rule). It is fully
subagent-implementable — no `.claude/` writes required. Defer the umbrella
skill (Option B/D wrapper) until there is a concrete app #3, because a skill
adds a Leader-only file with little marginal value over a one-line
`mise run` the Leader can already invoke.

Timing: **after MS v1 ships** (the issue's own "Out of scope" / "When" note).
Not urgent; this is amortization tooling, not a release blocker.

---

## (a) Current-state finding

### Source HTMLs — readable, outside repo
All three live at `~/GitHub/Wei18/tmp/` and are readable:
- `minesweeper-asc-provisioning.html` (10.4 KB) — Apple Developer App ID + iCloud Container + ASC app record + Remove-Ads IAP shell. 4 steps.
- `minesweeper-admob-registration.html` (10.2 KB) — AdMob app + Banner Ad Unit ID. 5 steps + "paste IDs back to Claude" box.
- `sudoku-cloudkit-production-deploy.html` (9.2 KB) — CloudKit Dev→Prod schema deploy. 5 steps. (Note: this one is Sudoku-themed; the other two are Minesweeper-themed.)
- (`minesweeper-icon-preview.html` also present — unrelated, ignore.)

These are **not tracked in this repo** and `tmp/` is not in `.gitignore` (it's simply outside the worktree). They are pure local scratch artifacts.

### Structure observation (the key reusability fact)
All three share a **byte-identical ~150-line CSS `<style>` block** (`:root` light/dark vars, `.step`, `.step-num`, `.field-row`, `.warn`, `.ok-note`, `.done-banner`, `.url-badge`). The AdMob one adds an `.id-box`/`.id-box-input` paste widget; the CloudKit one adds `.danger`/`.diagram`. Bodies differ entirely. So the natural split is **one shared shell + three body fragments**, not three independent files.

### Hardcoded parameters found (the substitution surface)
| Param | ASC HTML | AdMob HTML | CloudKit HTML |
|---|---|---|---|
| App name | `Minesweeper` | `Minesweeper` | `Sudoku` |
| Bundle ID | `com.wei18.minesweeper` | — | — |
| Container ID | `iCloud.com.wei18.minesweeper` | — | `iCloud.com.wei18.sudoku` (+ warns against `...minesweeper`) |
| IAP product ID | `com.wei18.minesweeper.iap.remove_ads` | — | — |
| Live composition type | — | `MinesweeperAppComposition.Live` | — |
| Record types | — | — | `SavedGame`, `PersonalRecord`, `MonetizationState` |

Important: **none of these are secrets.** Bundle IDs, container IDs, and IAP product IDs are already public (they live in `*.entitlements`, `Project.swift`, `Config.swift`). The actual secrets (AdMob App ID / Banner Unit ID values, ASC `.p8`, `CK_MANAGEMENT_TOKEN`) are *not in the HTMLs* — the HTMLs only tell the user where to obtain them and paste them back. So the renderer needs **no secret access at all**; it only substitutes public identifiers. This is consistent with `build-time-secret-injection` and `apple-public-repo-security`: the production AdMob ID values stay in memory files / `secrets/.env`, never in a committed template.

### Existing tooling that this should mirror
- `mise-tasks/ck/schema` — `--app sudoku|minesweeper` arg parsing, `container_for()` case lookup, `REPO_ROOT="$(git rev-parse --show-toplevel)"`, secrets via `source secrets/.env`, `#MISE description=...` header. **This is the exact pattern to copy.**
- `mise-tasks/store/screenshots` — same dispatch shape, also references the "scriptable-ops precedent set by `mise-tasks/ck/schema`".
- No existing provisioning skill in `.claude/skills/` (grep confirmed — closest are `asc-ops-handoff`, `build-time-secret-injection`, `monetization-sdk-integration`, all *guidance* skills, not renderers).
- No existing `new-app` / provisioning mise-task.
- `.claude/templates/` **does not exist**.

### Recent restructure — must reflect current layout
Apps now live under `App/{Sudoku,Minesweeper}/`; metadata under `docs/app-store/metadata/{sudoku,minesweeper}/`. The templates' *content* references paths like `Config.swift`, `MinesweeperAppComposition.Live`, `Info.plist` — these should be updated to current locations where the body text names a file (e.g. `App/Minesweeper/.../Info.plist`). The renderer itself anchors on `REPO_ROOT` so it is layout-agnostic.

---

## (b) Recommended option + why

### Why C-refined over A / B / D

| Option | Verdict | Reason |
|---|---|---|
| **A** — 3 skills (one per topic) | Reject | Each skill is a `.claude/` file (Leader-only to write). Three of them. A skill's value is *agent-invokable judgment*; these walkthroughs are *deterministic string substitution* — no judgment needed. Over-engineered. |
| **B** — 1 umbrella skill | Reject (for now) | Still a `.claude/` file. The "orchestrate 3 in sequence" value is real but small — the Leader can already chain three `mise run` calls. Premature. |
| **C** — templates + mise renderer | **Recommend** | Exactly mirrors `ck/schema` precedent. Fully subagent-buildable (no `.claude/` write). Renderer is ~60 lines of bash; templates are the existing HTMLs minus hardcoded values. Single source of truth for the shared CSS shell. |
| **D** — C + umbrella skill | Recommend the *C half now*, the skill *later* | The skill becomes worthwhile once app #3 exists and the Leader wants a single `Skill` entry point that also answers follow-ups. Until then it's a Leader-only file with no payload C doesn't already give. |

Refinement over vanilla C: **deduplicate the CSS shell.** Vanilla C would keep three full `*.html.tmpl` files (re-copying 150 identical CSS lines x3). Instead: one `_shell.html.tmpl` (CSS + `{{TITLE}}` + `{{SUBTITLE}}` + `{{BODY}}` slots) + three `*.body.html.tmpl` fragments. The renderer composes shell+body+params. This kills the "edit CSS in one file, forget the other two" drift the issue worries about.

### Reusability / pattern fit
The "Sudoku → Minesweeper → ???" pattern is real and already encoded elsewhere via `--app sudoku|minesweeper` dispatch (ck/schema, store/screenshots, the `container_for()` map). Adding `new-app:provisioning --app <name>` extends a pattern the codebase already commits to, rather than inventing a new surface. When app #3 arrives, you add one `case` line to `container_for()`-equivalent + supply its name/bundle/product IDs as flags.

---

## (c) Concrete spec (for the implementer)

### File layout (all under repo — subagent-doable)
```
mise-tasks/
  new_app/
    provisioning            # bash renderer; #MISE description=...
templates/
  provisioning/
    _shell.html.tmpl        # shared CSS + {{TITLE}} {{SUBTITLE}} {{BODY}} slots
    asc.body.html.tmpl      # ASC App ID + container + app record + IAP (4 steps)
    admob.body.html.tmpl    # AdMob app + banner unit (5 steps)
    cloudkit.body.html.tmpl # Dev→Prod schema deploy (5 steps)
```
Note: put templates at **repo-root `templates/`**, NOT `.claude/templates/`. The
issue's Option C said `.claude/templates/`, but `.claude/` is Leader-only/
sandbox-blocked AND these templates carry no agent-only semantics — they are
ordinary build inputs like `cloudkit/*.ckdb`. Repo-root `templates/` keeps the
whole thing subagent-ownable and version-controlled like the rest of `mise-tasks`.
(If the Leader prefers `.claude/templates/` for discoverability, that single
move becomes the only Leader-only step — see part (d).)

### Param interface
```
mise run new_app:provisioning <topic> --app <name> \
    [--bundle-id <id>] [--container-id <id>] [--product-id <id>] \
    [--live-composition <Type>] [--out <dir>] [--open]

topic   : asc | admob | cloudkit | all
--app   : sudoku | minesweeper | <new>   (drives defaults via a known-apps map)
--out   : default ~/GitHub/Wei18/tmp
--open  : `open` the rendered file(s) in the browser after render
```
For known apps, the bundle/container/product defaults come from a `case "$APP"`
map in the task (same shape as `ck/schema`'s `container_for()`), so the common
call is just `mise run new_app:provisioning all --app minesweeper`. For a brand-
new app not yet in the map, the user passes `--bundle-id` etc. explicitly (and
ideally adds a `case` line in the same PR).

### Substitution mechanism
Plain `sed` placeholder replacement (no new dependency — matches the
"no CLI trial-and-error / use what's installed" convention):
```
render() {  # $1=body-template $2=title $3=subtitle  → stdout
  body=$(sed -e "s/{{APP_NAME}}/$APP_NAME/g" \
             -e "s#{{BUNDLE_ID}}#$BUNDLE_ID#g" \
             -e "s#{{CONTAINER_ID}}#$CONTAINER_ID#g" \
             -e "s#{{PRODUCT_ID}}#$PRODUCT_ID#g" \
             -e "s/{{LIVE_COMPOSITION}}/$LIVE_COMPOSITION/g" "$1")
  sed -e "s/{{TITLE}}/$2/g" -e "s/{{SUBTITLE}}/$3/g" \
      -e "/{{BODY}}/r /dev/stdin" -e "/{{BODY}}/d" "$SHELL_TMPL" <<<"$body"
}
```
(Use `#` as sed delimiter for values containing `/` like `iCloud.com...`. Final
impl can swap to an awk one-shot if multiline body injection via sed proves
fiddly — but no templating engine / npm dep should be introduced.)

### Template authoring
Take the three existing HTMLs verbatim, then:
1. Hoist the shared `<style>`+`<head>`+`<body>` chrome into `_shell.html.tmpl` with `{{TITLE}}`/`{{SUBTITLE}}`/`{{BODY}}` slots. (AdMob's extra `.id-box` CSS and CloudKit's `.danger`/`.diagram` CSS: either merge all three supersets into the shared shell — they're additive and harmless — or keep per-topic `<style>` appends in the body fragment. Recommend **merge into shell**: one stylesheet, ~15 extra lines, zero drift risk.)
2. Replace every hardcoded `Minesweeper`/`Sudoku` → `{{APP_NAME}}`, `com.wei18.minesweeper` → `{{BUNDLE_ID}}`, `iCloud.com.wei18.*` → `{{CONTAINER_ID}}`, `com.wei18.minesweeper.iap.remove_ads` → `{{PRODUCT_ID}}`, `MinesweeperAppComposition.Live` → `{{LIVE_COMPOSITION}}`.
3. Update body file-path references to current layout (`App/<App>/.../Info.plist`, `Config.swift` location).
4. The CloudKit body's record-type list (`SavedGame`/`PersonalRecord`/`MonetizationState`) is app-shared, keep literal.

### Verification criteria (Goal-Driven)
- `mise run new_app:provisioning all --app minesweeper --out /tmp/prov-test` renders 3 HTMLs; `diff` of the rendered ASC/AdMob files against the originals (modulo intentional path-updates) shows only equivalent content — i.e. **a byte-for-byte semantic match proving the parameterization didn't lose content.**
- Rendering `--app sudoku` swaps name/container/product correctly (grep the output for `com.wei18.sudoku`, assert no stray `minesweeper`).
- No secret values appear in any template file (`mise run scan:secrets` / gitleaks clean — cross-ref `apple-public-repo-security`).
- Task `--help` prints usage; unknown topic/app errors non-zero (match `ck/schema` ergonomics).

---

## (d) Leader-only vs subagent-doable split

| Part | Owner | Why |
|---|---|---|
| `mise-tasks/new_app/provisioning` (renderer) | **Subagent** | Ordinary repo file, mirrors `ck/schema`. |
| `templates/provisioning/*.tmpl` (at repo root) | **Subagent** | Ordinary build inputs; no `.claude/` semantics. |
| Verification run + diff against originals | **Subagent** | Pure CLI. |
| *(If chosen)* moving templates under `.claude/templates/` | **Leader** | `.claude/` is sandbox-blocked for subagents. |
| *(If chosen, deferred)* umbrella skill `new-game-app-provisioning/SKILL.md` | **Leader** | `.claude/skills/` is Leader-write-only. |

So with the **recommended repo-root `templates/` placement, the entire task is subagent-doable in one PR** — zero Leader-only steps. The Leader-only items only appear if the user insists on `.claude/` placement or wants the skill wrapper now.

---

## (e) Open questions for the user

1. **Template location**: repo-root `templates/provisioning/` (subagent-doable, recommended) vs `.claude/templates/provisioning/` (matches issue's Option C wording but makes it Leader-only)? Recommend repo-root.
2. **Skill wrapper now or later?** Recommend defer the umbrella skill until app #3 is concretely planned. Confirm OK to ship C-only first.
3. **Timing**: now, or after MS v1 ships? The issue itself flags this as amortization, not a blocker. Recommend after MS v1.
4. **CSS shell merge**: OK to merge all three CSS supersets into one shared `_shell.html.tmpl` (one stylesheet, kills drift) vs keeping per-topic CSS appends? Recommend merge.
5. **Output dir**: keep default `~/GitHub/Wei18/tmp/` (outside repo, matches today's habit) — confirm that's still where you want rendered walkthroughs to land.
6. **Sudoku ASC/AdMob templates**: today only Minesweeper has ASC+AdMob HTMLs and only Sudoku has the CloudKit one. After templatization all three topics render for any `--app`. Confirm that's the intent (i.e. you want a future `--app <new>` to get all three), vs keeping CloudKit Sudoku-specific.
