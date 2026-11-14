---
name: mise-task-operations
description: Index of this repo's `mise run` tasks - build, test, scan, lint, generate, screenshots, TestFlight upload, CloudKit schema, App Store Connect preflight. Use before running or writing any ops command, before searching the repo for "how is X done", and when adding a new ops script. Each row gives the invocation, whether the task is safe or user-gated, and the skill with the details. Not a tutorial on mise itself (see apple-dev-skills:mise-tool-management).
---

# mise Task Operations

Most ops pipelines in this repo already exist as a `mise` task. Check this index before you write a command by hand.

- `mise tasks ls` prints the live list. When it differs from this file, `mise tasks ls` is right; update this file in the same PR.
- Task bodies are files under `mise-tasks/` (`mise-tasks/lint/swift` is the task `lint:swift`). `mise run <task> --help` prints usage.

Safety column: **safe** means the task changes only local, regenerable or git-tracked files. **gated** means a step writes to a live service and needs the user's go-ahead.

## Build and test

| Task | What it does | Safety | Details |
|---|---|---|---|
| `mise run tuist:generate [--open] [--no-install]` | `gen:settings_root`, `tuist install`, `tuist generate --no-open` → `Game.xcworkspace` | safe | `game-factory-composition` |
| `mise run worktree:seed <path>` | Copy the gitignored files listed in `.worktreeinclude` (`Tuist/*.xcconfig`, `secrets/`) into a worktree. Run from the main checkout | safe | — |
| `mise run test:ui [<app>] [--udid u] [--no-generate]` | Host-driven XCUITest end-to-end suites (`<App>-E2E` schemes). Not run by CI | safe; runs `xcodebuild test` on a simulator | `apple-dev-skills:host-driven-xcuitest-e2e` |
| `mise run ui:tour [--app <app>] [--udid u] [--no-build]` | Build a Debug simulator app, open every screen in light and dark, save screenshots to `build/tour/` | safe; pass `--udid` of your own simulator | `interactive-sim-ux-audit` |
| `mise run new_game:scaffold <Name>` | Create a compiling skeleton for a new game by copying Minesweeper | safe; refuses an existing destination | `game-factory-composition` |

Unit and snapshot tests are plain SwiftPM: `swift test --package-path Packages/<Kit>` (see `CLAUDE.md` §Commands).

## Gates (read-only checks)

| Task | Fails when | In CI |
|---|---|---|
| `mise run scan:l10n` | A catalog has a `<TRANSLATE>` marker, a stale entry or a key missing one of the 7 locales; a shared dotted key is missing from an app catalog; a test fixture differs from the shipping file | yes |
| `mise run scan:settings_root` | A per-app `Settings.bundle/Root.plist` differs from `App/Shared/Settings.bundle/Root.plist` | yes |
| `mise run scan:design_contracts` | A row in `scripts/design/contracts.py` points at a section missing from `docs/screen-contracts.md` or `docs/navigation-flows.md` | yes |
| `mise run scan:store_frame_drift [--base <ref>\|--list]` | A baseline or capture that feeds a store frame changed without regenerating every frame it feeds | yes |
| `mise run scan:store_baseline_orphans` | A baseline mapped to a store slot is missing or no test records it | yes |
| `mise run test:store_frame_drift` | The self-test of the drift gate fails | yes |
| `mise run lint:swift_strict [files]` | SwiftLint reports any warning | yes (changed files) |
| `mise run lint:swift [files]` | Never: warn-only | pre-commit |
| `mise run scan:secrets` | gitleaks finds a secret in staged files | pre-commit |
| `mise run scan:hygiene` | A secret-shaped file (`.p8`, `.p12`, `.pem`, `.env`) or an unfilled doc placeholder is staged | pre-commit |
| `mise run scan:admob` | A file other than `LiveAdMobBridge.swift` imports `GoogleMobileAds` | no |
| `mise run verify:audio` | A gameplay sound key has no bundled audio file | no |

Details for the l10n gate: `apple-dev-skills:ai-translated-localization`. For the store gates: `appstore-screenshot-pipeline`.

## Generate

| Task | What it does | Safety | Details |
|---|---|---|---|
| `mise run gen:acknowledgements [--config-path …]` | Regenerate the `Settings.bundle` license page | safe; output gitignored | `acknowledgements-generation` |
| `mise run gen:settings_root` | Copy the shared `Root.plist` into both apps (also run by `tuist:generate`) | safe; output tracked | — |
| `mise run gen:l10n_fixture` | Regenerate the l10n test fixture from the Sudoku catalog | safe | `apple-dev-skills:ai-translated-localization` |
| `mise run gen:privacy_fixture` | Regenerate the PrivacyInfo test fixture from the shipping manifest | safe | — |

## Release and store

| Task | What it does | Safety | Details |
|---|---|---|---|
| `mise run tf:upload <app\|all> <ios\|macos\|all> [--archive-only\|--i-am-sure]` | Archive, export, upload to TestFlight | archive and export safe; upload **gated** by `--i-am-sure` | `local-testflight-upload` |
| `mise run preflight:submission <app\|all> <ios\|macos\|all> [--fix]` | Check App Store Connect submission prerequisites | read-only; `--fix` writes copyright, release type and build attachment only | `asc-ops-handoff` |
| `mise run ck:schema <export\|validate\|deploy> --app <app> [--env e]` | Export, validate or deploy the CloudKit schema to Development | Development safe; Production is a Console step, **user-owned** | `cloudkit-schema-ops` |
| `mise run store:capture [--app a] [--device d] [--verify]` | Capture the `03-board` store source from a live simulator | safe; builds and boots its own simulators | `appstore-screenshot-pipeline` |
| `mise run store:screenshots build-ascspec [--verify-only]` | Build the App Store Connect screenshot frames | safe; needs macOS fonts and Pillow | `appstore-screenshot-pipeline` |
| `mise run store:screenshots <list\|sync\|clean> [--app <app>]` | Maintain the preview links to snapshot baselines | safe; preview only, never uploaded | `appstore-screenshot-pipeline` |
| `mise run new_app:provisioning <asc\|admob\|cloudkit\|all> --app <name>` | Render a provisioning walkthrough as HTML (public IDs only) | safe | `asc-ops-handoff` |

## Watching a PR

`mise run watch:pr <number> [interval-seconds]` prints one line when the PR is merged, closed, conflicted or has a failing check, then exits (0 only on merge). It is read-only.

## Xcode Cloud scripts

- `ci_scripts/ci_post_clone.sh`: installs mise tools, writes the `Tuist/*.xcconfig` files from workflow secrets, regenerates acknowledgements.
- `ci_scripts/ci_pre_xcodebuild.sh`: pre-build hook.

Details: `apple-dev-skills:xcode-cloud-single-track-ci`.

## Conventions for every ops task

- Secrets come from `secrets/.env` (gitignored). Never pass them as arguments and never print them. See `apple-dev-skills:build-time-secret-injection`.
- A step that writes to a live service is user-owned: the TestFlight upload, the CloudKit Production deploy, any `ASCRegister … apply` or `--i-am-sure`.
- Tool versions are pinned in `.mise.toml`, shared by local runs and CI.
- A new ops script goes in `mise-tasks/<group>/<name>` with a `#MISE description=` header and `set -euo pipefail`, and gets a row here.
