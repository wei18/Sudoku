#!/bin/bash
# Xcode Cloud pre-xcodebuild hook.
# Runs after dependencies are resolved (post `ci_post_clone.sh`) and right
# before `xcodebuild` starts. Mutations to `App/Info.plist` here flow into
# the archive uploaded to TestFlight / App Store Connect.
set -euo pipefail

cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/..}"

# Set CFBundleVersion from Xcode Cloud's built-in $CI_BUILD_NUMBER
# (https://developer.apple.com/documentation/xcode/environment-variable-reference).
# Local builds keep the committed "1" placeholder; Xcode Cloud builds get a
# monotonically-increasing value that satisfies ASC's "build number must
# increase" rule without manual bumps in Info.plist.
if [[ -n "${CI_BUILD_NUMBER:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${CI_BUILD_NUMBER}" App/Info.plist
    echo "Set App/Info.plist CFBundleVersion = ${CI_BUILD_NUMBER}"
else
    echo "CI_BUILD_NUMBER not set (expected in Xcode Cloud); leaving CFBundleVersion as-committed"
fi
