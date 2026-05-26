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
mise run scan:secrets

# 3) Repo-root setup for Tuist (cd once, then xcconfig + generate)
cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/..}"

# 3.1) Signing.xcconfig from Xcode Cloud's built-in $CI_TEAM_ID
#      (https://developer.apple.com/documentation/xcode/environment-variable-reference)
#      gitignored locally so the team ID never lands in a tracked file.
if [[ ! -f "Tuist/Signing.xcconfig" ]]; then
    if [[ -n "${CI_TEAM_ID:-}" ]]; then
        cat > "Tuist/Signing.xcconfig" <<EOF
DEVELOPMENT_TEAM = ${CI_TEAM_ID}
EOF
        echo "Wrote Tuist/Signing.xcconfig from CI_TEAM_ID"
    else
        echo "ERROR: CI_TEAM_ID env var not set (expected in Xcode Cloud); cannot generate Signing.xcconfig"
        exit 1
    fi
fi

# 3.2) Generate Xcode workspace via Tuist. Tuist symlinks
#      Sudoku.xcworkspace/xcshareddata/swiftpm/Package.resolved →
#      committed `.package.resolved` at repo root (#105), so xcodebuild's
#      internal package resolution succeeds without a -resolvePackageDependencies
#      pre-step.
mise exec -- tuist install
mise exec -- tuist generate --no-open

# 3.3) Generate Settings.bundle/Acknowledgements page from SwiftPM dep graph.
#      Config: `license_plist.yml` (source of truth). Output is
#      .gitignore'd — must run before xcodebuild bundles App/Resources.
#      Invocation routes through `mise run gen:acknowledgements` (SSOT task
#      body in .mise.toml).
mise run gen:acknowledgements
