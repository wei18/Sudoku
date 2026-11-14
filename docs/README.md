# docs/ index

Every file and folder under `docs/`, with its status. Start here to find which document is current for a topic.

Status values:

- **living**: kept current. Act on it.
- **as-built**: describes the code as of the stated date. Parts may be superseded; where it differs from the code or from a living document, they win.
- **generated**: produced by a task. Do not edit by hand.
- **historical**: a record of a past decision or plan. Do not act on it and do not update its prose.

## Current rules and design

| Path | What it is | Status |
|---|---|---|
| `designs/v3/design.md` | The 3.0 UI design for both apps (3-tab shell, board-first, Liquid Glass). The current design | living |
| `designs/v3/prototype.html` · `designs/v3/README.md` | Full-screen prototype of the 3.0 design, and how the design reached its final revision | living |
| `screen-contracts.md` | Per-screen contracts: elements, interactions, state variants. Anchored by `mise run scan:design_contracts` | as-built (2026-07-05, pre-3.0 sections marked in its header) |
| `navigation-flows.md` | Route enums, flow chains and negative flows (rows S, M, N). Anchored by the same gate | as-built (2026-07-05, pre-3.0 sections marked in its header) |
| `foundations.md` | Engineering platform decisions: Swift 6, modules, testing, CI, logging, analytics, secrets, third-party SDKs | living |
| `methodology.md` | Collaboration rules for agents: roles, dispatch brief, Leader rules | living |
| `privacy-policy.md` | The public privacy policy (user-facing) | living |

The 3.0 design changes the screen contracts through a change table in `scripts/design/contracts.py`. The gate fails when a row of that table points at a section that no longer exists.

## App Store

| Path | What it is | Status |
|---|---|---|
| `app-store/SUBMISSION-CHECKLIST.md` | Step-by-step v2.6 submission guide | living |
| `app-store/review/*-v2.6-review-information.md` | App Review notes and contact table for v2.6 | living |
| `app-store/review/sudoku-v2.5.md` · `app-store/review/minesweeper-v1.md` | Review notes of earlier submission attempts | historical |
| `app-store/metadata/` | Listing text per app and locale, IAP metadata, `README.md` with the schema | living |
| `app-store/metadata/COPY-REVIEW.md` | A 2026-06 review of the listing copy | historical |
| `app-store/screenshot-strategy.md` | Storyline, caption copy and capture rules for store screenshots | living (its opening sections are marked superseded) |
| `app-store/captures/` | Live-simulator captures that feed store frames, with `manifest.json` | generated (`mise run store:capture`) |
| `app-store/screenshots-ascspec/` | The screenshot frames uploaded to App Store Connect | generated (`mise run store:screenshots build-ascspec`) |
| `app-store/screenshots/` | Preview tree; the committed PNG files are placeholders | generated (`mise run store:screenshots sync`) |
| `app-store/screenshots/TASKS.md` | Task spec for an abandoned headless-capture approach | historical |
| `app-store/icons/` · `app-store/identity-check-evidence/` | Icon sources and identity-check evidence | living |
| `app-store/provisioning/templates/` | Templates for `mise run new_app:provisioning` | living |

## Marketing

| Path | What it is | Status |
|---|---|---|
| `marketing/BRIEF.md` | Positioning brief and the table of verified claims. Read before writing any marketing copy | living |
| `marketing/aso/` · `marketing/launch/` · `marketing/social/` · `marketing/appstore-copy/` | Draft collateral | living (drafts) |

## Earlier designs and plans

| Path | What it is | Status |
|---|---|---|
| `designs/README.md` | Index of `designs/` | living |
| `designs/design-system.md` · `designs/01-root.md` … `designs/08-settings.md` | v1/v2 visual design: tokens and per-screen specs. Superseded in part by `designs/v3/design.md` | historical |
| `designs/code/` | v1 snapshot matrix and a standalone preview package | historical |
| `designs/captureguard-kit.md` | RFC for a screen-capture guard (#286, parked) | historical |
| `designs/*.prototype.html` · `minesweeper/minesweeper-app-flow.prototype.html` | Pre-3.0 flow prototypes, tagged with build status | historical |
| `v1/` | v1.0 Sudoku: design, plan, setup, feature tour, mockup | historical |
| `v2/` | v2 monetization: design, plan, readiness checklist, proposals | historical |
| `superpowers/specs/` | Numbered platform design specs (SDD-003 to SDD-006) and two other design docs | historical |
| `superpowers/plans/` | Implementation plan for the skills migration | historical |
| `audits/cloudkit-index-audit-253.md` | CloudKit index cost audit (2026-06) | historical |
| `test-plans/phase3-interactive-ux.html` | Interactive UX test plan | historical |
| `methodology-history.md` | Source cases behind the collaboration rules | historical |

## Conventions

- Refer to a doc by its repo-root path: `docs/v1/design.md §How.5`, not `design.md`. Source comments use the same form.
- A status line at the top of a document uses the values above. Do not write "last updated" dates; git has them.
- A new backlog item is a GitHub issue with the label `backlog` plus one topic label, not a line in a document. `docs/foundations.md` §Backlog has the command and the label list.
