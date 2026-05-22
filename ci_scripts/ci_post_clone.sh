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

# 3) Repo-root setup for Tuist (cd once, then xcconfig + generate)
cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/..}"

# 3.1) Signing.xcconfig from CI env var (gitignored secret; never committed)
if [[ ! -f "Tuist/Signing.xcconfig" ]]; then
    if [[ -n "${SUDOKU_DEVELOPMENT_TEAM:-}" ]]; then
        cat > "Tuist/Signing.xcconfig" <<EOF
DEVELOPMENT_TEAM = ${SUDOKU_DEVELOPMENT_TEAM}
EOF
        echo "Wrote Tuist/Signing.xcconfig from SUDOKU_DEVELOPMENT_TEAM"
    else
        echo "ERROR: SUDOKU_DEVELOPMENT_TEAM env var not set; cannot generate Signing.xcconfig"
        exit 1
    fi
fi

# 3.2) Generate Xcode workspace via Tuist (repo does not commit .xcworkspace)
mise exec -- tuist install
mise exec -- tuist generate --no-open
