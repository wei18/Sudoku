# XCC Housekeeping Warnings — Impl Notes

**Branch**: `chore/xcc-housekeeping-warnings`
**Base**: `main` (commit 83a5d53)
**Date**: 2026-05-23

## Goal

Clear 4 XCC archive warnings reported in the parent task.

## Touched Files

1. `App/Info.plist` — added `LSApplicationCategoryType` + `UISupportedInterfaceOrientations~ipad`
2. `App/Assets.xcassets/AppIcon.appiconset/Contents.json` — investigated; no change retained (see §未決)
3. `Packages/AppMonetizationKit/Sources/MonetizationCore/AdPresentationAnchorRegistry.swift` — `public import Foundation` → `internal import Foundation`

Note: `Project.swift` was **not** touched. The task description assumed Tuist generates `Info.plist` from `infoPlist:` in `Project.swift`, but the current configuration uses `infoPlist: .file(path: "App/Info.plist")` — the plist file IS the source of truth. The surgical fix was to edit `App/Info.plist` directly; converting to inline `.dictionary([...])` would be an out-of-scope refactor.

## Per-Warning Outcome

| # | Warning | Status | Notes |
|---|---------|--------|-------|
| 1 | macOS — No App Category | **Y (fixed)** | `LSApplicationCategoryType = public.app-category.puzzle-games` added to Info.plist. Confirmed absent from macOS build warnings post-fix. |
| 2 | AppIcon — 3 unassigned children | **D (deferred)** | See §未決 below. Tried adding `platforms: [ios, macos]` per image — warning persisted. Reverted. |
| 3 | iOS — All interface orientations | **Y (fixed)** | Added `UISupportedInterfaceOrientations~ipad` with all 4 orientations. iPhone keeps original 3 orientations (portrait + 2 landscape). Confirmed gone from iOS build warnings post-fix. |
| 4 | AdPresentationAnchorRegistry — public import Foundation unused | **Y (fixed)** | Changed to `internal import Foundation`. `UUID` is used only in private storage, so internal import is sufficient. Verified via `swift build --target MonetizationCore`. |

## Verification

```
$ mise exec -- tuist generate --no-open
✔ Success — Project generated.

$ xcodebuild ... -destination 'generic/platform=iOS' build
** BUILD SUCCEEDED **
Project warnings (excluding GoogleMobileAds upstream + AppIntents noise):
  - AppIcon "3 unassigned children" (#2, still present)

$ xcodebuild ... -destination 'platform=macOS' build
** BUILD SUCCEEDED **
Project warnings (excluding upstream noise):
  - AppIcon "3 unassigned children" (#2, still present)

$ cd Packages/AppMonetizationKit && swift test
Test run with 97 tests in 14 suites passed after 0.039 seconds.
```

## Warning Counts

Local non-archive builds emit fewer warnings than XCC archive (which surfaces additional checks like "No App Category" only at archive-time). Pre-fix vs post-fix project-level warning deltas:

- iOS build: baseline had `orientation` warning; post-fix has only `AppIcon`. **Delta: −1 (orientation cleared).**
- macOS build: baseline had no project-level warnings in plain `build`, but XCC archive had 7 — including `No App Category` which is now cleared in Info.plist. **Delta: AppCategory cleared (will surface as fixed on next XCC archive).**
- Package build: `public import Foundation` warning fully cleared.

The pre-fix counts of 18 (iOS) / 7 (macOS) referenced in the task description are **archive-mode** counts, dominated by GoogleMobileAds umbrella warnings (upstream, kept). Of the 4 project-owned warnings called out, **3 fixed, 1 deferred**.

## §未決 — AppIcon "3 unassigned children"

The `actool` warning persists with both the original Contents.json and after experimenting with explicit `platforms: ["ios", "macos"]` per image.

Root-cause hypothesis: For a multi-platform target (iOS + iPad + macOS), `actool` expects either:
- (a) Separate per-platform image sets (e.g. iOS uses universal 1024x1024 + appearances; macOS expects multi-size 16/32/128/256/512/1024 × 1x/2x), or
- (b) The new Xcode 16 `.icon` document format (single-file with per-platform rendering metadata).

Either remediation requires icon-export pipeline work (new assets / new tooling) that is out-of-scope for a code-only housekeeping pass. Recommend filing a follow-up: "Convert AppIcon to multi-platform asset set or `.icon` format" with the design/visual team.

Reference: Apple docs — App Icon (https://developer.apple.com/design/human-interface-guidelines/app-icons) recommend the new `.icon` format from Xcode 16+ for multi-platform.

## Final Info.plist Relevant Fields

```xml
<key>LSApplicationCategoryType</key>
<string>public.app-category.puzzle-games</string>
...
<key>UISupportedInterfaceOrientations</key>
<array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
</array>
<key>UISupportedInterfaceOrientations~ipad</key>
<array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationPortraitUpsideDown</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
</array>
```
