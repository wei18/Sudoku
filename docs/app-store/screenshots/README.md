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

## Uploading to ASC — `ASCRegister metadata screenshots`

`ASCRegister metadata screenshots` uploads the PNGs in this tree to App Store
Connect via Apple's multi-part reservation flow (reserve → PUT → commit), per
app + platform, into the correct `appScreenshotSet`:

```sh
# DRY-RUN (default): prints what WOULD upload + what is already present. No mutation.
ASCRegister metadata screenshots --key <p8> --key-id <id> --issuer <id> \
  --app sudoku --platform all --locale en

# EXECUTE: actually uploads (gated behind --i-am-sure, mirrors `metadata apply`).
ASCRegister metadata screenshots ... --i-am-sure
```

- **Device → display type**: `iphone-6.9 → APP_IPHONE_67`,
  `ipad-13 → APP_IPAD_PRO_3GEN_129` (Apple reuses the 12.9" enum for 13"),
  `mac → APP_DESKTOP`.
- **Idempotency**: a PNG whose `fileName` already lives in the matching set is
  **skipped** (never duplicated). It does not replace existing screenshots.
- **Checksum**: the commit PATCH sends the MD5 of the file bytes
  (`sourceFileChecksum`); ASC verifies it against the uploaded bytes.
- ⚠️ Because these baselines are PREVIEW-ONLY (see the table above), ASC will
  reject them server-side at the dimension/alpha check even with `--i-am-sure`.
  The command implements the upload *flow* correctly; submission-ready assets
  come from the marketing-frame pass (#236).
