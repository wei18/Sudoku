---
name: local-testflight-upload
description: Archive, export and upload a Sudoku or Minesweeper build to TestFlight from this machine with `mise run tf:upload`. Use when a build must reach TestFlight, when running or debugging `tf:upload`, when choosing between archive-only and a real upload, when regenerating the "What to Test" changelog, or when asked what build number to use or why the export fails. Not for App Store submission steps (see asc-ops-handoff) and not for simulator builds (see interactive-sim-ux-audit).
---

# Local TestFlight Upload

`mise-tasks/tf/upload` wraps `tuist`, `xcodebuild` and `xcrun altool`. It does locally what the Xcode Cloud "Main CI" workflow does: archive, export, upload to internal TestFlight.

The upload is a user-owned gate. Run it only when the user asks for an upload.

## Invocation

```
mise run tf:upload <sudoku|minesweeper|all> <ios|macos|all> [flags]
```

What happens, by gate flag:

| Flags | Archive and export | Upload | Exit code |
|---|---|---|---|
| `--archive-only` | Yes | No | 0 |
| neither flag | Yes | No: the task prints a confirmation banner and refuses | 2 |
| `--i-am-sure` | Yes | Yes | 0 on success |

Other flags:

| Flag | Effect |
|---|---|
| `--build <N>` | Set the build number (`CFBundleVersion`). Default: UTC time as `YYYYMMDDhhmm` |
| `--config <name>` | xcodebuild configuration. Default: `Release` |
| `--force-archive` | Archive again even when the source fingerprint is unchanged |
| `--changelog-only` | Write and print the "What to Test" changelog. No archive, export, upload or tag |
| `--full` | With the changelog: keep every commit and the `(#NNN)` references |
| `--since <ref>` | Changelog start when no earlier `tf/<app>-<plat>/*` tag exists |
| `--whats-new-only` | For a build already uploaded: wait for ASC processing, then set its `whatsNew` text. Needs `--build`, and `--i-am-sure` or `--dry-run` |
| `--whats-new-timeout <secs>` | How long to wait for ASC processing. Default: 900 |
| `--dry-run` | With `--whats-new-only`: print the payload, write nothing |

Examples:

```
mise run tf:upload sudoku ios --archive-only                 # build the .ipa, no upload
mise run tf:upload all all --archive-only                    # both apps, iOS .ipa and macOS .pkg
mise run tf:upload sudoku ios --i-am-sure                    # archive, export, upload
mise run tf:upload sudoku ios --changelog-only               # preview the changelog
mise run tf:upload sudoku ios --whats-new-only --build 202607061321 --dry-run
```

## Before you run it

1. In a worktree, seed the gitignored files first: `mise run worktree:seed <path>` from the main checkout.
2. `secrets/.env` must hold `ASC_API_KEY_PATH`, `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID` and `CK_TEAM_ID`. The task stops before doing any work if one is missing or still a placeholder. The user supplies these values; they are not in the repo.
3. Xcode must be signed in to the Apple Developer account: the archive uses automatic signing.
4. This is a heavy build. Apply the disk and load checks from the global engineering rules.

## Pipeline (per app and platform)

1. **Render xcconfig.** Write `Tuist/AdMob.xcconfig` and `Tuist/AppStore.xcconfig` from `secrets/.env` (`<APP>_ADMOB_APP_ID`, `<APP>_ADMOB_BANNER_UNIT_ID`, `ASC_APP_ID_<APP>`). If the keys are absent, the existing files are used unchanged.
2. **Resolve and generate.** `tuist install`, then `tuist generate --no-open` if the workspace is missing.
3. **Acknowledgements.** `mise run gen:acknowledgements`, then `tuist generate --no-open` again. Tuist reads the `Settings.bundle` at generate time, so the bundle must exist before the second generate.
4. **Archive.** `xcodebuild archive` to `build/testflight/<app>-<plat>.xcarchive`. Skipped when the fingerprint (HEAD, dirty tree, app, platform, configuration, rendered xcconfig) matches the previous archive. An untracked file whose content changed does not change the fingerprint: use `--force-archive` then.
5. **Set the build number.** Patch `CFBundleVersion` in the archived app's Info.plist. A build setting cannot do this: the value in Info.plist is a literal.
6. **Export.** `xcodebuild -exportArchive` with a generated options file (`method=app-store-connect`) to `.ipa` (iOS) or `.pkg` (macOS).
7. **Upload** (gated). `xcrun altool --upload-app`.
8. **After a successful upload.** In this order: write the changelog to `build/testflight/<app>-<plat>-<build>-changelog.md`, create and push the tag `tf/<app>-<plat>/<build>`, wait for ASC processing and set the en-US `whatsNew` text from the changelog. A failure in this step is a warning; the task does not report the upload as failed.

With `<app> all`, steps 1 to 6 run one app at a time, because both apps share `Tuist/AdMob.xcconfig` and `Game.xcworkspace`. Only the uploads run in parallel. One `--i-am-sure` covers both apps. If one app's upload fails, the other still completes and the task exits non-zero.

## Rules

- TestFlight builds are Release builds and carry the production AdMob IDs from `secrets/.env`. Debug builds always use Google's test ad unit.
- A build number can be used once per marketing version. Do not reuse a `--build` value.
- Do not report export compliance as a pending step. Both Info.plist files declare `ITSAppUsesNonExemptEncryption = false`. A new app must add the same key before its first upload.
- An uploaded build is not testable at once: ASC processes it first.
- Do not create the export options file beforehand (`touch`). PlistBuddy cannot read an empty file; the task creates it.
- Keep the export method `app-store-connect`. The older name `app-store` is not accepted.
- `mise-tasks/tf/asc_whats_new.py` uses only `python3` and `openssl`. Do not add a pip dependency.
- The task must run under macOS's bash 3.2. Optional flags are plain variables, not arrays, because an empty array fails under `set -u` there.
- The default changelog drops commits whose type is `docs`, `chore` or `ci` and commits whose scope is `skill`, `spec` or `meetings`. `--full` keeps them.
- `whatsNew` is cut to 4000 characters with a warning.

## See also

- `asc-ops-handoff`: which App Store Connect steps the user owns.
- `acknowledgements-generation`: the license page built in step 3.
- `apple-dev-skills:xcode-cloud-single-track-ci`: the Xcode Cloud workflow this task stands in for.
- `apple-dev-skills:build-time-secret-injection`: how `secrets/.env` and the xcconfig files are used.
- `mise-task-operations`: index of all ops tasks.
