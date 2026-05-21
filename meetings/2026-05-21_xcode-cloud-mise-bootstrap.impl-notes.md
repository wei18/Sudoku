# Xcode Cloud mise bootstrap — impl notes

## Bug symptom

Xcode Cloud build (macOS Tahoe 26.4) fails at `Run ci_post_clone.sh`:

```
/Volumes/workspace/repository/ci_scripts/ci_post_clone.sh: line 8: mise: command not found
```

Xcode Cloud's base image does not ship with mise, so the very first `mise install` call aborts before any tooling is provisioned.

## Fix shape

Prepend a guarded bootstrap block before the existing `mise install` line in `ci_scripts/ci_post_clone.sh`:

```bash
if ! command -v mise >/dev/null 2>&1; then
    curl -fsSL https://mise.run | sh
    export PATH="$HOME/.local/bin:$PATH"
fi
```

- Idempotent: skips install when `mise` already on PATH (local dev / cached CI runs).
- `set -euo pipefail` preserved at top; existing foundations.md §7.6 / §7.11 comments untouched.
- Only `ci_scripts/ci_post_clone.sh` modified.

## Why `curl | sh` is acceptable here

1. **Official source.** `https://mise.run` is the installer endpoint documented at https://mise.jdx.dev/getting-started.html — same idiom the upstream project recommends.
2. **Transparent install.** The script writes to `$HOME/.local/bin/mise` only; no root, no system mutation, no daemon, no background service.
3. **No secrets in scope.** Bootstrap runs before any Xcode Cloud secret env vars are consumed (gitleaks step still runs afterward as the second-line scan).
4. **Pinned downstream.** Once mise is on PATH, `.mise.toml` pins every tool version (gitleaks, swiftlint, etc.), so the *effective* toolchain is reproducible even though the bootstrap binary itself floats to latest. The bootstrap is a thin shim, not a tool version source.
5. **Fail-fast flags.** `curl -fsSL` — fail on HTTP error, silent progress, follow redirects — matches the upstream recommendation and avoids masking 4xx/5xx as success.

## §未決

- **Should Xcode Cloud cache `~/.local/bin/mise` between runs?** Bootstrap currently re-downloads mise on every clean build (~5–10s). Xcode Cloud supports a custom cache path via workflow config; caching `~/.local/bin/mise` + `~/.local/share/mise` could shave that cost and also pre-warm the tool cache (gitleaks, swiftlint binaries). Tradeoff: cache invalidation when mise releases a security fix. Backlog candidate for `docs/foundations.md` §Backlog (tooling topic).
