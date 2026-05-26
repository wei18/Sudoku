#!/bin/bash
# Xcode Cloud pre-xcodebuild hook.
# Runs after dependencies are resolved (post `ci_post_clone.sh`) and right
# before `xcodebuild` starts. Mutations to `App/Info.plist` here flow into
# the archive uploaded to TestFlight / App Store Connect.
set -euo pipefail

# Resolve repo root via absolute path. Xcode Cloud cd's into `ci_scripts/`
# before invoking the hook (observed in first run on PR #177), and
# `$CI_PRIMARY_REPOSITORY_PATH` isn't always populated in this hook context.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
INFO_PLIST="${REPO_ROOT}/App/Info.plist"

if [[ ! -f "${INFO_PLIST}" ]]; then
    echo "ERROR: App/Info.plist not found at ${INFO_PLIST}" >&2
    exit 1
fi

# Set CFBundleVersion from Xcode Cloud's built-in $CI_BUILD_NUMBER
# (https://developer.apple.com/documentation/xcode/environment-variable-reference).
# Local builds keep the committed "1" placeholder; Xcode Cloud builds get a
# monotonically-increasing value that satisfies ASC's "build number must
# increase" rule without manual bumps in Info.plist.
if [[ -n "${CI_BUILD_NUMBER:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${CI_BUILD_NUMBER}" "${INFO_PLIST}"
    echo "Set ${INFO_PLIST} CFBundleVersion = ${CI_BUILD_NUMBER}"
else
    echo "CI_BUILD_NUMBER not set (expected in Xcode Cloud); leaving CFBundleVersion as-committed"
fi
