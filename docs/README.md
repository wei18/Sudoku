# docs/

## Cross-version

Stable across versions; updated whenever architecture / process / brand changes:

- `foundations.md` — engineering platform decisions (Swift 6, modules, testing, CI, Logger, Tracking, secrets)
- `methodology.md` — collaboration process, dispatch contract, backlog routing
- `privacy-policy.md` — user-facing legal (en + zh-Hant)
- `designs/` — visual design system + per-screen design docs
- `app-store/` — App Store submission metadata + assets (icons / screenshots / review notes)
- `marketing/` — positioning brief + launch / ASO / social draft collateral
- `audits/` — point-in-time audit reports (e.g. CloudKit index cost)

## Version-scoped

- `v1/` — v1.0 Sudoku app (puzzle gameplay + Game Center + CloudKit save sync)
  - `design.md`, `plan.md`, `setup.md`, `feature-tour.md`, `design-mockup.html`
- `v2/` — v2.0 monetization layer (AdMob banner + Remove Ads IAP + UMP/ATT)
  - `design.md`, `plan.md`, `uiux-bugfix-plan.md`, `v2.5-readiness.md`, `att-permission-ux-proposal.md`
- `superpowers/specs/` — platform-level design docs (SDD-003 Puzzle Platform UX Refresh, SDD-004 2048/Tiles2048, SDD-005 platform convergence)

## Conventions

- Cross-doc references use **repo-root paths**: ``docs/v1/design.md §How.X`` (not bare `design.md`)
- Source comments referencing docs use the same path style
- Backlog routing: product → `v1/design.md` or `v2/design.md` §Backlog; engineering → `foundations.md §Backlog`; implementation steps → `plan.md §Backlog`; collaboration → `methodology.md §Backlog`
