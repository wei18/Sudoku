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

# 3.2) Generate Xcode workspace via Tuist (repo does not commit .xcworkspace)
mise exec -- tuist install
mise exec -- tuist generate --no-open

# 3.3) Resolve SwiftPM packages at workspace level (Tuist generates the
# workspace but disables automatic resolution; we re-enable for the first
# build so AdMob/UMP SDKs can fetch).
xcodebuild -resolvePackageDependencies \
    -workspace Sudoku.xcworkspace \
    -scheme Sudoku \
    -clonedSourcePackagesDirPath "${CI_DERIVED_DATA_PATH:-DerivedData}/SourcePackages" \
    -onlyUsePackageVersionsFromResolvedFile NO
