---
name: acknowledgements-generation
description: Regenerate each app's Settings.bundle Acknowledgements (open-source license) page from the SwiftPM dependency graph via `mise run gen:acknowledgements` (wraps LicensePlist, configured by `App/<App>/license_plist.yml`). Invoke when adding / removing / upgrading a third-party SwiftPM dependency (especially the AdMob / UMP graph under AppMonetizationKit), when license disclosure must be refreshed before a release, when editing a `license_plist.yml`, or when asked "how is the Acknowledgements / licenses page generated".
---

# Acknowledgements Generation

The `mise-tasks/gen/acknowledgements` task regenerates each app's iOS-standard
**Settings.bundle Acknowledgements page** from its SwiftPM dependency graph,
wrapping `ubi:mono0926/LicensePlist` (pinned in `.mise.toml`). The page surfaces
under iOS Settings.app → `<App name>` → Acknowledgements and discloses
third-party licenses (currently the AdMob + UMP SDKs pulled by
`AppMonetizationKit`).

## When to invoke

- Adding / removing / upgrading any third-party SwiftPM dependency (notably the
  AdMob / UMP graph under `Packages/AppMonetizationKit`).
- Refreshing license disclosure before a release.
- Editing `App/Sudoku/license_plist.yml` or `App/Minesweeper/license_plist.yml`.
- Asked how the licenses / Acknowledgements page is produced.

## Invocations

```bash
# Local dev — regenerate BOTH apps (no-args default mode).
mise run gen:acknowledgements

# Single app — pass-through mode: any args are forwarded verbatim to license-plist.
mise run gen:acknowledgements --config-path App/Sudoku/license_plist.yml
mise run gen:acknowledgements --config-path App/Minesweeper/license_plist.yml
```

The task has two modes:
- **No args** → regenerates both apps in sequence (Sudoku then Minesweeper).
- **Args present** → `exec`s `license-plist` with those args (this is how CI runs
  it — see `ci_scripts/ci_post_clone.sh`, which dispatches per `CI_PRODUCT` /
  `CI_XCODE_SCHEME`).

## Inputs / outputs

- **Config (inputs, committed)**: `App/Sudoku/license_plist.yml` and
  `App/Minesweeper/license_plist.yml`. Key options: `packagePaths` (the
  `Package.swift` files to scan — both list `AppMonetizationKit` + the app's own
  kit), `outputPath`, `force: true` (overwrite stale entries), `addVersionNumbers`,
  `suppressOpeningDirectory` (headless CI).
- **Output (generated, gitignored)**: the Settings.bundle at the config's
  `outputPath` — `App/Sudoku/Resources/Settings.bundle` /
  `App/Minesweeper/Resources/Settings.bundle`. CI regenerates on every build, so
  the bundle is **not committed**; do not `git add` it.

## Notes / safety

- Idempotent — `force: true` overwrites stale entries; re-running is safe.
- Nothing here is user-owned or irreversible (no secrets, no live-service writes).
  The only thing committed is the `.yml` config; the bundle is build output.
- The task is the SSOT invocation; CI and local dev both route through it rather
  than calling `license-plist` directly, so the pinned LicensePlist version
  (`.mise.toml`) is shared.

## See also

- [[apple-dev-skills:monetization-sdk-integration]] — adding the AdMob / UMP deps that this page must disclose.
- [[apple-dev-skills:mise-tool-management]] — how LicensePlist is pinned in `.mise.toml`.
- [[mise-task-operations]] — the ops-task index this task belongs to.
- `ci_scripts/ci_post_clone.sh §3.3` + `docs/foundations.md §4` — the CI wiring.
