---
name: app-icon-rasterize
description: Rasterize a designer-authored 1024×1024 SVG into the PNG that Apple's asset catalog wants — no Homebrew dependency, no Cloud service, just `qlmanage` already on the Mac.
---

# App icon rasterize (SVG → 1024 PNG)

Use when a designer hands off the icon as SVG and you need the PNG that `AppIcon.appiconset/Contents.json` references.

This is the gap that bit the team on 2026-06-01 — Sudoku's first-pass icon production left the SVG → 1024 PNG step undocumented (only the downstream Pillow Lanczos *downscale* to the macOS ladder was written up). Following the 2026-06-01 simplification (single 1024 universal PNG, no Tinted, no macOS ladder) there is exactly one rasterize step per appearance and it is documented here.

## When to use

- Designer subagent (or human designer) produced a clean `light.svg` + `dark.svg` matching the icon spec
- You need the matching `AppIcon-Light.png` + `AppIcon-Dark.png` in `<app>/Assets.xcassets/AppIcon.appiconset/`
- This Mac does NOT have `rsvg-convert`, `inkscape`, or `imagemagick` (verified absent on the project Mac as of 2026-06-01; Homebrew is not installed)

## When NOT to use

- The SVG uses `<filter>` blurs, `<text>`, embedded fonts, or other features QuickLook's SVG generator may render unreliably. Re-author the SVG with flat shapes first.
- The SVG already ships as PNG from the designer (e.g. Affinity / Figma export). Just commit the PNG.

## SVG authoring contract — read BEFORE writing the SVG

The designer's SVG **must NOT** bake rounded corners into the artwork. Apple's compositor applies the squircle mask at render time (iOS Springboard, macOS Dock, every preview surface). Baking corners produces a *double-mask* look — the icon shows up smaller than its peers with visible inner padding.

Common mistakes that cause this:

```xml
<!-- WRONG — corners baked into the artwork via clipPath -->
<defs>
  <clipPath id="iconMask">
    <rect width="1024" height="1024" rx="246" ry="246"/>
  </clipPath>
</defs>
<g clip-path="url(#iconMask)">
  <rect width="1024" height="1024" fill="#FAF8F3"/>
  ...
</g>

<!-- ALSO WRONG — rx/ry directly on the background rect -->
<rect width="1024" height="1024" rx="246" ry="246" fill="#FAF8F3"/>
```

```xml
<!-- RIGHT — background fills 1024×1024 to the edges, no clip, no rx/ry -->
<rect x="0" y="0" width="1024" height="1024" fill="#FAF8F3"/>
<!-- artwork on top, also no clip -->
```

After rasterize, `sips -g hasAlpha …png` will still report `yes` because QuickLook writes 8-bit RGBA — but every pixel including the corners must be **opaque**. Quick check: open the PNG in Preview at 100%, hover the corners — Digital Color Meter should report the background color (e.g. `#FAF8F3`), not transparency.

This rule applies to both Light and Dark variants. There is no platform on which the artwork should pre-apply its own squircle.

## Procedure

```bash
# 1. Designer writes SVG to ../tmp/ (project-scope scratch
#    dir, NOT /tmp — see feedback-project-scope-auto-execute). Each SVG must
#    declare width="1024" height="1024" viewBox="0 0 1024 1024".
ls -la ../tmp/minesweeper-icon-light.svg ../tmp/minesweeper-icon-dark.svg

# 2. Rasterize via QuickLook thumbnail generator.
#    -t           thumbnail mode
#    -s 1024      thumbnail size (square)
#    -o <dir>     output directory (-o cannot rename the file, see step 3)
qlmanage -t -s 1024 -o ../tmp \
  ../tmp/minesweeper-icon-light.svg \
  ../tmp/minesweeper-icon-dark.svg

# 3. qlmanage's quirk: it APPENDS `.png` to the source filename instead of
#    swapping the extension. So `light.svg` becomes `light.svg.png`. Rename
#    directly into the asset catalog so the .svg.png artifact never lingers.
mv ../tmp/minesweeper-icon-light.svg.png \
   Minesweeper/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png
mv ../tmp/minesweeper-icon-dark.svg.png \
   Minesweeper/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png

# 4. Verify dimensions + format.
file Minesweeper/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png
# expected: PNG image data, 1024 x 1024, 8-bit/color RGBA, non-interlaced
sips -g pixelWidth -g pixelHeight Minesweeper/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png
# expected: pixelWidth: 1024 / pixelHeight: 1024

# 5. Commit the SVG source-of-truth alongside, under docs/app-store/icons/.
mkdir -p docs/app-store/icons/<app>/
cp ../tmp/<app>-icon-light.svg docs/app-store/icons/<app>/light.svg
cp ../tmp/<app>-icon-dark.svg  docs/app-store/icons/<app>/dark.svg
```

## Verify visually

Open the produced PNGs in Preview.app and confirm:

- Background fill reaches all 4 edges (no transparency at canvas border — Apple's compositor adds the squircle mask)
- Light variant uses paper `#FAF8F3` background
- Dark variant uses ink `#15171A` background
- Colors match the spec hex values byte-for-byte
- No anti-alias bleed from `<filter>` effects (rare with QuickLook, but inspect the highlight + spark ring areas)
- Both PNGs are 1024×1024 exactly (no off-by-one from QuickLook scaling)

If any check fails, the fix lives in the SVG, not in a post-process pass — re-edit, re-rasterize.

## Asset-catalog metadata

`AppIcon.appiconset/Contents.json` must reference both PNGs as universal idiom (no `"platform": "ios"`), so Apple auto-adapts the 1024 master across iOS + macOS:

```json
{
  "images" : [
    {
      "filename" : "AppIcon-Light.png",
      "idiom" : "universal",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        { "appearance" : "luminosity", "value" : "dark" }
      ],
      "filename" : "AppIcon-Dark.png",
      "idiom" : "universal",
      "size" : "1024x1024"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

No Tinted entry (intentionally excluded per 2026-06-01 user direction). No `AppIcon-macOS.appiconset/` (universal idiom covers macOS via auto-scale).

## Why qlmanage and not X

| Tool | Reason rejected |
|---|---|
| `rsvg-convert` (librsvg) | Requires Homebrew, not installed on this Mac |
| `inkscape --export-png` | Requires Homebrew or .app install |
| `imagemagick convert` | Requires Homebrew |
| `sips` | Does not read SVG input on macOS as of Sequoia |
| `cairosvg` (Python) | Requires Homebrew (Cairo system lib) |
| Pillow | No SVG support natively |
| Swift + WebKit CLI | Works but ~80 LOC of bespoke code for a one-step thumbnail render that `qlmanage` already does |
| Browser screenshot | Manual, unreproducible across machines |

`qlmanage` ships with macOS, takes one command, outputs the exact PNG shape Apple wants. The trade-off is that QuickLook's SVG generator may diverge slightly from full-spec SVG 1.1 — keep the SVG simple (flat shapes, no filters, no text) and the output is faithful.

## Companion skill

For the Sudoku icon's macOS size-ladder downscale workflow (which is now retired per the 2026-06-01 universal single-PNG decision but was the team's earlier process), see `meetings/2026-05-23_appicon-multiplatform.impl-notes.md`.
