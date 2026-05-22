# 2026-05-22 — Fix Xcode Cloud build: generate Signing.xcconfig from env var

GitHub issue: #91
Branch: `fix/ci-signing-xcconfig`

## Problem

Xcode Cloud build #4 failed at `tuist generate`:

```
Configuration file not found at path /Volumes/workspace/repository/Tuist/Signing.xcconfig
✖ Error: Fatal linting issues found
```

`Tuist/Signing.xcconfig` is gitignored (contains `DEVELOPMENT_TEAM`, a 10-char Apple Developer identifier treated as a secret per foundations.md §7). Xcode Cloud's fresh clone has no copy, so tuist refuses to generate the workspace.

## Fix

Three coordinated edits — secret stays out of git, CI synthesizes it just-in-time from an Xcode Cloud workflow env var.

### 1. `ci_scripts/ci_post_clone.sh`

- Consolidated the `cd "${CI_PRIMARY_REPOSITORY_PATH...}"` into a single section `# 3) Repo-root setup for Tuist` (previously block #3 did its own cd; now cd happens once, both xcconfig-write and tuist-generate run under it).
- New step `3.1`: if `Tuist/Signing.xcconfig` is missing and `SUDOKU_DEVELOPMENT_TEAM` is set, write the file from a heredoc. If the env var is missing, fail fast with a clear error (preserves `set -euo pipefail` behavior on a misconfigured workflow).
- Preserves all prior blocks (mise bootstrap #1, gitleaks #2).

### 2. `Tuist/Signing.xcconfig.example`

- Updated the CI guidance comment block. Old text referenced a non-existent `ci_pre_xcodebuild.sh`; new text names the actual hook (`ci_post_clone.sh`) and the actual env-var name (`SUDOKU_DEVELOPMENT_TEAM`).

### 3. `docs/v2/v2.5-readiness.md`

- Appended one item to the `## Pre-flight` checklist documenting the manual ASC workflow step required to set `SUDOKU_DEVELOPMENT_TEAM` in Xcode Cloud, including the exact UI breadcrumb.

## Why this shape

- **Secret never enters git.** Workflow env var lives only in ASC; the synthesized file is gitignored. Matches foundations.md §7 posture (secret material reconstructed at build time from external store).
- **Idempotent.** `[[ ! -f ... ]]` guard means a developer running a local `act`-style replay with a real Signing.xcconfig won't have it overwritten.
- **Fail-fast.** Missing env var aborts ci_post_clone before tuist runs, so the error surfaces in the post-clone log (clearly attributable to misconfig), not deeper inside a tuist lint trace.
- **No team-ID hardcoding.** Heredoc interpolates `${SUDOKU_DEVELOPMENT_TEAM}` only.

## Verify

- `bash -n ci_scripts/ci_post_clone.sh` — blocked by sandbox (Bash permission denied). Script is short and was hand-reviewed; no syntactic surprises (heredoc terminator on its own line, no unmatched quotes, `set -euo pipefail` preserved).
- `Tuist/Signing.xcconfig` confirmed gitignored: `.gitignore` line 14 (`Tuist/Signing.xcconfig`), with line 13 comment explicitly noting the `.example` template is the only committed copy.

## §未決

- **Local file with different value.** Current logic (`[[ ! -f "Tuist/Signing.xcconfig" ]]`) skips writing if the file already exists, regardless of contents. On Xcode Cloud this is moot (fresh clone, file never exists). On a developer machine running ci_post_clone manually, a stale local file with a different team ID would be preserved. Acceptable for now — local devs are expected to manage their own xcconfig per the .example instructions — but worth documenting if we later add a `--force-regen` mode for CI re-runs from cache.
- **Workflow env-var scoping.** SUDOKU_DEVELOPMENT_TEAM should be set as a non-secret env var (team ID is sensitive-but-not-secret per Apple's own posture — it appears in every signed `.ipa`). Marking it "secret" in ASC will work but is theatrical; either way achieves the goal.
- **Pre-existing branch state.** Working tree had unrelated uncommitted changes from `docs/spec-s2-cleanup` when this branch was created; Leader handles scope at commit time.
