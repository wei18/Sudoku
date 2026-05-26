#!/usr/bin/env bash
#
# generate-acknowledgements.sh — refresh App/Resources/Acknowledgements/
# from the SwiftPM dep graph.
#
# Backlog source: docs/foundations.md §Backlog (LicensePlist auto-acknowledgements).
# Trigger: v2 ships AdMob + UMP (third-party SDKs); App Store requires
# user-accessible license disclosure.
#
# Usage: scripts/generate-acknowledgements.sh
#
# Output:
#   App/Resources/Acknowledgements/Acknowledgements.md   — bundled markdown
#                                                          read by SettingsView
#   App/Resources/Acknowledgements/license_list.plist    — for completeness
#                                                          (Settings.bundle compat)
#
# Tool: github.com/mono0926/LicensePlist
# Install (Leader pre-flight, one of):
#   mise install ubi:mono0926/LicensePlist@latest    # preferred (pinned via .mise.toml)
#   brew install licenseplist                        # fallback
#
# Re-run cadence: after every SPM dep bump that adds/removes/upgrades a package.
# CI does NOT run this — manual regen + commit is the contract.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

OUTPUT_DIR="App/Resources/Acknowledgements"
mkdir -p "${OUTPUT_DIR}"

# Resolve license-plist binary. Prefer mise-managed, fall back to PATH.
if command -v mise >/dev/null 2>&1 && mise which license-plist >/dev/null 2>&1; then
    LP=("mise" "exec" "ubi:mono0926/LicensePlist" "--" "license-plist")
elif command -v license-plist >/dev/null 2>&1; then
    LP=("license-plist")
else
    echo "error: license-plist not installed. See header comment for install options." >&2
    exit 127
fi

# Run LicensePlist against both SwiftPM packages. AppMonetizationKit pulls
# the third-party SDKs (GoogleMobileAds, GoogleUserMessagingPlatform);
# SudokuKit only pulls swift-snapshot-testing (testing-only — still license-
# disclosable since the dep graph is public).
"${LP[@]}" \
    --output-path "${OUTPUT_DIR}" \
    --package-paths "Packages/AppMonetizationKit,Packages/SudokuKit" \
    --markdown-path "${OUTPUT_DIR}/Acknowledgements.md" \
    --suppress-opening-directory \
    --force

echo "Generated acknowledgements at ${OUTPUT_DIR}"
echo "Next: review the diff, commit, and verify SettingsView's Acknowledgements row renders."
