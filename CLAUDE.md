# CLAUDE.md — agent operating guide

## Status

- Two games, **Sudoku** and **Minesweeper**, share one codebase and one store version (2.6.0).
- Neither app is on the App Store. Distribution is TestFlight only. The 2.6.0 submissions were withdrawn (`DEVELOPER_REJECTED`); v2.6 is still the first release target.
- There are no live users and no revenue. Do not treat a bug as a production incident.

## Mirror principle

The two apps differ only in gameplay screens and resources. Layout, navigation, buttons and source code are one shared implementation.

- When Minesweeper needs something Sudoku has, extract a shared parameterized target (as `GameAppKit`, `GameShellKit` and `SettingsKit` do). Never copy and adapt: cross-app drift has always come from hand-written per-app wrappers (#448).
- Verify every change to shared code in both apps.
- When unsure, read the Sudoku implementation of the same surface first. It is the reference shape.

## Architecture

```
leaf cores (Foundation-only, portable):  SudokuCoreKit · MinesweeperCoreKit · TimeKit · DeterminismKit
seams (restricted framework imports):    PersistenceKit(CloudKit) · GameCenterKit(GameKit) · RemindersKit(UserNotifications)
                                         GameAudioKit(AVFoundation) · AppMonetizationKit(AdMob/StoreKit) · TelemetryKit(OSLog)
shared UI (GameShellKit = zero deps):    GameShellUI · SettingsUI(SettingsKit)
shared composition (deps allowed):       GameAppKit — GameConfig · makeGameApp · GameRoot · ResumePill
apps (thin shells):                      SudokuKit · MinesweeperKit  →  App/Sudoku · App/Minesweeper (Tuist-generated)
tooling:                                 ASCRegisterKit (standalone CLI; does not depend on the cores)
test support (never in app products):    GameTestSupportKit
```

- `GameShellKit` has zero dependencies. Code that needs Persistence, Game Center or Telemetry goes in `GameAppKit`.
- Resume is game-agnostic: `ResumeCandidate<Route>` plus an injected `fetchResume` closure. Persistence stays per game; do not force Minesweeper onto the Sudoku-typed `SavedGameSummary`.
- `SplitMix64` drives puzzle and board generation. The frozen seed vectors must not change.
- CloudKit resolution stays lazy (`PrivateCKGatewayFactory`). Tests that build `.live()` run without entitlements, and an eager `CKContainer.default()` crashes them.

## Roles

- **Leader**: the session the user talks to. It plans, dispatches, reviews and reports. **Developer**: a subagent that implements one dispatched task. If you were dispatched, you are a Developer.
- The Leader dispatches implementation. It edits directly only for docs, a one-line fix, when the user says so, or when subagent file writes are denied.
- Dispatch coding with `model: "sonnet"` and mechanical edits with `model: "haiku"`. Before the first dispatch of a session, run one haiku write test: some harness versions deny subagent file writes.
- Dispatch brief, review rounds and repo-specific Leader rules: `docs/methodology.md`.
- Code review: follow the global engineering rules. Repo addition: when a diff touches a high-risk path, name it in the reviewer brief. High-risk paths: `*Persistence`, `*AppComposition`, `GameCenterClient`, `AppMonetizationKit` (`MonetizationCore`, `AdsAdMob`, `IAPStoreKit2`), `Project.swift`, `Package.swift`, `PrivacyInfo.xcprivacy`.
- Issues labeled `audit` come from Upkeep, the daily AI repo audit (`.github/workflows/audit.yml`). Post a triage comment before fixing anything: many findings repeat tracked items or accepted won't-fixes.

## Commands

```bash
mise tasks ls                                              # every ops task; check here before hand-rolling a command
swift test --package-path Packages/<Kit>                   # one package; use a repo-relative path (cd does not persist)
swift test --package-path Packages/<Kit> --filter <Suite>  # one suite
swift test --package-path Packages/GameCenterKit --no-parallel   # this package can hang in parallel mode
mise run tuist:generate                                    # resolve packages, generate Game.xcworkspace, do not open Xcode
mise run scan:l10n                                         # 7 locales complete + test fixtures in sync
mise run scan:design_contracts                             # screen-contract anchors still resolve
```

- In a new worktree, run `mise trust` before the first commit; without it the pre-commit hooks fail open. Before an app build, run `mise run worktree:seed <path>` from the main checkout to copy the gitignored xcconfig and secrets.
- If a `swift test` run crashes or hangs, do not start a second run. Stop the stuck `swiftpm-testing-helper`, re-run suite by suite with `--filter`, and report the substitution.
- Trust `swift test`, not SourceKit: "no such module" diagnostics after an edit are usually stale.
- `swift build` skips test targets, and macOS `swift test` skips `#if os(iOS)` code. After changing a shared protocol requirement, run `swift test` on every package with a conformer, and build iOS-only conformers from the package directory with `xcodebuild -scheme <Target> -destination 'generic/platform=iOS Simulator' build`.
- Snapshot baselines are committed. A failing snapshot means behavior changed: investigate, never re-record to pass. A fully blank snapshot means the `AssetCatalogCompiler` plugin is missing from the target's `plugins:`.

## What CI covers

GitHub Actions (`.github/workflows/lint.yml`) runs on every PR: PR title, markdown links in `docs/` and `meetings/`, SwiftLint `--strict` on changed files, `scan:l10n`, `scan:settings_root`, `scan:store_frame_drift`, `scan:store_baseline_orphans`, `scan:design_contracts`.

CI builds nothing and runs no tests (owner decision, recorded on #1039). This overrides the global engineering rules for "Build and test on CI":

- Run `swift test` locally for every package you changed, and report the result with its output.
- `mise run test:ui` (host-driven XCUITest) is on demand. Run it when the user or the task brief asks. This overrides the global rule against local `xcodebuild test` for that task only.

## Change procedure

1. Write the test first, then the code (`docs/methodology.md`).
2. Run `swift test` for each package you changed and `mise run lint:swift_strict -- <changed .swift files>`. If you touched user-visible strings, run `mise run scan:l10n`.
3. Get the diff reviewed as the global engineering rules say.
4. Open the PR. The title follows Conventional Commits and its subject starts with a lowercase letter or a digit (`^[a-z0-9]`); CI checks it.
5. Never put `close`, `fix` or `resolve` next to `#NNN` in a PR title, PR body or commit message unless the PR must close that issue. GitHub ignores "does not". Write "part of #NNN".
6. Merge rules (CI green, squash): `CONTRIBUTING.md`.
7. After a merge from a worktree, run `git fetch && git reset --hard origin/main` in the main checkout and confirm it is clean. Worktree index changes can leak into it.

## Hard gates (user-owned: prepare, never run unprompted)

- TestFlight upload: `mise run tf:upload <app> <platform> --i-am-sure`. See the `local-testflight-upload` skill.
- CloudKit Production schema: promotion is the CloudKit Console button only. `cloudkit/*.ckdb` is the source of truth. Production fields and indexes are add-only. See the `cloudkit-schema-ops` skill.
- App Store Connect submission, IAP pricing, signing: see the `asc-ops-handoff` skill.
- Production AdMob and ASC identifiers never appear in code, comments, docs or PR diffs. They live in `secrets/.env` and the gitignored `Tuist/*.xcconfig`, and reach the app through `$(…)` substitution.

## Conventions

- Commit with `git commit --no-gpg-sign -F <msgfile>`: signing hangs and hooks block heredocs. End the body with the `Co-Authored-By: Claude …` trailer.
- SwiftLint runs `--strict` in CI. A file over 400 lines fails: extract a sibling file (`Live+Feature.swift`). One-character names fail; use names of three or more characters. `TODO` comments fail: open an issue instead.
- Swift 6 strict concurrency and `InternalImportsByDefault` apply everywhere. New shared types are `Sendable`. A `@Sendable` closure cannot capture MainActor statics: mark test fixtures `nonisolated`.
- The app-root bootstrap (`GameRoot`, `makeGameApp`) uses `.onAppear { Task { … } }`, not `.task`: `.task` there broke the arm64 device Release link (#361). `.task` is correct in leaf views (#607).
- A deliberate difference between the two apps carries a code comment with the reason and issue number at both the present site and the absent site, for example `// Sudoku-only: <reason> (#NNN)`.
- User-visible strings need all 7 locales (`apple-dev-skills:ai-translated-localization`). Regenerate test fixtures with `mise run gen:l10n_fixture` and `mise run gen:privacy_fixture`; never hand-edit them.

## Where truth lives

| What | Where |
|---|---|
| Index of all docs, with status | `docs/README.md` |
| Current UI design (3.0) | `docs/designs/v3/design.md` |
| Per-screen behavior and navigation | `docs/screen-contracts.md` · `docs/navigation-flows.md` |
| Gate that ties the design to those contracts | `mise run scan:design_contracts` (`scripts/design/contracts.py`) |
| App Store submission steps | `docs/app-store/SUBMISSION-CHECKLIST.md` |
| Engineering platform decisions | `docs/foundations.md` |
| Ops tasks and release pipelines | `mise tasks ls` · `.claude/skills/mise-task-operations` |
| Skills | `.claude/skills/README.md` (project skills, plus the `apple-dev-skills` submodule that provides `apple-dev-skills:` and `collaboration-skills:`) |
| Collaboration rules | `docs/methodology.md` |
| Past decisions and their reasons | `meetings/*.md` · `docs/v1/` · `docs/v2/` · `docs/superpowers/specs/` (historical records) |

## Glossary

- **3.0 / v3**: the current UI design generation (3-tab shell, Liquid Glass). Not a store version.
- **v2.6 / 2.6.0**: the store version both apps will ship first.
- **SDD-NNN**: a numbered platform design spec in `docs/superpowers/specs/`.
- **ASC**: App Store Connect. **XCC**: Xcode Cloud. **GC**: Game Center. **MS**: Minesweeper.
- **Seam**: a protocol boundary that keeps an Apple or third-party framework inside one package.
