# AppIcon S3 Polish — 2026-05-22

**Branch**: `chore/app-icon-polish`
**Scope**: Address 3 S3 polish items from `meetings/2026-05-21_app-icon-brand-audit.impl-notes.md` (issue #81).
**Executor**: UI Designer sub-agent (code-only; Leader handles git/commit/push/merge).

## Items addressed

### S3-A — Drop skeuomorphic shadow on 07 (RESOLVED)

`docs/app-store/icons/finalists/light-difficulty-trio.svg` previously stacked two offset rects (`#2E5135` at 0.08 / 0.10 opacity, offset 8–12pt down-right) to fake a soft shadow under the grid. Brand contract in `docs/designs/design-system.md` mandates **flat surfaces** ("no skeuomorphic shadows").

**Change**: Removed both shadow rects entirely (lines 14–15 deleted). No replacement hairline — flat composition reads cleaner against warm-paper `#FAF8F3` and the sage grid frame already provides sufficient anchoring. Comment string updated from "subtle drop shadow" to "flat (no skeuomorphic shadow)".

### S3-B — 60px legibility (RESOLVED in SVG)

Grid strokes were tuned for 1024 hero rendering and become hairlines at 60px @1x (Spotlight, Settings).

**Change**:
- `light-difficulty-trio.svg`: `stroke-width="12"` → `stroke-width="16"` on the sage grid group.
- `dark-geometric-burst.svg`: `stroke-width="14"` → `stroke-width="18"` on the amber grid group.

Ratio preserved (dark slightly thicker, since amber on navy needs more weight than sage on paper). Inline comments tagged `S3-B:` so future audits can find the rationale.

### S3-C — Dark PNG file size / gradient flattening (RESOLVED in SVG)

`AppIcon-Dark.png` measured 554 KB vs Light 29 KB — 19× larger due to the radial gradient (`#34487A` → `#2A3B5C`), which PNG compresses poorly.

**Change**: Replaced `<radialGradient id="navyGlow">` and its `fill="url(#navyGlow)"` reference with a flat `fill="#2A3B5C"` (the gradient's outer-stop endpoint, deeper navy). The `<defs>` gradient definition is removed entirely. This also brings the icon in line with the design-system **flat surfaces** convention (same axiom that S3-A enforces on the light icon — now consistent across the pair).

Visual impact: loses the subtle center-glow; gains brand-contract consistency. The 4-cell pinwheel + bright amber grid already carry the visual energy; the radial gradient was a cosmetic flourish, not a structural element.

## §未決 (open items — Leader to action)

1. **PNG re-rasterization is blocked in subagent sandbox.** `qlmanage` and `sips` are denied by the harness for this sub-agent. The SVG sources are correct and ready; Leader (or local terminal) must run:

   ```sh
   qlmanage -t -s 1024 -o /tmp/icons-png \
     docs/app-store/icons/finalists/light-difficulty-trio.svg \
     docs/app-store/icons/finalists/dark-geometric-burst.svg
   cp /tmp/icons-png/light-difficulty-trio.svg.png App/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png
   cp /tmp/icons-png/dark-geometric-burst.svg.png  App/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png
   sips -g pixelWidth -g pixelHeight App/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png App/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png
   stat -f '%z %N' App/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png App/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png
   ```

   Verification gates:
   - Both PNGs report `pixelWidth: 1024 / pixelHeight: 1024`.
   - Dark PNG size drops from 554 KB to < 50 KB (target; flat solid `#2A3B5C` should land ~10–25 KB, comparable to Light's 29 KB).
   - Light PNG size stays in the 25–40 KB range (slightly heavier than 29 KB due to thicker strokes adding a few more dark pixels).

2. **60px legibility eye-check.** Stroke thickening is a numeric bet (16/18 vs 12/14, +33%/+29%). Should be re-verified by viewing the rasterized PNGs scaled to 60×60 (Finder → Get Info preview, or drop into `Settings.app` icon slot). If amber strokes on `#2A3B5C` still feel thin at that size, push 09 to `stroke-width="20"` in a follow-up.

3. **Pre-rasterize PNG sizes for the commit message** (reference): Light = 29,596 B, Dark = 554,240 B. Post-rasterize sizes go into the PR body after Leader runs the qlmanage step.

## Files touched

- `docs/app-store/icons/finalists/light-difficulty-trio.svg` — shadow rects removed, stroke 12→16
- `docs/app-store/icons/finalists/dark-geometric-burst.svg` — radialGradient + defs flattened to solid `#2A3B5C`, stroke 14→18
- `meetings/2026-05-22_app-icon-s3-polish.impl-notes.md` — this file

## Files intentionally NOT touched

- `docs/app-store/icons/finalists/tinted-grid-dot.svg` (polished in #77)
- `App/Assets.xcassets/AppIcon.appiconset/AppIcon-Tinted.png` (polished in #77)
- `App/Assets.xcassets/AppIcon.appiconset/Contents.json` (asset entries unchanged)
- `App/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png` / `AppIcon-Dark.png` — **pending Leader rasterization (see §未決 #1)**
- `docs/designs/design-system.md` (frozen by #78)

## Invariants preserved

- 1024×1024 viewBox ✓
- 24% rounded-corner `clipPath` (rx/ry=246) ✓
- Cell positions `212 / 412 / 612` on a `200×200` grid module ✓
- Outer grid box `212,212 → 812,812` (600×600) ✓
- Tinted variant untouched ✓
