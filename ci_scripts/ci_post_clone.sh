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

# 3.1b) AdMob.xcconfig from per-workflow Secret env vars (ASC → Xcode Cloud
#       → Workflow → Environment Variables). One workflow per app so each
#       picks up the right App ID + banner unit ID for its target.
#       Template: Tuist/AdMob.xcconfig.example (committed). Real file is
#       gitignored. The Info.plist `GADApplicationIdentifier` /
#       `GADBannerUnitID` substitutions resolve from these values.
if [[ ! -f "Tuist/AdMob.xcconfig" ]]; then
    # Detect which app this workflow targets via $CI_PRODUCT (Xcode Cloud
    # built-in: scheme name). Fall back to $CI_XCODE_SCHEME if needed.
    SCHEME="${CI_PRODUCT:-${CI_XCODE_SCHEME:-}}"
    case "${SCHEME}" in
        Sudoku)
            APP_ID_VAR="SUDOKU_ADMOB_APP_ID"
            BANNER_VAR="SUDOKU_ADMOB_BANNER_UNIT_ID"
            ;;
        Minesweeper)
            APP_ID_VAR="MINESWEEPER_ADMOB_APP_ID"
            BANNER_VAR="MINESWEEPER_ADMOB_BANNER_UNIT_ID"
            ;;
        *)
            echo "ERROR: cannot determine AdMob env-var prefix — CI_PRODUCT/CI_XCODE_SCHEME='${SCHEME}' (expected Sudoku or Minesweeper)"
            exit 1
            ;;
    esac
    APP_ID="${!APP_ID_VAR:-}"
    BANNER="${!BANNER_VAR:-}"
    if [[ -z "${APP_ID}" || -z "${BANNER}" ]]; then
        echo "ERROR: ${APP_ID_VAR} and/or ${BANNER_VAR} not set in Xcode Cloud Workflow env vars; cannot generate AdMob.xcconfig"
        exit 1
    fi
    cat > "Tuist/AdMob.xcconfig" <<EOF
ADMOB_APP_ID = ${APP_ID}
ADMOB_BANNER_UNIT_ID = ${BANNER}
EOF
    echo "Wrote Tuist/AdMob.xcconfig from ${APP_ID_VAR} + ${BANNER_VAR}"
fi

# 3.2) Generate Xcode workspace via Tuist. Tuist symlinks
#      Game.xcworkspace/xcshareddata/swiftpm/Package.resolved →
#      committed `.package.resolved` at repo root (#105), so xcodebuild's
#      internal package resolution succeeds without a -resolvePackageDependencies
#      pre-step.
mise exec -- tuist install
mise exec -- tuist generate --no-open

# 3.3) Generate Settings.bundle/Acknowledgements page from SwiftPM dep graph,
#      for the app this workflow builds. Output is .gitignore'd — must run
#      before xcodebuild bundles <App>/Resources. Per-app config selected via
#      $CI_PRODUCT (same scheme detection used for AdMob.xcconfig above):
#        Sudoku      → license_plist.yml             (source of truth)
#        Minesweeper → license_plist.minesweeper.yml (source of truth)
#      Invocation routes through `mise run gen:acknowledgements` (SSOT task
#      body in .mise.toml); the explicit --config-path arg puts the task in
#      pass-through mode so only the built app's bundle is regenerated.
case "${CI_PRODUCT:-${CI_XCODE_SCHEME:-}}" in
    Sudoku)
        mise run gen:acknowledgements --config-path license_plist.yml
        ;;
    Minesweeper)
        mise run gen:acknowledgements --config-path license_plist.minesweeper.yml
        ;;
    *)
        echo "ERROR: cannot determine acknowledgements config — CI_PRODUCT/CI_XCODE_SCHEME='${CI_PRODUCT:-${CI_XCODE_SCHEME:-}}' (expected Sudoku or Minesweeper)"
        exit 1
        ;;
esac
