# App Store screenshots — snapshot-sourced staging tree

This directory is **generated**, not hand-authored. Run:

```sh
mise run store:screenshots sync          # all apps
mise run store:screenshots sync --app sudoku
mise run store:screenshots list          # print the mapping + gaps
mise run store:screenshots clean         # remove the symlinks
```

`sync` materializes relative **symlinks** under
`<app>/<device>/<locale>/NN-screen.png` pointing at the committed
snapshot-test baselines in `Packages/.../__Snapshots__/`. The baseline is the
single source of truth: re-recording the snapshots (`swift test --record`)
auto-refreshes these previews. No PNGs are duplicated — git stores the links as
link entries, not copies. The task body and mapping live in
`mise-tasks/store/screenshots`.

## ⚠️ PREVIEW-ONLY — these are NOT App Store submission assets

The baselines are raw `NSHostingView` renders at the snapshot layout sizes
**with an alpha channel**:

| Source | Baseline pixels | ASC requires | Verdict |
|---|---|---|---|
| iPhone snapshot | 786 × 1704, RGBA | 1290 × 2796 (exact, no tolerance), **no alpha** | ✗ size + alpha |
| Mac snapshot | 1800 × 1200, RGBA | ≥ 1280 × 800, **no alpha** | ✗ alpha (size ok) |
| iPad | *(no baselines exist)* | 2048 × 2732 | ✗ unwired |

App Store Connect rejects the upload at the dimension/alpha check before review.
So this tree lets reviewers and the Leader eyeball the 5-shot store storyline
from a single source — it does **not** replace the marketing-frame / upscale
pass that produces ASC-exact RGB assets. See
[`../screenshot-strategy.md`](../screenshot-strategy.md) §Snapshot-sourced
pipeline for the gap and the path to submission-ready assets.
