# AdMob Secret Injection — Architect Review

**Date**: 2026-06-03
**Reviewer**: Software Architect (subagent)
**Subject**: Leader's proposed `~/.config/wei18-secrets/admob.env` + xcconfig + Info.plist `$()` substitution design for AdMob production identifier injection

## Headline verdict

**NEEDS_REVISIONS** — directionally sound but contains two load-bearing wrong assumptions plus several architectural smells. Specifically: (A) shell-exported env vars do NOT automatically populate xcconfig `$()` interpolation in vanilla `xcodebuild`, and (F) Xcode Cloud's "Environment Variable" UI propagates to the build environment as process env vars — they reach `xcodebuild` invocation env but xcconfig `$(VAR)` expansion resolves against the **build settings table**, not arbitrary process env. The plan conflates two distinct namespaces. A build-phase script generating a Swift constant is materially safer and simpler. Tuist regeneration will clobber unmanaged per-config xcconfig references unless they're declared in `Project.swift`. The project already has a working precedent (`ci_post_clone.sh` writes `Tuist/Signing.xcconfig` from `$CI_TEAM_ID`) that the proposal ignores.

## Critical holes

1. **[ASSUMPTION — wrong] Shell env does not feed xcconfig `$(VAR)` interpolation.** xcconfig variable references resolve against the build settings table populated from: (a) xcconfig files in the inheritance chain, (b) build settings defined in project/target, (c) settings passed on `xcodebuild` command line as `VAR=value` positional arguments (NOT exported shell env). A `source admob.env && xcodebuild archive` does NOT make `$SUDOKU_ADMOB_APP_ID` visible to `$(SUDOKU_ADMOB_APP_ID)` in `Release.xcconfig`. The only ways to inject from shell are `xcodebuild SUDOKU_ADMOB_APP_ID="$SUDOKU_ADMOB_APP_ID"` (positional) or `-xcconfig /path/to/override.xcconfig`. Process env vars *do* show up in Run Script build phases via `$VAR`, but that is a different mechanism from xcconfig interpolation.

2. **[ASSUMPTION — wrong] Xcode Cloud "Environment Variables" do not directly populate xcconfig interpolation either.** XCC's environment variables (including Secret ones) are exposed as process env to `ci_*.sh` hooks and to the `xcodebuild` *process*, not as build settings. For XCC to land the values in `$(SUDOKU_ADMOB_APP_ID)`, you need a `ci_pre_xcodebuild.sh` or `ci_post_clone.sh` that writes a generated `AdMob.xcconfig` from the env, or writes a generated `AdMobConfig.swift`. The current `ci_pre_xcodebuild.sh` is a stub — perfect place to do this, and it mirrors the established `ci_post_clone.sh` pattern that already writes `Tuist/Signing.xcconfig` from `$CI_TEAM_ID`.

3. **[EVIDENCE — verified] Tuist will clobber un-declared xcconfig references.** `Project.swift:116-122` only declares `.debug(... xcconfig: "Tuist/Signing.xcconfig")` / `.release(... xcconfig: "Tuist/Signing.xcconfig")` at the **project level**, and both configurations point at the same file. There is no per-target / per-config xcconfig wiring today. If you drop `Sudoku/Configurations/Debug.xcconfig` and `Sudoku/Configurations/Release.xcconfig` into the filesystem without referencing them in `Project.swift`, `tuist generate` will not include them and the next regeneration wipes any manual Xcode UI fix. The plan must amend `sudokuTarget` and `minesweeperTarget` `settings:` to use `.settings(base:, configurations: [.debug(name:"Debug", xcconfig:...), .release(name:"Release", xcconfig:...)])` — and reconcile with the existing project-level xcconfig (Signing) since target xcconfig inheritance order matters (target overrides project).

4. **[ASSUMPTION — partial] Info.plist `$(VAR)` substitution requires `INFOPLIST_PREPROCESS` or the modern Info.plist build settings flow.** `$(EXECUTABLE_NAME)` etc. work because they are *system-defined build settings*. Arbitrary user variables work **only if** they are present in the build settings table at Info.plist processing time. With the corrected design (per-config xcconfig declaring `ADMOB_APP_ID`), this works. With the broken design (relying on shell env), it does not — unset Info.plist variables resolve to the literal string `$(VAR)`, not empty.

5. **[ARCHITECTURE] Using Info.plist as a config storage layer for app code is an antipattern when a compile-time Swift constant is trivially achievable.** `GADBannerUnitID` is your own invented key. App code reads it via `Bundle.main.object(forInfoDictionaryKey:)` from inside a SwiftPM package — and `Bundle.main` semantics inside a package consumed by an app, while it returns the App bundle at runtime, has well-known gotchas under #Preview / unit test host / SwiftUI Preview / multi-bundle Mac Catalyst. You also lose compile-time guarantees (force-unwrap `as! String` will crash, not refuse to build). The build-phase generated Swift file gives you: compile-time check, no runtime Bundle dance, trivially testable, Info.plist stays semantic (only Apple-defined keys), symmetric handling of `GADApplicationIdentifier` and the banner unit.

## Important concerns

6. **Two Tuist-generated app targets share one Info.plist substitution path** — if Minesweeper's xcconfig ever leaks into the Sudoku target inheritance, you cross-contaminate. Cleaner: use the same unprefixed `ADMOB_APP_ID` / `ADMOB_BANNER_UNIT_ID` key in *both* targets' xcconfigs, and let the shell/CI env feed them via target-distinguished file paths or a CI script that picks the right env var per target.

7. **`fatalError` belt-and-suspenders should stay** at least one release cycle past the xcconfig migration. Keep it until you've verified prod archives twice (one TestFlight, one App Store release) that the new path works.

8. **Explicit `secrets/` placement: outside repo or inside.** Proposal puts `admob.env` at `~/.config/...` — outside the tree, safe. If user prefers `<repo>/secrets/` (inside tree, gitignored), document explicit deny-list strategy.

9. **gitleaks coverage gap.** `.gitleaks.toml` should detect the AdMob account ID prefix `ca-app-pub-` followed by a digit pattern that is NOT `3940256099942544` (Google's test prefix). Otherwise a paste into a comment slips through.

10. **Bundle.main behavior in tests** — if any unit test code path triggers `LiveAppComposition` construction, `Bundle.main` is the test host bundle, not the app bundle, and the Info.plist key is absent → force-unwrap crash. Build-phase Swift constant avoids this entirely.

11. **Package tests don't see Info.plist at all.** If Live.swift gets exercised by a package-level test (even via mock), the build-phase constant approach degrades gracefully (constant compiled in); the Info.plist-Bundle approach forces a fake bundle injection.

## Alternative designs considered

| Option | Pros | Cons | Safety |
|---|---|---|---|
| **A. Proposed (xcconfig + Info.plist `$()` + Bundle.main read)** | Apple-native, no codegen | Two wrong assumptions; runtime crash mode; Tuist gen friction; antipattern Info.plist key | Medium-low |
| **B. Build-phase script generates `AdMobConfig.swift`** | Compile-time constant; no Bundle dance; trivial tests; symmetric Sudoku+Minesweeper handling; works the same locally + XCC; mirrors `Signing.xcconfig` precedent | Adds 1 build phase per app target; codegen file gitignored | **High** |
| **C. CI-only patching (`sed -i` on Info.plist + Live.swift in `ci_pre_xcodebuild.sh`)** | Dev machines never see real IDs | Mutates committed sources during build; release builds depend on regex | Low |
| **D. `Tuist/AdMob.xcconfig` written by `ci_post_clone.sh` from XCC env (mirrors existing Signing pattern) + Info.plist `$(VAR)` substitution** | Reuses verified project precedent; one mechanism for all secrets; correct namespace for xcconfig interpolation; Tuist-aware because referenced in `Project.swift` | Still uses Info.plist as config carrier | **High** |
| **E. Hybrid: option D for `GADApplicationIdentifier` (Info.plist is the right home — SDK reads it) + option B for banner unit ID (app code reads it)** | Each value lives where it belongs semantically; compile-time safety for code-side; SDK gets what it expects | Two mechanisms to learn | **Highest** |

## Recommended (Option E)

1. **`GADApplicationIdentifier` (Info.plist) — via xcconfig generated by CI script + local stub:** `Tuist/AdMob.xcconfig` gitignored, generated by `ci_post_clone.sh` from XCC env vars + local mise task from `~/.config/wei18-secrets/admob.env`. `Tuist/AdMob.xcconfig.example` committed with sandbox fallback values. `Project.swift` adds target-level setting hook so xcconfig is wired per Tuist API.

2. **Banner unit ID (app code) — via build-phase codegen:** build phase script reads `${SUDOKU_ADMOB_BANNER_UNIT_ID}` (provided by xcconfig → propagated as env to script phases) and writes `Derived/AdMobConfig.swift` containing `enum AdMobConfig { static let bannerUnitID = "..." }`. File gitignored, added to target sources via Tuist `sources:` glob. App code consumes the constant directly — no Bundle.main, no force unwrap, no Info.plist key invented.

3. **Keep `fatalError` gate one release past the migration** as defense in depth.

4. **Update `.gitleaks.toml`** with a `ca-app-pub-[0-9]{16}~[0-9]+` rule excluding `3940256099942544`.

## Migration plan (Architect's original 7 PRs)

| PR | Scope |
|---|---|
| 1 | `Tuist/AdMob.xcconfig.example` + `.gitignore` entry + `Project.swift` per-target xcconfig wiring + `ci_post_clone.sh` writes generated xcconfig from XCC env (with test-ID fallback) |
| 2 | Swap Info.plist `GADApplicationIdentifier` to `$(SUDOKU_ADMOB_APP_ID)` / `$(MINESWEEPER_ADMOB_APP_ID)` |
| 3 | Build-phase codegen for `AdMobConfig.swift`; rewire `Live.swift` to read constant; keep `#if DEBUG` fallback |
| 4 | Update `.gitleaks.toml` rule |
| 5 | Real prod XCC env vars set via XCC UI; first TestFlight build; verify AdMob console shows test impressions |
| 6 | After two successful prod releases, remove `fatalError` gate |
| 7 | ADR + `docs/foundations.md §7` update |

## Open questions for Leader

1. Single Tuist xcconfig file or two? Currently `Tuist/Signing.xcconfig` is shared by both apps + both configs. Adding AdMob into the same file (one `Tuist/Secrets.xcconfig`) reduces moving parts but couples concerns. Recommend separate (`Signing.xcconfig`, `AdMob.xcconfig`) for clarity.
2. Are XCC Secret env vars available at `ci_post_clone.sh` time, or only `ci_pre_xcodebuild.sh`? The existing script reads `$CI_TEAM_ID` (a built-in, not user-defined Secret) — not a confirming precedent.
3. Banner unit ID via xcconfig + Info.plist (so SDK semantics + app-code semantics share one mechanism) vs split (option E)?
4. Migration timing vs v2.5.3 / MS v1 release windows?
5. Worktree / Tuist regen interaction with the new xcconfig — does `tuist generate` invoked from `ci_post_clone.sh` happen *after* the xcconfig is written? Reading the script: yes (line 24-34 writes xcconfig, line 41-42 runs `tuist generate`).

## Leader's downstream decisions

User chose simplified path (Option A with revisions) over Architect's Option E:
- Banner Unit ID via Info.plist `$()` + `Bundle.main` read (Architect cautioned against; Leader accepted Bundle.main flakiness as small risk at our scale)
- Dropped build-phase codegen step (1 fewer PR; lost compile-time safety)
- Kept xcconfig + Info.plist + ci_post_clone.sh CI generation
- Removed `secrets/.env` middle layer in favor of `Tuist/AdMob.xcconfig` directly mirroring `Signing.xcconfig` precedent
- 7-PR migration compressed to ~3 PR (PR1 covered Architect stages 1-3 combined)

Trade rationale: smaller scope, mirror existing precedent, accept marginal safety loss. Architect's primary safety net (build-phase codegen) replaced by smoke-test + runtime guard combination.

## Reference files

- `Project.swift` lines 116-122 (current Signing wiring)
- `Tuist/Signing.xcconfig.example` (existing precedent)
- `ci_scripts/ci_post_clone.sh` lines 24-34 (Signing xcconfig generation)
- `ci_scripts/ci_pre_xcodebuild.sh` (currently stub; not used by Leader's path)
- `Sudoku/Info.plist` + `Minesweeper/Info.plist`
- `Packages/SudokuKit/Sources/AppComposition/Live.swift`
- `Packages/MinesweeperKit/Sources/MinesweeperAppComposition/Live.swift`
- `.gitignore`
- `.gitleaks.toml`
