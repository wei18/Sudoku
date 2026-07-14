---
description: Consult the design-app reference library (Mobbin design-db, UI/UX pre-flight checklist, five-stage AI-UI workflow) when designing or auditing UI/UX — new screens or flows, layout and pattern selection, design-system changes, spacing/motion/a11y decisions. Provides real-product evidence (500+ annotated iOS screens) plus the pre-flight rules distilled from this repo's own audit history.
---

# design-db-uiux — UI/UX design with the design-app library

The design-app workspace lives at `/Users/zw/GitHub/Wei18/design-app`
(read access is wired via `permissions.additionalDirectories` in
`.claude/settings.json`). If the path is missing on this machine, say so and
fall back to HIG + `docs/designs/design-system.md` only — do not guess library
content.

## When to reach for it

| Task | Use |
|---|---|
| Designing a NEW screen/flow (stats, calendar, onboarding, paywall…) | design-db: find same-type flows as evidence before inventing |
| Choosing a UI pattern (form mode, filter, progress, permission prompt) | `elements/*.md` cross-app selection advice |
| Any UI implementation or audit | pre-flight checklist (below) BEFORE writing SwiftUI |
| Deciding process staging for a big design task | five-stage workflow note |

## Read order

1. **`design-db/USAGE-FOR-AI.md`** — library entry point AND the
   **pre-flight checklist** (reduce-motion gating, color-token semantics,
   44pt hit targets, a11y-on-semantic-change, doc/code sync). The checklist
   items map to this repo's mechanisms: `MotionGate`, the two-tier spacing
   contract (`ScaledSpacing` / `theme.spacing.*`, design-system.md §Spacing),
   `.frame(minWidth: 44, minHeight: 44)` minimums, and
   `docs/screen-contracts.md` anchors.
2. **`design-db/index.json`** — query by flowType / screenType / element tag;
   follow paths into `apps/<app>/flows/<flow>/` (screens + notes.md 逐屏分析
   with design tokens and color ratios).
3. **`design-db/elements/*.md`** — cross-app pattern comparison with
   "which situation picks which shape" advice.
4. **`notes/ai-ui-five-stage-workflow.md`** — process staging (concept →
   design decision → design language → build → review → pre-ship) and how
   design-db feeds stages 0–2.

## Caveats (from the 2026-07 audit cycle, `notes/case-sudoku-spec-audit-cycle.md`)

- **Descriptive, not normative**: the library shows what top apps do, not what
  is correct here. Bring this repo's own judgment anchors
  (design-system.md, screen-contracts.md) to every citation.
- **iPhone-only coverage**: no macOS/iPad reference material — for
  NavigationSplitView / Mac layout questions use HIG + this repo's own
  precedents (#763 overlay adjudication), not the library.
- **a11y is checklist territory**: screenshots cannot show reduce-motion or
  VoiceOver semantics; those rules live in the pre-flight checklist, not in
  the screen library.

## Write-back duty (closing the loop)

After a design/audit cycle driven by this skill, append what the library was
missing and which patterns won/lost to a case note in
`design-app/notes/case-*.md` and commit **in that repo** (it is a separate
git repo). Gaps drive the next capture round; this is how the library gets
better instead of stale.
