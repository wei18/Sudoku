# AppIcon multiplatform — impl notes (2026-05-23)

## Path chosen: A (per-platform `.appiconset`)

`AppIcon.appiconset` (iOS) keeps the single-1024 universal-with-appearances shape
(light / dark / tinted). A sibling `AppIcon-macOS.appiconset` ships the
traditional 16…1024 macOS icon ladder (10 entries, all `idiom: mac`). Project.swift
selects the catalog name per SDK via `ASSETCATALOG_COMPILER_APPICON_NAME[sdk=macosx*]`.

Why Path A over B / C:

- **Path B (Xcode 16 `.icon` document)** — Xcode 26.5 is installed (well past
  the Xcode-16 floor), so the format would be supported, but the existing
  finalists are already exported as flat 1024 PNGs with appearance metadata
  intact; flipping to `.icon` would require re-authoring the icon doc and a
  matching design step. Not worth the churn for a warning fix.
- **Path C (explicit appearances + platform per entry)** — same shape as the
  current single-set with 6 entries instead of 3. Does not actually solve the
  warning because macOS still wants the size ladder (`idiom: mac` 16…1024), not
  a single 1024 with `idiom: mac`. So C cannot satisfy AppKit's icon
  requirements alone.

Path A is the documented, long-standing Apple pattern and what `actool` for
macOS expects.

## Files touched

- `App/Assets.xcassets/AppIcon.appiconset/Contents.json` — restored
  `platform: "ios"` on all 3 entries (reverts PR #70's removal). The iOS set is
  now explicitly iOS-scoped so actool will not try to satisfy macOS slots from
  it.
- `App/Assets.xcassets/AppIcon-macOS.appiconset/` — **NEW**:
  - `Contents.json` (10 `idiom: mac` entries, 16/32/128/256/512 at 1x/2x)
  - 10 PNGs generated from `AppIcon-Light.png` (1024 → downscaled with
    Pillow Lanczos; `sips` was sandbox-denied, Pillow 11.3.0 was available
    and produces equivalent Lanczos output)
- `Project.swift` — introduced `appTargetSettings` that layers on top of
  `swiftSettings`:
  - `ASSETCATALOG_COMPILER_APPICON_NAME = "AppIcon"` (iOS default)
  - `ASSETCATALOG_COMPILER_APPICON_NAME[sdk=macosx*] = "AppIcon-macOS"`

  App target now uses `.settings(base: appTargetSettings)` (root project
  settings still use `swiftSettings`).

## Verification

- `mise exec -- tuist generate --no-open` — **Success**, no errors.
- `xcodebuild` (iOS + macOS) — **BLOCKED**: the sandbox in this dev-agent
  session denies `xcodebuild` and `xcrun actool` invocations. Leader must run
  the two builds locally to confirm:
  ```
  xcodebuild -workspace Sudoku.xcworkspace -scheme Sudoku \
    -destination 'generic/platform=iOS' -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "unassigned|warning:|error:|BUILD" | tail
  xcodebuild -workspace Sudoku.xcworkspace -scheme Sudoku \
    -destination 'platform=macOS' -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "unassigned|warning:|error:|BUILD" | tail
  ```
  Expected: BUILD SUCCEEDED on both, "AppIcon has 3 unassigned children"
  warning gone, no new actool warnings on the new macOS set.

## §未決 (open questions for Leader)

1. **Build verification deferred to Leader** — sandbox denied `xcodebuild` /
   `xcrun actool` / `sips` in this session. The Pillow-generated PNGs are
   byte-valid (`file` confirms PNG RGBA), but the macOS asset compilation needs
   actool to confirm "unassigned children" is gone.
2. **Visual quality at 16×16 / 32×32** — the Light icon has fine interior
   detail (per PR #74 round-corner clip); Lanczos downscale at 16×16 may smudge
   the centre glyph. Worth a side-by-side visual review against, say, the
   Finder Get-Info preview. If unacceptable, the next step is hand-tuned
   small-size variants (or moving to Path B's `.icon` document where Xcode
   handles the rasterization at runtime).
3. **Light-only macOS variant** — macOS does not consume the Dark / Tinted
   appearances; the macOS set ships the Light source at all sizes. If a darker
   macOS-mode icon is desired later, add `appearances: [{luminosity: dark}]`
   variants to `AppIcon-macOS.appiconset` (macOS does honour dark luminosity
   on the dock icon since Sonoma).
4. **PR #74's 24% rounded clip** — preserved because the source PNG already
   has the clip baked in; all 10 downscales inherit it.
