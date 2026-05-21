# AppIcon ↔ Brand Audit — 2026-05-21

**Auditor**: Brand Guardian (sub-agent), READ-ONLY
**Inputs**: `docs/app-store/icons/finalists/{light-difficulty-trio,dark-geometric-burst}.svg`, `App/Assets.xcassets/AppIcon.appiconset/{Contents.json,AppIcon-Light.png,AppIcon-Dark.png}`, `docs/designs/design-system.md` (canonical brand essence), `docs/design-mockup.html`, `docs/designs/03-daily-hub.md`, `docs/designs/04-practice-hub.md`, `docs/designs/05-board.md`, `docs/foundations.md`.

## Verdict

**Yellow** — the light finalist (07) introduces two non-system colors (clay `#C97D5F`, amber `#E6A857`) that have **no counterpart** anywhere in the in-app design token set, and binds them to a difficulty taxonomy that the in-app UI does not color-encode at all. The dark finalist (09) further escalates: it adds a fourth invented color (lavender `#B5A6D6`) and recolors the grid in amber — a treatment that contradicts `cell.error`/accent semantics from `design-system.md`. The two icons read as **two different brands**, not siblings. None of this is fatal — both icons are individually competent and on-brief for "Sudoku grid" — but the system-coherence story is broken and needs one of: (a) bind the new icon palette into `design-system.md` as a real difficulty-color extension, or (b) repaint both icons to honor the sage+warm-paper restraint that the rest of the App is committed to.

## Two-icon coherence

**Strangers, not siblings.**

Shared scaffolding:
- Same 3×3 grid geometry, same 200pt cell modules, same 600pt grid box centered with ~15% margin, same `stroke-linecap="square"`.

Where they diverge enough to read as different products:
- **Background**: 07 = `#FAF8F3` warm paper (canonical `surface.background` light). 09 = navy radial gradient `#34487A → #2A3B5C` — **navy is not in the dark-mode design token set**. Canonical `surface.background` dark is `#15171A`, `surface.primary` dark is `#1E2024`. Navy is a brand-new hue.
- **Grid stroke**: 07 = sage `#2E5135` (a darker variant of `accent.primary` light `#5C7A4F`). 09 = amber `#E6A857`. Switching the line color from sage to amber across light/dark **breaks the App's own contract**: in `design-system.md` the dark accent is `#9BB87E` (lighter sage), not amber. Amber has no design-system role at all.
- **Cell composition**: 07 = diagonal trio (3 filled cells along anti-diagonal). 09 = pinwheel (4 corners + soft amber center). Different *semantic* layout, not just different colors.

The only visual tie is the 3×3 grid + the cell side `212–812` framing. That is structural, not stylistic. A user landing on the App Store light listing and then re-opening dark would see "different app, same puzzle".

**Minimum change to make them siblings** (if direction is kept):
1. Keep 09's navy bg, but recolor the grid strokes to dark-mode sage `#9BB87E` (the canonical dark accent). Drop the amber lines.
2. Recolor 09's pinwheel cells from `sage/clay/amber/lavender` to a 4-tone variant of the **07 palette** (sage / clay / amber / amber-darker), removing the lavender invention.
3. Adopt 09's pinwheel layout in light too, OR keep diagonal in light but ensure both use the same number of filled cells. Two different cell-layout metaphors across light/dark is the strongest "stranger" signal.

## Findings

### S1 (must fix before App Store submission)

**S1-A. Tinted slot points at the light multi-tone PNG** (`Contents.json:19-29`).
iOS tinted mode renders the icon as a single-channel grayscale + system tint. The light finalist has 3 distinct mid-saturation fills (sage / clay / amber); under grayscale these collapse to luminances `~0.42 / ~0.55 / ~0.66` — visible separation but the *meaning* (3 difficulty tiers) is destroyed, and the tint applied on top will produce muddy desaturated cells with the sage grid as the only readable element. The fallback is technically legal but visually substandard.
**Fix**: ship a purpose-built tinted variant — a flat sage grid on transparent/white with a single accent dot (closest to the original Concept 01 finalist `01-grid-single-dot.svg` which was the previous designer recommendation). Update `Contents.json` to point the tinted slot at it. (Issue: file currently does not exist; needs new asset.)

**S1-B. Dark icon introduces 4 non-canonical hues** (`dark-geometric-burst.svg:6-19`).
Navy gradient `#34487A/#2A3B5C`, amber grid `#E6A857`, clay `#C97D5F`, lavender `#B5A6D6` — none of these exist in `docs/designs/design-system.md`. The App's own brand essence statement says "**one accent color used sparingly**" (`design-system.md:11`). Four invented hues + a gradient is the polar opposite of that contract.
**Fix**: either (a) repaint dark icon using only `surface.background dark #15171A` bg + sage `#9BB87E` strokes + the same 07 trio in dark variants, OR (b) escalate the palette extension to design-system.md (see §未決 below) and accept the icon as the trigger that broadens the brand.

**S1-C. macOS rounded-rect framing** (both SVGs).
iOS auto-masks AppIcons with the squircle. macOS does **not** auto-round — the icon ships as a literal square unless the artwork includes its own rounded corners. Both finalists are full-bleed rectangles with no intentional corner radius. On macOS Dock / Launchpad / Finder, both icons will render as hard squares against the dark/light bg, looking unfinished next to system apps with native squircle corners.
**Fix**: add a `clipPath` with a 24% corner radius (per Apple macOS template) inside both SVGs, OR ship two separate raster variants per platform and split `Contents.json` by idiom. Per #70 the AppIcon now serves macOS; this is no longer optional.

### S2 (should fix before TestFlight)

**S2-A. 07's difficulty-color metaphor has zero in-app reinforcement.**
`docs/designs/03-daily-hub.md`, `04-practice-hub.md`, `05-board.md` all label difficulty in plain text ("Easy" / "Medium" / "Hard") with `text.primary` color. There is **no `difficulty.easy/medium/hard` token** in the design system, and the only colored treatment of a card is `accent.muted` (sage) for selection. A first-time user who notices 07's three-tone grid will not have any in-app moment that reinforces "sage = Easy, clay = Medium, amber = Hard". The icon teaches a vocabulary the App never speaks.
**Fix**: either (a) extend `design-system.md` with formal `difficulty.{easy,medium,hard}` tokens (`#5C7A4F / #C97D5F / #E6A857` or whatever the icon should canonize), and apply them to DailyHubView cards + Picker tints; (b) drop the multi-tone trio and ship a single-tone variant (all sage); (c) accept the icon as decorative-only and stop describing its trio as a difficulty mapping in marketing copy.

**S2-B. "Calm" violation on 07's amber + clay** (`design-system.md:11`).
Brand essence is "Calm graph paper, lit by daylight … low chroma, high contrast text, restrained accent." Clay `#C97D5F` (chroma ~50 LCh) and amber `#E6A857` (chroma ~58 LCh) are notably higher chroma than the canonical sage `#5C7A4F` (chroma ~28 LCh). They read as warm and inviting, not necessarily un-calm, but they push past the "restrained accent" line the design system draws. Mid-saturation warm trio is acceptable on a *postcard* icon but is a directional choice that the rest of the App does not back up.

**S2-C. 09 pinwheel motion vs "Sudoku is a focus exercise, not a slot machine"** (`design-system.md:11`).
The pinwheel layout (4 corners + soft center) reads as **rotational motion** at small sizes — even though the SVG is static, the eye traces a circular path through the rotating palette. The brand essence explicitly contrasts itself against "slot machine" energy. A pinwheel is closer to slot-machine than graph-paper. The light finalist's diagonal trio reads as static progression and is more on-brand.

### S3 (nice to have)

**S3-A. Drop-shadow on 07** (`light-difficulty-trio.svg:7-8`).
Two stacked offset rects at 8%/10% opacity to fake a soft shadow. `design-system.md:11` says "no skeuomorphic shadows." The shadow is subtle but it is a shadow. Either drop it or formalize it (e.g. document as "1px ink line below the grid box, calligraphic mark, not depth").

**S3-B. 60px legibility quick check.**
- 07 at 60px: the 3 filled cells become 12×12 px squares, the sage grid strokes (12pt at 1024 → 0.7px at 60) **vanish entirely** at native @1x and barely register at @2x. The icon collapses to "3 colored dots on cream" — readable as decorative but loses Sudoku semantics.
- 09 at 60px: the 4 corner cells are 12×12 px each, navy bg dominates, amber grid strokes (14pt → 0.8px at 60 @1x) also disappear. The icon collapses to "4 colored corners on navy" — reads as abstract more than Sudoku.

Both icons are designed for the 1024 hero shot and degrade noticeably below 120px. Acceptable for App Store listing thumbnail (120px+) but Home Screen icons render at 60–76pt for Spotlight / Settings.
**Fix**: either thicken grid strokes to 16-18pt (gains at small sizes, costs slight elegance at hero), or add a tiny @1x-targeted simplification (e.g. drop subdivision lines below 80px and ship only the outer box + cells).

**S3-C. PNG file size delta** (Light 22KB, Dark 592KB).
Dark PNG is 26× the size of the light PNG. Likely cause: the radial gradient. Either flatten the gradient to a solid `#2A3B5C` (loses depth but saves ~570KB and matches the design-system convention of flat surfaces), or pre-quantize the gradient PNG via `pngcrush` / `oxipng`.

## §未決 to escalate to Leader

1. **Difficulty palette binding** — does the project want to extend `docs/designs/design-system.md` with `difficulty.{easy,medium,hard}` color tokens (`#5C7A4F` / `#C97D5F` / `#E6A857`) and roll them out to DailyHubView cards + PracticeHubView Picker tints? If yes, this is a §How update + token additions + snapshot refresh in `docs/designs/0X-*.md`. If no, the 07 icon's multi-tone metaphor is **decorative-only** and marketing copy must not describe it as a difficulty trio.

2. **Tinted variant strategy** — paint a dedicated tinted asset (recommend reusing the Concept 01 `01-grid-single-dot.svg` shape: flat sage grid + single accent dot, single-channel friendly), or accept iOS auto-tinting of the multi-tone light PNG (currently the case via `Contents.json`)? The current setup will produce a muddy tinted result on Home Screen Tinted appearance.

3. **macOS rounded-rect framing** — both finalist SVGs assume iOS squircle masking. After #70 removed `platform:ios`, the icon also ships to macOS where corners are not auto-applied. Decision: (a) add 24% corner radius to artwork (one icon for both platforms, slightly suboptimal on iOS since the squircle is not a circle), (b) split assets per-idiom in `Contents.json` (more work, cleanest result), or (c) accept hard square corners on macOS as an intentional aesthetic.

4. **Two-icon sibling-ness** — accept the current "navy world / paper world" split as intentional dramatic contrast (rare for App Icons; HIG implicitly discourages but doesn't forbid), or unify under one visual language (recommend: keep 07 diagonal in light, mirror it in dark with `#15171A` bg + lighter sage strokes + dark-mode trio of the same three hues)?
