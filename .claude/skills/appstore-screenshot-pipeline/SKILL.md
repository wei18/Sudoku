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
| iPad | 1032×1376 baselines exist (#506) | 13": 2048×2732 / 2064×2752 | ✗ size + alpha (use build-ascspec) |

The symlinked tree is for eyeballing the storyline from one source — **it is not
an upload path.**

## The marketing-frame pass NOW EXISTS — and is the real upload path (#311 / #506)

The "separate pass" below is no longer hypothetical. `mise run store:screenshots
build-ascspec` (→ `scripts/build-ascspec-screenshots.py`) composites the baselines
into ASC-exact **1290×2796 (iPhone 6.9") + 2064×2752 (iPad 13") RGB, no-alpha** PNGs
with on-brand frames + the strategy-doc caption copy, written to their OWN tree:

```
docs/app-store/screenshots-ascspec/<app>/<device>/<locale>/NN-screen.png
```

This path is separate from the preview symlinks (so it never clobbers them) AND
matches the uploader contract `<app>/<device>/<locale>` exactly. Key facts:
- **Per-locale fonts:** CJK locales (zh-Hant/zh-Hans/ja/ko) load Hiragino/PingFang —
  SFNS has zero CJK glyphs and renders Chinese as tofu (the #504 regression).
- **iPad baselines now exist** (#506 added iPad-13 snapshot configs + the generator's
  `ipad-13` arm) — the "unwired" row above is historical.
- **Upload (Leader-orderable, gated):**
  `ASCRegister metadata screenshots --app <app> --app-id <id> --platform ios
  --locale <repo-code> --screenshots-dir docs/app-store/screenshots-ascspec --i-am-sure`
  (run per locale; device auto-detected from the dir; iPhone+iPad both picked up,
  already-present slots skipped). Other locales fall back to en in ASC.
- **EYEBALL the output per locale** (esp. CJK) before upload — the dimension/mode
  check passed even while every zh-Hant caption was tofu (#504). See [[interactive-sim-ux-audit]]
  discipline: verify content, not just dims.

## Known footguns

- **Do not upload the symlinked PNGs to App Store Connect.** They fail the
  dimension + alpha pre-check. The `sync` output and `list` both reprint this.
- **The gap to submission-ready is now CLOSED** by `build-ascspec` (see the section
  above). Do not upload the *preview symlinks*; do upload the `screenshots-ascspec/`
  tree. #311 delivered the marketing-frame pass + CJK-font fix + uploader-contract
  path; #506 added the iPad-13 arm. Both apps' iPhone 6.9" + iPad 13" (en + zh-Hant)
  are uploaded to ASC as of 2026-06-15.
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
