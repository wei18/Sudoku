---
name: local-testflight-upload
description: Local archive → export → TestFlight upload via `mise run tf:upload`, the temporary stand-in for the Xcode Cloud "Main CI" workflow while the XCC monthly compute quota is exhausted. Covers the per-app/per-platform pipeline (tuist generate → xcodebuild archive → CFBundleVersion bump → App-Store-Connect export → gated altool upload), ASC API auth from secrets/.env, and the user-owned --i-am-sure upload gate. Invoke when a build needs to reach TestFlight without Xcode Cloud, when running or debugging `tf:upload`, when deciding archive-only vs upload, or when asked "how do I get a build to TestFlight locally / why is the export plist failing / what build number do I use".
---

# Local TestFlight Upload

## When to invoke

- XCC "Main CI" can't run (quota out) but a build must reach internal TestFlight.
- Running or debugging `mise run tf:upload` for Sudoku or Minesweeper.
- Deciding between a safe archive-only dry run and a real upload.
- Diagnosing an ExportOptions.plist / build-number / export-compliance failure.
- User asks "how do I ship a TestFlight build without Xcode Cloud".

## What it is

`mise-tasks/tf/upload` is a commit-tracked, idempotent wrapper around the Apple
CLIs (`tuist`, `xcodebuild`, `xcrun altool`) that reproduces the Xcode Cloud
**Main CI** action (Build + Archive + upload to internal TestFlight) on a local
machine. It is a **temporary substitute** for the XCC workflow described in
`docs/foundations.md §4`, for the window where the XCC monthly compute quota is
exhausted. It mirrors the scriptable-ops precedent of `mise-tasks/ck/schema` and
`mise-tasks/store/screenshots`.

## Invocation

```
mise run tf:upload <sudoku|minesweeper> <ios|macos|all> [flags]
```

| Flag | Effect |
|---|---|
| `--archive-only` | archive + export only; never upload (default-safe) |
| `--build <N>` | explicit `CFBundleVersion` (build number); default `$(date -u +%Y%m%d%H%M)` |
| `--config <name>` | xcodebuild configuration (default `Release`) |
| `--i-am-sure` | **REQUIRED** to actually upload to TestFlight (user-owned) |
| `-h`, `--help` | usage |

Examples:
```
mise run tf:upload sudoku ios --archive-only            # safe: produce .ipa
mise run tf:upload sudoku all --archive-only            # iOS .ipa + macOS .pkg
mise run tf:upload sudoku ios --i-am-sure               # archive+export+UPLOAD
mise run tf:upload minesweeper macos --build 20260605 --i-am-sure
```

## Pipeline (per app + platform)

0. **admob render** — if `secrets/.env` carries `<APP>_ADMOB_APP_ID` +
   `<APP>_ADMOB_BANNER_UNIT_ID` (SUDOKU_*/MINESWEEPER_*), the task (re)writes
   `Tuist/AdMob.xcconfig` for the app being built — local parity with XCC's
   `ci_post_clone.sh` §3.1b. Absent keys → existing file used unchanged. Debug
   builds force Google's test ad unit in code, so prod values here never serve
   live ads from a dev run.
0.5. **acknowledgements** — `tuist install` (resolve SwiftPM) → `mise run gen:acknowledgements` → THEN `tuist generate`. Order matters (#433): `gen:acknowledgements` needs resolved checkouts to enumerate deps, and Tuist globs the `Settings.bundle` at *generate* time — so the bundle must be populated before generate or the installed build ships an EMPTY Acknowledgements page. See [[acknowledgements-generation]].
1. **generate** — `tuist generate` (the `Game.xcworkspace` is gitignored).
2. **archive** — `xcodebuild archive` → `build/testflight/<app>-<plat>.xcarchive`.
3. **bump** — PlistBuddy `Set :CFBundleVersion` on the **archived app's** embedded
   Info.plist. `CFBundleVersion` is a hardcoded `"1"` literal in the app's
   Info.plist (not driven by `CURRENT_PROJECT_VERSION`), so a build-setting
   override would be a no-op — the patch must happen post-archive / pre-export.
4. **export** — `xcodebuild -exportArchive` with a runtime-generated
   `ExportOptions` plist (`method=app-store-connect`, `destination=export`) →
   `.ipa` (iOS) / `.pkg` (macOS).
5. **upload** — `xcrun altool --upload-app` to TestFlight. **GATED** (see below).

## Auth

Reads ASC API credentials from `secrets/.env` (never echoed, never on argv):

- `ASC_API_KEY_PATH` → the `AuthKey_<KEY_ID>.p8` (gitignored, under `secrets/`)
- `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID`
- `CK_TEAM_ID` — reuses the single 10-char Apple Developer Team ID already in
  `.env` for cktool (used for `DEVELOPMENT_TEAM` at archive + export team id).

Nothing new is invented. The `.p8` is staged as a per-run symlink under
`build/testflight/private_keys/` where altool searches by key id, and removed on
exit. If any key is missing/placeholder the task aborts before doing work; fill
from project memory (`asc-api-credentials` + the Team ID).

## Safety gates

- **archive + export are safe and repeatable** — they touch only `build/`
  (gitignored). Use `--archive-only` freely as a dry run.
- **upload is the only irreversible, user-owned step.** It signs with the App
  Store distribution identity and pushes to ASC/TestFlight. The task prints a
  "user-owned, confirm" banner and **REFUSES without `--i-am-sure`** (exit 2).
  Per [[asc-ops-handoff]], the WHEN-to-upload decision is the user's; archive/export
  are Leader-orderable.

## Known footguns

- **ExportOptions plist must NOT be pre-`touch`ed.** PlistBuddy cannot parse a
  0-byte file ("Cannot parse a NULL or zero-length data"). The task `rm -f`s the
  path so PlistBuddy auto-creates it on the first `Add`. Do not "helpfully" add a
  `touch` before `write_export_options`. (This was the real failure on the first
  end-to-end run, 2026-06-09 — fixed by removing the `touch` + the `Clear dict`.)
- **Build-number uniqueness.** TestFlight/ASC reject a duplicate `CFBundleVersion`
  for the same `CFBundleShortVersionString`. The UTC-minute default is unique per
  minute; if you re-run within the same minute or pass an explicit `--build`,
  ensure it hasn't been used for this marketing version already.
- **Export-compliance is already handled for Sudoku + Minesweeper — do NOT flag
  it.** Both `App/Sudoku/Info.plist` and `App/Minesweeper/Info.plist` statically
  declare `ITSAppUsesNonExemptEncryption = <false/>`, so ASC never prompts for an
  encryption/export-compliance answer and the build is never held on that gate.
  When reporting an upload result, omit the compliance step. (Processing delay is
  still real — uploading ≠ instantly testable — but no compliance answer is
  needed.) A NEW app (e.g. Tiles2048) must add the same Info.plist key before its
  first TF build, or it WILL be held pending the ASC web-UI compliance answer.
- **macOS export method.** Xcode 15+ renamed `app-store` → `app-store-connect`;
  the task uses the new name (accepted by 16/26). Don't revert it.
- **Workspace is gitignored.** A clean checkout has no `Game.xcworkspace`; the
  task runs `tuist install` + `tuist generate --no-open` to produce it.

## See also

- [[apple-dev-skills:xcode-cloud-single-track-ci]] — the **Main CI** workflow this task temporarily
  substitutes; restore XCC once quota returns and retire local uploads.
- [[asc-ops-handoff]] — user-owned vs Leader-orderable taxonomy; TestFlight
  upload + promotion sit on the user-owned side.
- [[apple-dev-skills:build-time-secret-injection]] — the `secrets/.env` + `.p8` handling pattern
  this task reuses.
- [[mise-task-operations]] — the ops-task index this task belongs to.
