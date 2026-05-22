# 2026-05-22 — ci_post_clone.sh: explicit SwiftPM resolution

## Context

Xcode Cloud build #9 (issue #96) fails after `tuist generate --no-open`:

```
xcodebuild: error: Could not resolve package dependencies:
  a resolved file is required when automatic dependency resolution is disabled
  and should be placed at .../Sudoku.xcworkspace/xcshareddata/swiftpm/Package.resolved.
```

Exit 74. Tuist invokes xcodebuild with `-disableAutomaticPackageResolution`;
the generated workspace has no `Package.resolved`, so xcodebuild refuses to
fetch `swift-package-manager-google-mobile-ads`.

## Change

Append §3.3 to `ci_scripts/ci_post_clone.sh` (only that file touched). After
`tuist generate --no-open`, run an explicit top-level
`xcodebuild -resolvePackageDependencies` against the generated workspace:

- `-workspace Sudoku.xcworkspace -scheme Sudoku` — target the generated
  workspace + main scheme.
- `-clonedSourcePackagesDirPath "${CI_DERIVED_DATA_PATH:-DerivedData}/SourcePackages"`
  — direct SPM clones into Xcode Cloud's DerivedData (env var supplied by
  Xcode Cloud; local fallback `DerivedData` so a developer dry-run works).
- `-onlyUsePackageVersionsFromResolvedFile NO` — the critical flag. Without
  it, xcodebuild in CI contexts demands a pre-existing `Package.resolved`
  and refuses to write a new one. `NO` allows first-fetch and emits the
  resolved file under the workspace's xcshareddata.

Blocks 1, 2, 3.1, 3.2 untouched. `set -euo pipefail` preserved (the new
command therefore aborts the script on non-zero exit, matching existing
fail-fast posture).

## Verification

- `bash -n ci_scripts/ci_post_clone.sh` — sandbox denied; visual review
  only. Syntax: single multi-line `xcodebuild …` continuation with trailing
  backslashes on each non-final line, no quoting traps around
  `${CI_DERIVED_DATA_PATH:-DerivedData}`.
- Will be validated end-to-end by the next Xcode Cloud build triggered on
  this branch.

## §未決

- Cache `${CI_DERIVED_DATA_PATH}/SourcePackages/` between Xcode Cloud builds
  to skip ~30 s of AdMob/UMP re-fetches per run? Xcode Cloud doesn't expose
  arbitrary path caching; the SourcePackages dir under DerivedData is
  retained across same-workflow runs by default, so this may already be
  free after build #10. Confirm by comparing build #10 vs #11 SPM
  resolution wall-clock.
- Should `Package.resolved` be committed to the repo (under
  `Tuist/`-managed seed location) to lock versions? Currently the workspace
  is regenerated each CI run, so a committed file would have to be copied
  into `Sudoku.xcworkspace/xcshareddata/swiftpm/` post-generate. Defer
  until we hit a reproducibility incident.
