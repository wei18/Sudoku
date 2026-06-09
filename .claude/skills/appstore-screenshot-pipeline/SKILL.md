---
name: appstore-screenshot-pipeline
description: Sync App Store screenshot PREVIEWS from committed snapshot-test baselines via `mise run store:screenshots` (list / sync / clean). Symlinks selected baseline PNGs into docs/app-store/screenshots/<app>/<device>/<locale>/NN-screen.png so re-recording snapshots auto-refreshes previews. PREVIEW-ONLY — baselines carry an alpha channel and wrong dimensions, so they are NOT ASC submission-spec; a separate marketing-frame/upscale pass is still required before any real upload. Invoke when wiring or refreshing store-preview screenshots, running/debugging `store:screenshots`, eyeballing the storefront storyline, or when asked "can I upload these snapshot PNGs to App Store Connect" (answer: not directly).
---

# App Store Screenshot Pipeline

## When to invoke

- Wiring or refreshing the store-preview screenshot tree.
- Running or debugging `mise run store:screenshots`.
- Eyeballing the App Store storefront storyline from a single source.
- Someone proposes uploading the snapshot PNGs straight to ASC.

## What it is

`mise-tasks/store/screenshots` (task `store:screenshots`) maps selected
snapshot-test baseline PNGs into a staging tree using **relative symlinks**:

```
docs/app-store/screenshots/<app>/<device>/<locale>/NN-screen.png
  → Packages/.../__Snapshots__/<...>.png
```

This keeps the snapshot baseline the **single source of truth**: re-recording the
snapshots (`swift test --record`) auto-updates the store preview with no copy
step. Git stores the symlinks as links, not PNG copies. Mirrors the
scriptable-ops precedent of `mise-tasks/ck/schema` and the ASCRegister CLI.

## Invocation

```
mise run store:screenshots list                              # print mapping + gaps
mise run store:screenshots sync  [--app sudoku|minesweeper|all]
mise run store:screenshots clean [--app sudoku|minesweeper|all]
```

- `list` — prints every wired slot with an `[ok]` / `[MISSING-BASELINE]` mark,
  plus the standing reminders (preview-only; no iPad baselines).
- `sync` — creates/refreshes the symlinks; skips slots whose baseline is missing.
- `clean` — removes only the symlinks (`-L` checked) and prunes empty dirs.

The mapping table lives inline in the task (one row per store slot that has a
baseline today). `--app` filters to one app.

## What is wired today

Light-mode, `en`/default-locale slots that have a baseline (per the inline MAP):

- **Sudoku** — iPhone: Home / Daily / Board / Completion / Settings; Mac: Home /
  Board / Settings.
- **Minesweeper** — iPhone: Home / Daily / Board / Completion; Mac: Home / Daily.

Run `mise run store:screenshots list` for the authoritative live mapping. Only
light-mode renders are wired (ASC v1 storyline is light-mode per
`docs/app-store/screenshot-strategy.md §Capture conventions`).

## PREVIEW-ONLY — these are NOT submission-ready

The baselines are raw `NSHostingView` renders at snapshot layout sizes **with an
alpha channel**. ASC's screenshot spec is exact-dimension, zero-tolerance, no
alpha — so ASC rejects them at the dimension/alpha check **before** review:

| Source | Baseline pixels | ASC requirement | Verdict |
|---|---|---|---|
| iPhone snapshot | 786 × 1704, RGBA | 6.9": 1290×2796 / 1320×2868, no alpha | ✗ size + alpha |
| Mac snapshot | 1800 × 1200, RGBA | ≥ 1280×800, no alpha | ✗ alpha |
| iPad | *(no baselines exist)* | 13": 2048×2732 / 2064×2752 | ✗ unwired |

The symlinked tree is for eyeballing the storyline from one source — **it is not
an upload path.**

## Known footguns

- **Do not upload the symlinked PNGs to App Store Connect.** They fail the
  dimension + alpha pre-check. The `sync` output and `list` both reprint this.
- **The gap to submission-ready is a separate pass** (tracked under #236): a
  marketing-frame / upscale step consumes these baselines and emits ASC-exact RGB
  (no-alpha) PNGs at the required dimensions, applying the overlay copy tabled in
  `screenshot-strategy.md`, plus adding **iPad snapshot fixtures**. #311 delivered
  the wiring + the honest gap doc only.
- **Missing baseline ≠ error.** `sync` skips a slot whose source PNG is absent and
  reports it; that's expected when a snapshot hasn't been recorded yet.
- **Re-record refreshes automatically.** Because the previews are symlinks, you
  never re-run anything after `swift test --record` — the preview follows.

## See also

- `docs/app-store/screenshot-strategy.md` — the full storyline (5 shots × device
  classes × 7 locales), overlay copy, capture conventions, and the
  §"Snapshot-sourced pipeline" / §gap that this task implements.
- [[asc-ops-handoff]] — uploading App Metadata (incl. screenshots) to ASC is a
  user-owned / future-ASCRegister-mode op; this task only stages previews.
- [[swift-testing-baseline]] — the snapshot baselines that are the source of truth.
- [[mise-task-operations]] — the ops-task index this task belongs to.
