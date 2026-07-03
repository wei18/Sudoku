# SDD-006 — New-Game Scaffold: one-command bootstrap for game N

**Status:** DRAFT (2026-06-29) — planning #479. The scaffold *form* is the central
open question (§5); everything else is firm enough to review.
**Date:** 2026-06-29
**Author:** AI Leader (planning session with the user)
**Tracks:** epic #479 (new-game scaffold). **Builds on:** SDD-005 (platform
convergence, COMPLETE — the prerequisite), north-star memory
`goal-many-small-games-platform`, mirror principle.

> **UPDATE 2026-06-29 — Tiles2048 removed; template source is now Minesweeper.**
> This RFC was drafted while Tiles2048 (SDD-004) existed as the "canonical clean
> shape". Later the same day the user removed Tiles2048 to keep MS + Sudoku the
> focus (SDD-004 abandoned, #501 closed). **Wherever this doc said "2048" / "from
> 2048" as the template source, it now says "Minesweeper"** — MS is the cleanest
> shipped 2-game mirror to template from (Sudoku is the older reference with the
> most bespoke surface). The §2 conformance audit below is a **two-game**
> (Sudoku + Minesweeper) check; both are conformant after #640.
>
> **UPDATE 2026-07-03 (audit #631) — body line-edited.** §2/§3/§5/§7's 2048
> references were renamed to Minesweeper-keyed equivalents using the repo's real
> identifiers (`cloudkit/minesweeper.ckdb`, `com.wei18.minesweeper`,
> `iCloud.com.wei18.minesweeper`). One collapse to note: 2048 carried two
> distinct name tokens — `Game2048` (Swift module prefix) and `Tiles2048`
> (App-Store-facing name / app-target / bundle-id prefix), because its display
> name diverged from its module prefix. Minesweeper uses one name for both, so
> the §5 rename map now has a single token (`Minesweeper`) where 2048 needed two.
> The generator itself is still PENDING (§5 form undecided) — this update is a
> documentation rename only, no design change.

---

## 1. Goal

Make "add a new game" collapse from hand-copying ~30 files to **one command that
stamps a compiling, runnable skeleton game wired into the whole platform** — so the
only work left is the gameplay itself + the user-owned launch gates.

SDD-005 already shrank the per-game surface to "one `GameConfig` + engine + board +
tokens". This epic removes the remaining friction: the *boilerplate around* that
surface (packages, App shell, CloudKit DB, Project.swift wiring, L10n shells, test
dirs) is mechanical and identical every time — it should be generated, not retyped.

**Non-goal:** generating gameplay. The scaffold produces a trivial **placeholder
game** (e.g. tap-to-win) so the platform wiring compiles and ships; the developer
then replaces the three gameplay pieces.

---

## 2. Current state — what "add game 4" costs today

Per-game footprint, using **Minesweeper as the canonical template** (SDD-005 §Pillar A):

| Layer | Per-game artifacts | Generatable? |
|---|---|---|
| **Core rules** | `<Game>CoreKit`: `<Game>GameState/` (Session·Snapshot·Status) + `<Game>Engine/` (Board·Move·Daily·Direction + RNG/Clock reexports) | skeleton yes; **rules manual** |
| **Kit** | `<Game>Kit`: `<Game>AppComposition` (Live·LiveRouteFactory·AppComposition) · `<Game>Persistence` · `<Game>UI` | composition/persistence **templated**; board UI/tokens manual |
| **App shell** | `App/<Game>/`: Info.plist · entitlements · license_plist.yml · `<Game>App.swift` · Resources (Localizable/InfoPlist `.xcstrings` 7-locale shells · PrivacyInfo · Assets) | **almost fully generated** |
| **Infra** | `cloudkit/<game>.ckdb` · `Project.swift` app target + 2 schemes (`<Game>` + `<Game>-E2E`) · ASCRegister GC config | ckdb/Project.swift **generated**; CK/ASC *deploy* = user-owned gate |
| **Secrets** | AdMob app/banner IDs · ASC app id · CK container | **manual** (memory + `secrets/.env`) |

**Existing tooling:** only `mise-tasks/new_app/provisioning` (renders a provisioning
HTML). There is **no code generator** today.

What SDD-005 already bought us: composition is `makeGameApp(config:)` everywhere;
Home / DailyHub skeleton / board-redirect / GC dashboard / ResumePill / ATT /
Settings are all shared and render from `GameConfig`. So the generated
`<Game>AppComposition` is a thin, near-identical mirror of Minesweeper's — exactly
the kind of boilerplate a scaffold should own.

### Conformance of the three existing games (audit 2026-06-29)

Before templating game N, the two shipped games must agree on the shape the
template copies. Audited Sudoku / Minesweeper against the canonical structure
(Minesweeper = the clean shape to template from; the original audit also covered
Tiles2048, now removed):

| Dimension | Sudoku | Minesweeper | Verdict |
|---|---|---|---|
| `<Game>CoreKit` (`Engine` + `GameState`) | ✓ | ✓ | conformant |
| `<Game>Kit` (`AppComposition`/`Persistence`/`UI`) | ✓ (+`KitTesting`) | ✓ | conformant (Sudoku's extra test-support target is benign) |
| Composition = `makeGameApp` / `GameConfig` | ✓ | ✓ | conformant |
| **`LiveRouteFactory` location** | `SudokuAppComposition/LiveRouteFactory.swift` | `MinesweeperAppComposition/LiveRouteFactory.swift` | ✓ (Sudoku's UI→composition move resolved #640) |
| App shell core (Info.plist · entitlements · license_plist · xcstrings×2 · PrivacyInfo · `App.swift`) | ✓ | ✓ | conformant |
| `cloudkit/<game>.ckdb` | ✓ | ✓ | conformant |
| Project.swift app target + schemes (incl. `<App>-E2E`) | ✓ | ✓ | conformant |
| Preview.swift / Audio / `.storekit` / `.xctestplan` | ✓ | ✓ | conformant |

The only drift the original three-game audit found — Sudoku's `LiveRouteFactory`
living in the **UI** module instead of the **composition** module — was resolved in
**#640 (#639)**: its Daily/leaderboard statics moved to `SudokuLeaderboardRouting`
(SudokuUI) and the factory now lives in `SudokuAppComposition/LiveRouteFactory.swift`.
Both games now place it identically.

**Scaffold implication:** the template follows Minesweeper's shape — `LiveRouteFactory`
in `<Game>AppComposition`, UI module composition-free, the full App-shell + ckdb +
E2E-scheme set present. With #640 landed there is no per-game exception to template
around.

---

## 3. What the scaffold generates vs. what stays manual

**Generated (mechanical, identical every time):**
1. `Packages/<Game>CoreKit` + `Packages/<Game>Kit` — Package.swift + target dirs +
   placeholder gameplay (a minimal engine/session/board that compiles & wins).
2. `App/<Game>/` — Info.plist (with `$(…)` AdMob substitution wiring, no real IDs),
   entitlements (per-game iCloud container id), PrivacyInfo, `<Game>App.swift`,
   `license_plist.yml`, `Localizable.xcstrings` + `InfoPlist.xcstrings` (7-locale
   shells seeded from the shared keys), `Assets.xcassets` placeholder AppIcon.
3. `cloudkit/<game>.ckdb` — SavedGame record-type template (mirror of `minesweeper.ckdb`).
4. `Project.swift` — append the app target + `<Game>` and `<Game>-E2E` schemes.
5. Test scaffolds — `<Game>E2ETests` dir, `ConfigConsistencyTests`, resume
   round-trip test stubs, an empty snapshot baseline dir.
6. A generated `NEXT-STEPS.md` listing the manual + user-owned follow-ups.

**Manual (gameplay — the point):**
- `<Game>CoreKit` real rules (engine/session/daily).
- `<Game>UI` board view + cell tokens.
- `GameConfig` values (title, tints, audio prefix, home-mode copy, routes).

**User-owned gates (scaffold emits templates + a checklist, never executes):**
- CloudKit schema **deploy** to Dev/Prod (Console button — see hard-gates).
- ASC app record + GC leaderboards/achievements (ASCRegister, user-run).
- Real AdMob / ASC / CK-container IDs (memory + `secrets/.env`; never in code).

---

## 4. Placeholder-gameplay strategy (the load-bearing idea)

A scaffold that leaves `<Game>CoreKit` empty produces a non-compiling tree — useless.
Instead it stamps a **trivial but real game**: a 1-cell "tap to win" board over a real
`GameSession`/snapshot, a deterministic daily seed, one difficulty. This makes the
generated app **build, launch, play to completion, save/resume, and pass its E2E
smoke** on day one — proving every platform seam is wired *before* any gameplay is
written. Replacing gameplay is then a localized swap of the three manual pieces, each
already compiling against the shared protocols.

This also gives us the #510-Phase-3 win→completion E2E **for free** on the new game
(the placeholder is, by construction, one tap from winning).

---

## 5. **[OQ-1] Scaffold form — the central open question**

Two viable shapes; the user deferred the choice to this RFC.

**Option A — `mise run new_game:scaffold <Name>` (bash generator).** Recommended.
Stamps the file tree from a committed `templates/new-game/` set (or from Minesweeper
as the live template), `sed`-renames `Minesweeper` → `<Name>`, swaps in placeholder
gameplay, appends the `Project.swift` target+schemes, seeds the L10n shells. Consistent
with the repo's mise-tasks-for-everything posture; one command, reproducible, reviewable.
- *Risks:* `sed`-rename across a live template is brittle (catches substrings); a
  committed `templates/` set drifts from Minesweeper unless gated. Mitigation: a
  `scan:` check that diffs the template against Minesweeper's shape, or generate *from*
  Minesweeper at run time with an explicit rename map.

**Option B — documented checklist + copy Minesweeper.** A `docs/new-game-checklist.md` +
a "copy `Packages/Minesweeper*`, rename, blank gameplay" runbook. Lower build cost, but
every new game repeats manual `cp`/`sed`/edit steps — exactly the friction this epic
exists to kill. Not recommended as the primary deliverable (keep it as the fallback doc).

**Leaning:** A, with the template sourced **from Minesweeper at run time** (no committed
template copy to drift), driven by an explicit token map (`Minesweeper`→`<Name>`,
`minesweeper`→`<name>`, `com.wei18.minesweeper`→`com.wei18.<name>`,
`iCloud.com.wei18.minesweeper`→`iCloud.com.wei18.<name>`). Unlike 2048 — which needed two
separate tokens (`Game2048` module prefix vs `Tiles2048` app/bundle-id prefix) because
its display name diverged from its module prefix — Minesweeper uses one name for both,
so the map collapses to a single token. The gameplay files are then overwritten with the
placeholder set rather than copied.

---

## 6. Phasing

- **PR1 — generator core + compiling skeleton.** `new_game:scaffold` produces the
  packages + `App/<Game>/` + `Project.swift` wiring + placeholder gameplay; success
  criterion = `tuist generate && swift build` + the new app's E2E smoke green.
- **PR2 — infra templates.** `cloudkit/<game>.ckdb` + `ck:schema --app <name>` param
  verify; ASCRegister GC config template; `NEXT-STEPS.md` user-owned checklist.
- **PR3 — parameterization audit.** Confirm `tf:upload` / `store:screenshots` /
  `gen:acknowledgements` / `scan:l10n` already accept the new app name (the epic says
  "verify"); fix any hard-coded `sudoku|minesweeper|tiles2048` enumerations found.
- **PR4 (optional) — monetization slot.** Banner-slot assembly + Remove-Ads IAP wiring,
  pending the SDD-003 Epic-5 ScreenContainer banner shape.

---

## 7. Acceptance criteria

- `mise run new_game:scaffold <Name>` produces a tree that **`tuist generate &&
  swift build` clean** and whose `<Name>-E2E` launch + win→completion smoke is green,
  with zero hand-editing.
- The generated `<Game>AppComposition` diffs to ~empty against Minesweeper's (only
  `GameConfig` values + names differ) — i.e. it inherits SDD-005's convergence.
- No real AdMob/ASC/CK IDs anywhere in generated files (only `$()` substitution +
  placeholders); `scan:secrets` / `scan:hygiene` pass.
- `NEXT-STEPS.md` lists every manual + user-owned gate with the owning skill.
- The 9-item #479 checklist is either generated or explicitly listed as user-owned.

---

## 8. C4 empirical proof — deferred (user decision 2026-06-29)

SDD-005 C4 ("new game = one GameConfig + engine/board/tokens") is *structurally* met
but unproven. The user chose to **ship the generator + docs without standing up a real
game 4 now** — C4 gets its empirical proof when an actual 4th game is added. The
generator's own placeholder-skeleton build/E2E smoke (run during development, not
merged) is the interim evidence that the wiring holds.

---

## 9. Open questions

- **[OQ-1]** Scaffold form (§5) — A (mise generator, recommended) vs B (checklist).
- **[OQ-2]** Template source — generate from Minesweeper at run time (no drift,
  recommended) vs a committed `templates/new-game/` set (explicit but drifts).
- **[OQ-3]** Rename safety — `sed` token map vs a small Swift/script renamer that's
  word-boundary aware (avoid `Game2048`-substring false hits).
- **[OQ-4]** Does the placeholder game ship a real `Assets.xcassets` AppIcon, or a
  1×1 stub the developer must replace (and a `scan:` reminder)?
- **[OQ-5]** Should PR3's parameterization audit be folded into PR1 (so the very first
  generated game exercises `tf:upload` etc.) or kept separate?

---

*Drafted 2026-06-29 while closing out SDD-005 (#634/#635/#636 E2E + #637 dead-field).
Next: user picks the §5 form + §9 OQs, then this becomes the #479 implementation roadmap.*
