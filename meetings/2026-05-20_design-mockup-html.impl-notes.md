# Design Mockup HTML — Implementation Notes

**Date**: 2026-05-20
**Artifact**: `docs/design-mockup.html`
**Skill**: `.claude/skills/ios-design-mockup`
**Status**: COMPLETE

---

## §設計決定 (Design decisions)

### Layout: flow-per-row (not column-per-flow)
- 18 screens in 6 horizontal flow rows (Entry / Daily / Practice / Board / Completion / Leaderboard+Settings). Reading order is left→right within a row, top→bottom across rows.
- Reason: 18 screens won't fit on one horizontal scroll comfortably; row-grouping mirrors the spec's per-View doc structure (1 file per row of frames).

### Arrow routing
- **Intra-row arrows**: gentle S-curve cubic Bezier between phone-right and phone-left, vertical center.
- **Inter-row arrows** (e.g. S02→S03 jumps from row 1 to row 2): vertical drop with curve, exiting bottom edge of source, entering top edge of target, routed in the gap *between* phones to avoid overlap.
- **Double-headed scope toggle** (S15↔S16): horizontal arc connecting the two leaderboard frames in the same row.
- All arrows live in **one** `.arrows-layer` SVG covering the whole canvas with `pointer-events: none`.

### Tokens panel — bottom, full-width
- Right-side panel would feel cramped against an 18-screen canvas. Bottom is the better home.
- Sections: Brand essence, Colors (split into Surfaces / Cells / Text / Accent / Status), Typography (with samples), Spacing, Radius, Shadow, Components (Mode Card / Daily Card / Picker / Board Cell / Digit Pad / Hero / Settings Row).
- Each component sample matches the actual app theme (sage + warm paper), not generic iOS.

### Sage + warm-paper theme application
- `--color-tint` overridden to `#5C7A4F` (was system blue `#007AFF`).
- `--color-bg` overridden to `#FAF8F3` warm paper (was `#FFFFFF`).
- Apple HIG baseline values are documented **side by side** in the tokens panel as a comparison column so the reader sees both.
- Cell colors come from project's design-system.md, not from generic iOS semantic.

### Font sizing
- All in-frame text uses SwiftUI semantic scale literals from design-tokens.md (`.body` 17/22, `.title3` 20/25, `.largeTitle` 34/41 etc.). No custom sizes.
- Cell digit on Board: `font-size: 22px` (≈ 36pt cell × 0.6 conversion factor).

### Cell rendering on Board screens (S09, S10, S11)
- 9×9 grid uses CSS grid with `grid-template-columns: repeat(9, 1fr)`.
- Box separators rendered via `box-shadow: inset` on the inner cells (1.5pt at every 3rd boundary). Avoids cell-element-count blowup.
- S11 error cell: triple encoding — bg tint, top-left red triangle (CSS `clip-path`), red digit color.

---

## §偏離 (Deviations from skill defaults)

1. **Arrow legend extended** — added a 5th style (double-headed) and a 6th color (sage tint) so the legend reflects sage-themed arrows, not the skill's default iOS blue.
2. **Skill's arrow color** `#007AFF` replaced with the project's accent `#5C7A4F` (sage) for solid push arrows. Dashed remains `#FF9500` (orange) to retain visual distinction.
3. **Default `--color-tint` reassigned** from `--color-system-blue` to a new `--color-accent-sage` per the project's design system. Documented in the tokens panel.
4. **Status bar time** uses `15:51` per the user's spec (Leader's brief), not the skill's default `9:41`.
5. **Tokens panel section "Brand essence"** added (not in skill default) — quotes design-system.md "Calm graph paper, lit by daylight."

---

## §折衷 (Tradeoffs considered)

- **Column-per-flow vs flow-per-row** — column would stack vertically per flow group; chose row because the spec already organizes content top-to-bottom flow-by-flow in `docs/designs/0X-*.md`. Row layout maps 1:1 to the doc structure.
- **Right-side vs bottom tokens panel** — chose bottom because the canvas is wide (18 phones × ~480px = ~8600px); a right panel would be unreachable at print scale.
- **Inline SVG icons vs emoji** — followed skill rule, used inline SVG. The "calendar / dice / trophy / gear" icons on Home mode cards are stylized SVG redraws of SF Symbols.
- **Cell errors S11**: considered rendering all 81 cells fully populated vs the more realistic "almost complete" with 4-5 empty cells + 1 error. Chose the latter — closer to the spec's mistake scenario.

---

## §未決 (Unresolved / TODOs)

1. **S04 Daily Hub (Easy completed)** — spec shows Easy at 4:11 completed in the wireframe but doesn't lock specific times for Medium/Hard pending state. I chose `—` (em-dash) per design-system tokens convention.
2. **S05 Daily Hub all-complete** — design.md doesn't describe a "sweep day" celebration. I rendered all 3 cards with checkmarks and times (Easy 4:11, Medium 12:30, Hard 18:42), no extra celebration banner because §brand-essence forbids celebrations. **Flag for Leader review** — confirm no banner is desired.
3. **S07 Practice drawing (shimmer)** — the shimmer animation in static HTML is rendered as a darker `surface.placeholder` fill with a faint gradient stripe. CSS animation suppressed for print friendliness; would animate in browser.
4. **S17 AX3 vertical-stack row** — rendered with one example row (the user's rank 17) vertically stacked, plus 2 normal rows above. Spec doesn't say how many rows to show in AX3 mode; assumption.
5. **S13 GC unauthenticated** — used `person.crop.circle.badge.questionmark` SVG redraw. Spec mentions this SF Symbol but exact rendering is left to interpretation.

None of the above blocked completion; flagged for Leader's review pass.
