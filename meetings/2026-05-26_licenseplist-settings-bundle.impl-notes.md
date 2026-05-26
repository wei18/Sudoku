# LicensePlist → Settings.bundle (CI-regen) — impl notes

Date: 2026-05-26
Supersedes: `meetings/2026-05-26_licenseplist-integration.md` (lives on
`origin/wip/licenseplist-preflight-v1`; never merged).

## Design pivot (user-locked 2026-05-26)

| Aspect | v1 plan (scrapped) | v2 plan (this dispatch) |
|---|---|---|
| Output target | SwiftUI in-app view rendering Markdown | iOS-standard `Settings.bundle` (surfaces in iOS Settings.app → Sudoku → Acknowledgements) |
| Generator invocation | `scripts/generate-acknowledgements.sh` (manual / lefthook) | `mise exec … license-plist` from `ci_scripts/ci_post_clone.sh` |
| Config | CLI flags inside the bash script | `license_plist.yml` (single source of truth) |
| Committed artifact | `App/Resources/Acknowledgements/Acknowledgements.md` | Nothing — generated `Settings.bundle/` is `.gitignore`'d |
| SwiftUI changes | new `AcknowledgementsView.swift` + `SettingsView` row + snapshot regen | None |

## What got dropped from `wip/licenseplist-preflight-v1`

- `scripts/generate-acknowledgements.sh` (manual script — superseded by CI hook)
- Plan for `AcknowledgementsView.swift` (no SwiftUI integration in this design)
- Plan for `SettingsView.swift` Acknowledgements row + snapshot baseline regen
- Plan for committing `App/Resources/Acknowledgements/Acknowledgements.md`

What carried over: the `.mise.toml` `ubi:mono0926/LicensePlist` pin (with `exe = "license-plist"` override to handle the lowercase-hyphen binary name inside the tarball).

## Files touched (this dispatch)

1. `.mise.toml` — re-applied `ubi:mono0926/LicensePlist` pin with rationale comment
2. `license_plist.yml` — new; YAML config under `options:` block with camelCase keys (`packagePaths`, `outputPath`, `force`, `addVersionNumbers`, `suppressOpeningDirectory`) per upstream README. Initial draft used hyphen-case keys mirroring the CLI flag names — silently ignored by the parser (no error; output went to the default `./com.mono0926.LicensePlist.Output/`). Corrected to camelCase after consulting the upstream `README.md§Configuration`.
3. `ci_scripts/ci_post_clone.sh` — appended one-line `license-plist` invocation as step 3.3 (after `tuist generate`, before xcodebuild consumes resources)
4. `.gitignore` — added `App/Resources/Settings.bundle/`
5. `Project.swift` — added `.glob(pattern: "App/Resources/Settings.bundle/**")` to App target `resources:` so Tuist bundles the generated dir without requiring it to exist at `tuist generate` time
6. `docs/foundations.md §4 環境鎖定` — appended sub-bullet documenting LicensePlist invocation path

## Design decisions & rationale

### Why `Settings.bundle` over SwiftUI in-app

- iOS-standard surface: users find license disclosures in the OS-level Settings.app pane, same place every app puts them. Zero in-app UI surface area to design / test / localize / snapshot.
- App Store compliance is satisfied by Settings.bundle regardless of whether the App also shows an in-app view.
- Zero SwiftUI changes → zero snapshot baseline churn.

### Why CI-regen + `.gitignore`'d output

- `Package.resolved` is the upstream source of truth. Any change there (SemVer bump, new transitive dep) automatically reflects in the next CI build's Acknowledgements page. No "developer forgot to regen" drift.
- Generated artifact is verbose plist tree — diff noise per dep bump would dominate PR review.
- `license_plist.yml` (10 lines, declarative) is the only thing humans edit.

### Why `ci_post_clone.sh` (not `ci_pre_xcodebuild.sh`)

- Settings.bundle must exist on disk before `xcodebuild` packages App/Resources. `ci_post_clone.sh` runs earliest in Xcode Cloud's hook chain (per `docs/foundations.md §4`); `tuist generate` already happens here, so license-plist is appended after `tuist generate` for cohesion.

### Why `exe = "license-plist"` override in `.mise.toml`

- ubi backend defaults to looking for an executable matching the GitHub repo name (`LicensePlist`) inside the release tarball. The actual binary is `license-plist` (lowercase + hyphen). Without the override `mise install` fails. Verified locally: `mise exec ubi:mono0926/LicensePlist -- license-plist --version` → `3.27.9`.

### Why `.glob(pattern: …/Settings.bundle/**)` in Project.swift

- Plain `"App/Resources/Settings.bundle"` string-literal entry would make Tuist fail-fast at `tuist generate` time on a fresh checkout (dir doesn't exist until CI runs license-plist). `.glob` resolves at build time and tolerates an empty/missing match on dev machines — they get no Acknowledgements page locally (acceptable: it's a release-surface concern only).

## Open questions (none blocking)

- Should dev machines also auto-regen Settings.bundle (e.g. via a lefthook pre-commit on `Package.resolved` change)? Currently dev machines simply don't have the bundle locally; only CI builds (TestFlight + App Store) ship it. Leader to decide if this is acceptable post-merge.
