#!/bin/bash
# Xcode Cloud post-clone hook.
# Earliest hook (foundations.md §7.6 / §7.11): runs before build resources are
# consumed, so secret leaks fail fast.
set -euo pipefail

# 1) Install all CLI tools pinned in .mise.toml (gitleaks, swiftlint, etc.)
# Bootstrap mise (Xcode Cloud images do not ship with it)
if ! command -v mise >/dev/null 2>&1; then
    curl -fsSL https://mise.run | sh
    export PATH="$HOME/.local/bin:$PATH"
fi
mise install

# 2) Second-line secret scan — backstops a `git commit --no-verify` bypass.
mise exec aqua:gitleaks/gitleaks -- gitleaks git --pre-commit --staged --redact
