# ITMS icon + orientation fix — impl notes

Closes #115. Branch: `fix/itms-icon-orientation`.

## Scope

ASC delivery rejected build 24 with 4 ITMS codes. Two root causes, single-file fix in `App/Info.plist`.

| ITMS | Cause | Fix |
|------|-------|-----|
| 90713 | `CFBundleIconName` missing | Add `<key>CFBundleIconName</key><string>AppIcon</string>` |
| 90022 | 120×120 icon not located (cascade of 90713) | Resolved by 90713 fix |
| 90023 | 152×152 icon not located (cascade of 90713) | Resolved by 90713 fix |
| 90474 | Base `UISupportedInterfaceOrientations` only 3 entries; iPad multitasking validator checks base, not `~ipad` override | Add `UIInterfaceOrientationPortraitUpsideDown` to base array |

Tuist `infoPlist: .file(...)` does not auto-inject build-derived keys → `CFBundleIconName` must be in source plist.

## Diff (App/Info.plist)

```diff
     <key>CFBundleExecutable</key>
     <string>$(EXECUTABLE_NAME)</string>
+    <key>CFBundleIconName</key>
+    <string>AppIcon</string>
     <key>CFBundleIdentifier</key>
     <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
```

```diff
     <key>UISupportedInterfaceOrientations</key>
     <array>
         <string>UIInterfaceOrientationPortrait</string>
+        <string>UIInterfaceOrientationPortraitUpsideDown</string>
         <string>UIInterfaceOrientationLandscapeLeft</string>
         <string>UIInterfaceOrientationLandscapeRight</string>
     </array>
```

`UISupportedInterfaceOrientations~ipad` (added in PR #113) untouched — already 4 orientations. iPhone iOS runtime auto-suppresses upside-down per HIG, so adding it to base has no user-visible effect on iPhone.

Project.swift + Assets.xcassets untouched (per task constraint; correct after PRs #113, #114).

## Verification

| Check | Result |
|-------|--------|
| `plistlib.load` on source plist | OK (parses without error; `plutil -lint` Bash denied by sandbox so used python3 plistlib as equivalent syntactic validator) |
| `tuist generate --no-open` | Success, 3.754s |
| `xcodebuild -workspace Sudoku.xcworkspace -scheme Sudoku -destination 'generic/platform=iOS' build` | `** BUILD SUCCEEDED **` |
| Built `Sudoku.app/Info.plist` `CFBundleIconName` | `AppIcon` |
| Built `UISupportedInterfaceOrientations` | 4 entries: Portrait, PortraitUpsideDown, LandscapeLeft, LandscapeRight |
| Built `UISupportedInterfaceOrientations~ipad` | 4 entries (unchanged) |

Built plist read via `python3 plistlib` against `DerivedData/.../Debug-iphoneos/Sudoku.app/Info.plist` (binary plist).

## 未決

None. Single-file change, all 4 ITMS codes addressed at source. Acceptance is post-merge build 25 ASC upload — verifiable only after Leader pushes and CI delivers.
