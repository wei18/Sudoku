# Xcode Cloud Tuist cwd fix — impl notes

**Branch**: `fix/ci-tuist-cwd`
**Issue**: #88 — Build #3 failed with `Manifest not found at path /Volumes/workspace/repository/ci_scripts`
**Root cause**: Xcode Cloud invokes `ci_post_clone.sh` with cwd = `ci_scripts/`. Tuist looks for `Project.swift` in cwd, but it lives at repo root.

## Change

`ci_scripts/ci_post_clone.sh` block 3 only — inserted a `cd` to repo root before `tuist install`:

```bash
cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/..}"
```

- `$CI_PRIMARY_REPOSITORY_PATH` — Xcode Cloud's documented env var for the cloned repo root.
- `$(dirname "$0")/..` — fallback so local dry-runs (`./ci_scripts/ci_post_clone.sh`) still resolve to repo root.

Blocks 1 (mise bootstrap), 2 (gitleaks), `set -euo pipefail`, and the §7.6/§7.11 comment are untouched.

## Verify

- `bash -n` — **blocked by sandbox**, not run.
- Manual read: file is 8 lines longer than 1-line change implies; only block 3 modified. Shell syntax of the added line is standard parameter expansion with default; no quoting hazards.
