# xcstrings Reformat Decision — Impl Notes

**Date**: 2026-05-20
**Task**: Decide and implement handling for Xcode's repeated auto-reformat of `App/Resources/Localizable.xcstrings`.

## Decision

**Option (a) — Commit the reformat once.**

## Rationale

- Simplest path; zero ongoing maintenance.
- Xcode's reformat is idempotent: once the file is committed in its expanded multi-line form, subsequent Xcode builds produce no-op writes (same bytes), so `git status` stays clean.
- Option (b) (lefthook hook) imposes a per-commit lint cost on every dev for a problem that disappears after a single commit. Not justified.
- Option (c) (ignore) leaves the noise in place — already bit us twice (PR #4, PR #14). Not acceptable.

## File State

### Before (this task)
- Path: `App/Resources/Localizable.xcstrings`
- Size: 68,156 bytes
- Lines: 2,686
- Format: **Already in Xcode's expanded multi-line JSON form** (Xcode reformatted on a prior build; not yet committed).
- mtime: 2026-05-20 14:35 (most recent Xcode build)

### After (this task)
- **No edit performed.** The file is already in the target shape. Leader stages and commits as-is.

## Verification Approach

Cannot run Xcode in this agent environment (no GUI). Verification deferred to Leader:

1. Leader commits `App/Resources/Localizable.xcstrings` as-is.
2. Leader opens Xcode, performs a clean build of the macOS target.
3. Leader runs `git status` — expected result: `Localizable.xcstrings` does **not** appear as modified.
4. If step 3 shows the file as modified, Option (a) assumption (idempotency) is wrong — escalate to consider Option (b).

## TODO Sweep

`grep -r "TODO\|FIXME\|XXX" App/Resources/` → empty. Clean.

## §未決

- **Leader must run an Xcode build once post-commit to confirm idempotency.** This is the only outstanding verification step. If non-idempotent, revisit (b).

## Status

COMPLETE (pending Leader's Xcode-build idempotency confirmation per §未決).
