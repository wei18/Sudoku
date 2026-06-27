---
name: mise-task-operations
description: Index + entry point for EVERY repo ops / build / release task. Before running or hand-rolling any infra command (TestFlight upload, CloudKit schema, screenshots, acknowledgements, l10n gate, secret scan, lint, provisioning) — or before grepping the repo to "find how X is done" — consult this: the pipeline is almost always already a `mise run <task>`. Lists each task with its invocation, safety gate, and the deeper owning skill. Invoke when asked to build / archive / upload / deploy / scan / lint / generate / provision anything, or when wiring a new ops script.
---

# mise Task Operations (ops entry point)

**Before re-discovering any ops pipeline by grepping the repo: it is almost
certainly already a `mise` task.** Run `mise tasks ls` to see them live, then use
the matching task below. Re-implementing or hand-grepping a pipeline that already
exists wastes time and tokens — this index exists so that never happens.

## All tasks (run `mise tasks ls` for the live list)

| Task | What | Safety | Deeper skill |
|---|---|---|---|
| `mise run tf:upload <app> <ios\|macos\|all> [--archive-only\|--i-am-sure]` | archive → export → TestFlight upload | upload gated `--i-am-sure` (user-owned); archive/export safe | [[local-testflight-upload]] |
| `mise run ck:schema <export\|validate\|deploy> --app <app> [--env e]` | CloudKit schema export / validate / dev-deploy | prod promote = Console-only (user-owned); task prints steps + exit 2 | [[cloudkit-schema-ops]] |
| `mise run store:screenshots <list\|sync\|clean> [--app <app>]` | sync ASC screenshot PREVIEWS from snapshot baselines (symlinks) | safe; PREVIEW-ONLY (not ASC-spec) | [[appstore-screenshot-pipeline]] |
| `mise run gen:acknowledgements [--config-path …]` | regenerate Settings.bundle license page | safe; output gitignored | [[acknowledgements-generation]] |
| `mise run gen:l10n_fixture` | regenerate AppCompositionTests L10n fixture (byte-copy of Sudoku catalog) | safe | [[apple-dev-skills:ai-translated-localization]] |
| `mise run scan:l10n` | L10n gate: 0 `<TRANSLATE>`, all 7 locales per key, **+ shared-code dotted-key parity** (dotted keys referenced from GameAppKit/GameShellUI/SettingsUI/MonetizationUI must exist in every app catalog, #594) | safe (read-only gate) | [[apple-dev-skills:ai-translated-localization]] |
| `mise run scan:secrets` | gitleaks over staged files | safe | [[apple-dev-skills:apple-public-repo-security]] |
| `mise run scan:hygiene` | block secret-shaped files (`.p8`/`.p12`/`.pem`/`.env`) from history | safe | [[apple-dev-skills:apple-public-repo-security]] |
| `mise run scan:admob` | AdMob SDK isolation gate: only LiveAdMobBridge.swift may `import GoogleMobileAds` | safe (read-only gate) | [[apple-dev-skills:monetization-sdk-integration]] |
| `mise run lint:swift [files]` | SwiftLint, warn-only (lefthook pre-commit) | safe | [[apple-dev-skills:mise-tool-management]] |
| `mise run lint:swift_strict [files]` | SwiftLint, warnings-fail (PR CI) | safe | [[apple-dev-skills:mise-tool-management]] |
| `mise run new_app:provisioning` | render provisioning walkthrough HTML (public IDs only) | safe | [[asc-ops-handoff]] |
| `mise run verify:audio` | check each #330 gameplay soundKey resolves to a bundled asset (stem == soundKey, resolver-ext) | safe (read-only) | — (#330) |
| `mise run ui:tour [--app <app>] [--udid u] [--no-build]` | deep-link + screenshot every screen (home/daily/practice/board/settings) in light & dark for designer review; uses the #510 DEBUG launch hooks | safe; builds a DEBUG sim app, output gitignored under `build/tour/` | — (#510) |
| `mise run test:ui [<app>] [--udid u] [--no-generate]` | run host-driven XCUITest E2E suites via the `<App>-E2E` schemes (both apps: launch smoke + full win→completion) | safe; local on-demand substitute for the per-PR CI gate while XCC quota is out (NOT a GitHub Actions gate) | — (#510 Phase 3) |

## CI scripts (Xcode Cloud)

- `ci_scripts/ci_post_clone.sh` — runs on every XCC clone: installs mise tools,
  injects build-time secrets, regenerates acknowledgements. Second line of secret
  defence. → [[apple-dev-skills:xcode-cloud-single-track-ci]], [[apple-dev-skills:apple-public-repo-security]]
- `ci_scripts/ci_pre_xcodebuild.sh` — pre-build hook. → [[apple-dev-skills:xcode-cloud-single-track-ci]]

## Conventions every ops task shares

- **Secrets** come from `secrets/.env` (gitignored) — never argv, never echoed.
  See [[apple-dev-skills:build-time-secret-injection]].
- **Irreversible / live-service steps are user-owned**: tf:upload's upload is
  gated behind `--i-am-sure`; ck:schema's production promote is CloudKit
  Console-only (cktool cannot push prod). archive / export / validate /
  dev-deploy / scans / lint / generate are Leader-orderable + safe.
- **Tool versions** are pinned in `.mise.toml` ([[apple-dev-skills:mise-tool-management]]); CI and
  dev share them for parity.

## See also

- [[asc-ops-handoff]] — the user-owned vs Leader-orderable taxonomy for ASC / TestFlight / Apple Developer ops.
- [[apple-dev-skills:xcode-cloud-single-track-ci]] — the CI workflows these tasks mirror or temporarily substitute.
