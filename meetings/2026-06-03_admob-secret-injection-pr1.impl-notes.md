# AdMob secret-injection PR1 — impl notes

Date: 2026-06-03
Scope: Migrate AdMob App ID + banner unit ID from committed source into
build-time xcconfig (`Tuist/AdMob.xcconfig`) injected via Info.plist
substitution. Plus tooling secrets baseline (`secrets/.env.example`).

## Decisions

- **Single xcconfig file** `Tuist/AdMob.xcconfig` wired at the project level
  (both Debug + Release `.configurations`), mirroring `Tuist/Signing.xcconfig`.
  Both Sudoku + Minesweeper targets pick up the same `$(ADMOB_APP_ID)` /
  `$(ADMOB_BANNER_UNIT_ID)` substitutions from the same file. Per-target
  override is unnecessary because we generate the xcconfig fresh per build
  (locally one app at a time, XCC writes app-specific values per workflow).
  - Trade considered: per-target xcconfig (`Tuist/AdMob-Sudoku.xcconfig` +
    `Tuist/AdMob-Minesweeper.xcconfig`). Rejected — XCC workflows are
    per-app anyway, so they'd each set `ADMOB_APP_ID` to the right value
    via env var. Local dev: developer fills only the app they're testing.
  - Note for Leader: this means a local dev cannot run BOTH apps with
    distinct real prod IDs simultaneously — but they shouldn't need to
    (local dev uses sandbox IDs from the .example anyway).

- **`GADBannerUnitID` custom Info.plist key** invented for this PR. Apple
  doesn't reserve the namespace; Google reads `GADApplicationIdentifier`
  itself but the banner unit is our app's data. Documented as our key in
  the Info.plist comment.

- **`fatalError` removed**, replaced by an Info.plist-key-existence test
  (smoke test in AppCompositionTests). Catches misconfig at test time
  (pre-archive) rather than runtime first-launch. Test reads the App
  target's Info.plist (NOT a test bundle copy) by parsing
  `Sudoku/Info.plist` via `#filePath` walk… wait — Xcode Cloud test runner
  doesn't have the source tree. **Adjusted approach**: copy Info.plist as
  a test resource (renamed `.json` to dodge plist compiler? no — plist
  parser handles XML directly). Use `.copy("Resources/Info.plist")`
  pattern, treat as plain `Data`, parse with `PropertyListSerialization`.

  Actually — re-reading PrivacyManifestTests: it copies `PrivacyInfo.xcprivacy`
  via testTarget resources and reads via `Bundle.module.url(...)`. Same
  pattern works here. Info.plist as committed has `$(ADMOB_APP_ID)`
  substitution literals — parsing it raw at test time would see the literal
  string `$(ADMOB_APP_ID)`. That's fine: the test asserts the KEY EXISTS
  and the VALUE STRING IS NON-EMPTY. It does NOT assert the value is a real
  AdMob ID — that's a runtime concern handled by AdMob SDK itself.

  **Implication**: the test passes even on a fresh clone without
  `AdMob.xcconfig` present, because the Info.plist source file always has
  the `$(...)` substitution string. Test value: catches accidental deletion
  of the keys, not misconfiguration. That's the same guarantee the old
  `fatalError` had (you couldn't accidentally delete it without crashing
  build), so it's a parity-grade replacement.

- **Sudoku byte-identicality**: Sudoku's current state ships sandbox IDs
  in Info.plist + DEBUG-gated sandbox banner unit in Live.swift + Release
  fatalError. After PR1: Info.plist substitutes from xcconfig (sandbox
  values in dev, real values from XCC env var), Live.swift reads banner
  unit from Info.plist key. Identical runtime behavior for the shipping
  scenarios (DEBUG dev → sandbox, Release with proper XCC → real IDs).
  The misconfigured-Release path differs: was runtime fatalError on app
  launch; now is empty string at runtime (since `Bundle.main.object(...)
  as! String` force-unwraps a literal `$(ADMOB_BANNER_UNIT_ID)` if the
  xcconfig was absent — Xcode leaves the substitution unresolved, but
  the string IS non-nil non-empty, just garbage). The test gate catches
  this pre-archive instead.

  Wait — that's only true if the xcconfig file is missing. If the
  xcconfig is PRESENT but the value is the literal `YOUR_APP_ID_HERE`
  template placeholder, the Info.plist gets that string verbatim and
  the SDK crashes. That's fine: it crashes loudly the same way the old
  fatalError did, just at a slightly different call site (SDK init vs
  composition root). Documented as known trade.

- **`secrets/` directory** new convention. Gitignored except `*.example`
  + optional `README.md`. The `.env.example` carries the docstring
  inline (no separate README — keeps surface small).

## Open questions for Leader / CR

- Should the smoke test live in AppCompositionTests (Sudoku) and
  MinesweeperUITests (MS), or carve a new dedicated test target?
  Current call: keep in existing tests, no new targets.
- For Minesweeper: the existing MinesweeperUITests target doesn't have a
  `resources:` block. Need to add one + copy Minesweeper/Info.plist. CR
  should sanity check the package layout change.
- Tuist xcconfig pattern wiring: project-level vs target-level. Going
  project-level (mirrors Signing); both target's Info.plist substitution
  variables resolve from project base config. Should work — verify in
  manual smoke test (Leader-owned).
