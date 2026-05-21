# Impl notes — App icon concepts (5 candidates)

**Branch**: `docs/app-icon-concepts`
**Date**: 2026-05-21
**Owner**: UI Designer (sub-agent)
**Status**: COMPLETE — awaiting Leader pick

## Scope

5 candidate app icons at 1024×1024 SVG + 1 README in `docs/app-store/icons/concepts/`. No Swift code; no asset catalog yet; no git ops.

## Deliverables

- `docs/app-store/icons/concepts/01-grid-single-dot.svg` (936 B)
- `docs/app-store/icons/concepts/02-nine-as-dots.svg` (773 B)
- `docs/app-store/icons/concepts/03-paper-pencil.svg` (1256 B)
- `docs/app-store/icons/concepts/04-monogram-S.svg` (938 B)
- `docs/app-store/icons/concepts/05-solved-check.svg` (1689 B)
- `docs/app-store/icons/concepts/README.md` (comparison + HIG audit + recommendation)

All SVGs < 2KB (target was < 8KB).

## Design constraints honored

- Brand: sage `#5C7A4F` + warm paper `#FAF8F3`
- No text (exception: 04 monogram, flagged in §未決)
- No gradients
- No transparency (solid `<rect>` background on every icon)
- No `<filter>`, no `<mask>`, no complex `<defs>`
- `viewBox="0 0 1024 1024"` on every file
- ~15% padding on main element
- `stroke-linecap="round"` used on Concept 05 checkmark per spec

## Visual self-check summary

| # | 60×60 legibility | Sudoku-specific reading | Calm tone |
|---|---|---|---|
| 01 | strong | strong | strong |
| 02 | strong | medium | strong |
| 03 | medium (pencil thins) | weak (faint grid disappears) | strong |
| 04 | strong | weak (no sudoku cue without text recall) | strong |
| 05 | strong (checkmark) | weak (reads as todo done) | medium-strong |

## Recommendation

**01 — Grid Single Dot**. Strongest combination of brand fit + sudoku semantic + small-size legibility + HIG compliance. See README §"Designer's recommendation" for full reasoning.

## §未決 (for Leader)

1. Is single-letter monogram (04) acceptable under Apple HIG "no text" guidance?
2. If 03 selected, should pencil angle drop from 45° to 30° for a calmer line?
3. v2 dark / tinted variants — not designed in this round; flag if Leader wants a parallel dark pass before pick.

## Out of scope (next session)

- PNG export
- `AppIcon.appiconset/Contents.json`
- macOS multi-size variants
- iOS 18 tinted / dark variants
- Path-outlining of monogram text (if 04 picked)
