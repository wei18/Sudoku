# Minesweeper App Icon — Design Spec

**Designer**: UI Designer (Claude subagent)
**Date**: 2026-06-01
**Status**: spec ready for image-generation handoff
**Sibling reference**: Sudoku's existing `AppIcon-Light/Dark/Tinted.png` (diagonal trio on warm paper)

## Status update (2026-06-01, post user review)

User confirmed direction:
- **Light + Dark only** — Tinted variant **NOT adopted** (user explicitly declined).
- **Single 1024×1024 PNG per appearance** — no macOS size ladder. Apple's compositor scales from the 1024 across all surfaces (Springboard, Finder, Spotlight, etc.). Trades pixel-perfect control at 16×16 / 32×32 for asset-pipeline simplicity.

Sections §6 (variant table) and §7 (16×16 simplification) below are retained for reference but their Tinted / small-ladder portions are out-of-scope for shipping. §8 prompt is unchanged — it produces a single 1024 master that becomes Light, and the same prompt with the §6 Dark-variant swap produces the Dark master.

## 1. Concept summary

A single **cartoon mine** — round, matte, with eight short radial spikes and a stubby lit fuse — sits dead-center on a warm paper field, framed inside the same 24% rounded clip Sudoku uses. The mine is rendered in deep ink-black `#1F2227` with a soft warm-paper highlight on the upper-left curve, so it reads as a hand-drawn object on graph paper, not a CGI bomb. Tucked into the lower-right quadrant, a **small red triangular flag** on a slim charcoal pole leans toward the mine — the flag is the secondary motif and the splash of saturated color that makes the icon pop at thumbnail size. The background is the canonical Sudoku-family warm paper `#FAF8F3` in light mode, with the faintest 2pt-stroke graph-paper grid ghosted behind the mine at 6% opacity. Reads like a Sunday newspaper puzzle page, not a video-game splash.

## 2. Brand-family hook

**The warm-paper background + the ghost graph-paper grid behind the hero object.** Sudoku puts the 3×3 grid in the foreground; Minesweeper pushes it to a 6%-opacity backdrop and places a found-object on top. Same paper, same grid, different protagonist — instant "same publisher, same shelf."

## 3. Primary motif decision — mine + red flag

Defended against alternatives:
- **Grid of cells alone** — collides with Sudoku's silhouette at thumbnail size.
- **Number tiles (1/2/3)** — dense, only legible to existing players, dies at 60×60.
- **Explosion / shrapnel** — loss state, bad first impression, HIG discourages.
- **Mine alone** — reads as 8-ball / cherry bomb without flag context.
- **Flag alone** — ambiguous (golf? CTF? bookmark?).

Mine = hero (globally recognized Minesweeper primitive, in emoji 💣). Flag = supporting character + color punch. Two objects, clear hierarchy.

## 4. Color palette

| Role | Hex | Notes |
|---|---|---|
| Background — warm paper | `#FAF8F3` | Identical to Sudoku Light. The sibling anchor. |
| Ghost grid lines | `#5C7A4F` at 6% opacity | Sudoku's sage, dialed down to a whisper. |
| Mine body — ink | `#1F2227` | Near-black with a hint of cool. Fountain-pen feel. |
| Mine highlight | `#FAF8F3` at 35% opacity | Single soft crescent upper-left. Flat ellipse, no gradient. |
| Fuse — body | `#6B5847` | Warm brown, jute-rope feel. |
| Fuse — spark | `#E6A857` | Sudoku's amber (the warm-family hook). Single 24pt dot at fuse tip. |
| Flag — fabric | `#C8453A` | Saturated brick-red. Higher chroma than Sudoku's clay `#C97D5F`. Minesweeper is louder. |
| Flag — pole | `#2A2D33` | Dark charcoal, matches mine ink family. |

**Tinted-variant monochrome derivation**: drop hues, keep luminance only. Mine = `#FFFFFF` solid on transparent; flag fabric = `#FFFFFF` at 70% luma; flag pole + fuse spark merge into the mine ink. Ghost grid: drop entirely. Tinted icon = mine silhouette + flag silhouette, two solid shapes.

**Dark-mode background**: `#15171A` (canonical Sudoku dark surface). Mine becomes `#FAF8F3` (paper-on-ink inversion). Flag fabric stays `#C8453A` — red on dark navy/charcoal pops, no recoloring. Ghost grid: sage `#9BB87E` at 6%.

## 5. Composition (1024×1024 canvas)

```
0                                                          1024
+----------------------------------------------------------+ 0
|                  <-- 24% rounded clip -->                |
|                                                          |
|     . . . . . . . . . . . . . . . . . . . . . . . .      |
|     .   .   .   .   .   .   .   .   .   .   .   .       |
|     . . . . . . . . . . . . . . . . . . . . . . . .      | ~150
|     .   .   .   .   .   .   .   .   .   .   .   .       |  (ghost grid
|     . . . . . . . . . . . . . . . . . . . . . . . .      |   8×8 cells,
|     .   .   .   .   .   .   .   .   .   .   .   .       |   6% opacity)
|     . . . . . . . . . . . . . . . . . . . . . . . .      |
|                                                          |
|                       /  (fuse ~30°)                     | ~320
|                      *  ← amber spark                    |
|                     /                                    |
|                  ___|__                                  |
|                /        \                                |
|             ⟍|          |⟋   ← 8 short radial spikes    |
|              |    MINE   |                               | ~512 (center)
|             ⟋|          |⟍                              |
|                \________/                                |
|                                                          |
|                                                  ▲       | ~700
|                                                ▲ █       |  (flag triangle
|                                                ███       |   ~140pt tall)
|                                                  █       |
|                                                  █       |
|                                                  █       |  pole
|                                                  █       |
|                                                          | 1024
+----------------------------------------------------------+
```

**Spec values**:
- Canvas: 1024×1024, rounded clip rx=ry=246 (24%, matches Sudoku).
- Mine: circle radius 200pt, center `(512, 540)`. 8 short radial spikes, length 50pt, width 40pt base → flat tip.
- Highlight crescent: ellipse 90×60pt centered at `(440, 470)`, `#FAF8F3` 35% opacity.
- Fuse: 2pt line `(630, 380) → (680, 310)`, color `#6B5847`. Amber spark = filled circle r=24pt at `(680, 310)`.
- Flag: pole rect 12×200pt at `(820, 600)`, color `#2A2D33`. Triangle vertices `(820, 600)`, `(820, 700)`, `(720, 650)`, fill `#C8453A`.
- Ghost grid: 8×8 cells (128pt each), 2pt stroke `#5C7A4F` at 6% opacity. Mine + flag composite on top.

**Depth cues**: no skeuomorphic shadow. Depth from (a) overlap (flag occludes mine spike), (b) the highlight crescent faking upper-left light source, (c) fuse curving away in pseudo-3/4 view.

## 6. Variant table

| Variant | Background | Mine | Highlight | Flag fabric | Flag pole | Ghost grid |
|---|---|---|---|---|---|---|
| **Light** | `#FAF8F3` | `#1F2227` | `#FAF8F3` @ 35% | `#C8453A` | `#2A2D33` | `#5C7A4F` @ 6% |
| **Dark** | `#15171A` | `#FAF8F3` | `#1F2227` @ 30% | `#C8453A` (unchanged) | `#FAF8F3` @ 80% | `#9BB87E` @ 6% |
| **Tinted** | transparent (Apple composites) | `#FFFFFF` solid | none | `#FFFFFF` @ 70% luma | merged into mine ink | omitted |

**Tinted survival strategy**: mine luma 1.0, flag luma ~0.70 → distinct under any system tint, never merge into one blob.

**Dark rationale**: paper-on-ink inversion (Sudoku does same). Red flag stays saturated as the secondary multi-color hook.

## 7. Small-size simplification (16×16 macOS Finder sidebar)

At 16×16:
- **Mine**: 10×10 filled black circle, center-slightly-low. 8 spikes → 4 cardinal nubs only (1×2px each, N/S/E/W).
- **Highlight**: dropped.
- **Fuse + spark**: dropped (sub-pixel noise).
- **Flag**: 2×2 red pixel cluster at lower-right of mine. No pole. **Load-bearing**: without the red dot, the icon dies (reads as 8-ball / coffee).
- **Ghost grid**: dropped.
- **Background**: solid `#FAF8F3`.

Ship simplified at 16×16 and 32×32. Full composition at 128×128+. Break point: 64×64.

## 8. Image-generation prompt — paste into Midjourney / DALL-E

> A bold flat-design app icon, square 1:1 with 24% rounded corners. Centered: a round cartoon mine bomb, matte ink-black `#1F2227`, with eight short stubby radial spikes evenly spaced, and a short thin brown jute fuse `#6B5847` curving up-and-right from the top with a single warm amber spark `#E6A857` at its tip. A soft warm-paper highlight crescent on the upper-left curve of the mine for subtle volume — no gradient, just a single soft-edged light shape. Tucked at the lower-right, a small red triangular flag in saturated brick-red `#C8453A` on a slim charcoal pole `#2A2D33`, the flag triangle pointing toward the mine. Background: warm paper cream `#FAF8F3` with a very faint sage `#5C7A4F` 8×8 graph-paper grid ghosted at 6% opacity behind the objects, like a Sunday newspaper puzzle page. The mine and flag composite cleanly over the grid. Vector-style, flat shapes, no photorealism, no skeuomorphism, no drop shadow, no bevel, no metallic sheen, no glow, no sparkle effects, no text, no numbers, no letters. Composition centered with ~10% inset on all sides. Sibling visual family to a Sudoku app icon on the same warm paper. Mood: calm puzzle craftsmanship, friendly not menacing, Sunday-paper not Hollywood. 1024×1024.
>
> **Negative prompt / no**: photorealism, 3D render, ray tracing, metallic surface, chrome, glossy reflection, explosion, fire, smoke, sparks burst, glitter, lens flare, drop shadow, bevel, emboss, gradient background, neon, cyberpunk, retro pixel art, isometric perspective, multiple mines, mine field, character mascot, eyes on the mine, anthropomorphic, text, numbers, letters, watermark, signature, frame, border, busy background, navy blue background.

## 9. Three alternate directions

### Alt A — "Flag plants itself"

Invert the hierarchy. **Red triangular flag large + centered** (~60% canvas), planted vertically. The mine becomes a **small black-and-spike silhouette in lower-left quadrant**, partially hidden behind the flag pole — gameplay narrative is "marked, defused." Same palette + paper + grid. Reads more victorious / less ominous. Risk: a centered red triangle on cream can flicker as warning sign / rotated play-button at thumbnail.

### Alt B — "Numbered cell trio" (strongest sibling reading)

Echo Sudoku's three-cell motif. Drop mine entirely. **Three Minesweeper number tiles** in diagonal trio mirroring Sudoku's Light layout: "1" blue `#3B6FB8`, "2" green `#3B8B5A`, "3" red `#C8453A` (canonical Windows colors). 4th off-diagonal cell = unrevealed flat sage `#5C7A4F`. Strongest sibling-ness via structural twin (same diagonal as Sudoku) plus warm paper. **Risk**: loses iconic mine, non-players may not parse as Minesweeper.

### Alt C — "Tile flip reveal" (most designerly)

Single large square tile centered at ~45° rotation mid-flip, caught revealing what's underneath. Face-up = flat-ink mine; face-down (trailing edge) = sage `#5C7A4F`. Implies motion through tilted-square geometry, no motion blur. Background: warm paper, no ghost grid. Flag/fuse dropped — single object, single moment. Most sophisticated, least literal. Risk: reads as Minesweeper to players but as "abstract origami / kite" to non-players.

## Handoff next steps for user

1. Paste §8 prompt into Midjourney/DALL-E → generate 4–6 candidates of primary direction.
2. If primary doesn't land in 2 prompt iterations → fall back to **Alt B (strongest sibling-ness)** or **Alt A (flag-hero)**.
3. Once 1024×1024 lands → vector cleanup pass (Affinity trace or manual SVG redraw) → export per the iOS trio (Light/Dark/Tinted) + macOS 10-PNG ladder per `meetings/2026-05-23_appicon-multiplatform.impl-notes.md` workflow.
4. Final PNGs land at (per the simplified pipeline confirmed 2026-06-01):
   - `Minesweeper/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png` (1024×1024)
   - `Minesweeper/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png` (1024×1024)
   - **No** `AppIcon-Tinted.png` — `Contents.json` will omit the tinted appearance entry.
   - **No** `AppIcon-macOS.appiconset/` — single-asset universal AppIcon serves both iOS and macOS; `Project.swift` will drop the SDK-scoped `ASSETCATALOG_COMPILER_APPICON_NAME[sdk=macosx*]` override for Minesweeper.

## Production record (executed 2026-06-01)

How the v1 ship art was actually produced (gap-filling — Sudoku's first-pass icon left this SVG→PNG step undocumented). Codified as the project skill `.claude/skills/app-icon-rasterize/SKILL.md` so app #3 reuses the same path.

1. **UI Designer subagent** read this spec and authored two production-clean SVG files: `/tmp/minesweeper-icon-light.svg` + `/tmp/minesweeper-icon-dark.svg`. Single `<polygon id="spike">` in `<defs>` repeated via 8× `<use transform="rotate(N*45)">` for mathematical spike identity. Flat shapes only — no `<filter>` blurs, no `<text>`, no embedded fonts (QuickLook's SVG generator rasterizes those unreliably).
2. **Rasterize via `qlmanage`** (ships with macOS — no Homebrew, no Cloud round-trip):
   ```bash
   qlmanage -t -s 1024 -o /tmp /tmp/minesweeper-icon-light.svg /tmp/minesweeper-icon-dark.svg
   ```
   Produces 1024×1024 8-bit RGBA PNGs. Quirk: `qlmanage` appends `.png` instead of swapping the extension, so output is `light.svg.png` not `light.png`. Rename inline via `mv` to drop the `.svg.png` artifact.
3. **Commit SVG sources** at `docs/app-store/icons/minesweeper/{light,dark}.svg` as source-of-truth for re-export.
4. **Commit PNGs** at `Minesweeper/Assets.xcassets/AppIcon.appiconset/AppIcon-{Light,Dark}.png`.
5. **Designer flagged but not resolved**: dark-mode fuse brown `#6B5847` on `#15171A` runs ~3:1 contrast and nearly disappears. Open polish question — does the fuse need a dark-only lightened tone, or is "barely visible" the intended vibe (the spark, not the fuse, is the load-bearing element)?

Tools considered + rejected: `rsvg-convert` / `inkscape` / `imagemagick` / `cairosvg` — all need Homebrew, not installed on the project Mac. `sips` doesn't read SVG. `qlmanage` is the only macOS-native single-command path that produces the exact PNG shape Apple's asset catalog wants.
