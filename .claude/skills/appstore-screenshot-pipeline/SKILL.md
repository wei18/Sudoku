---
name: appstore-screenshot-pipeline
description: Produce App Store screenshots for Sudoku and Minesweeper - capture the live board (`mise run store:capture`), build the App Store Connect frames (`mise run store:screenshots build-ascspec`), preview the storyline (`store:screenshots list / sync / clean`) and upload (`ASCRegister metadata screenshots`). Use when a snapshot baseline or capture that feeds a store frame changes, when the `scan:store_frame_drift` or `scan:store_baseline_orphans` gate fails, when adding a store slot or locale, or before uploading screenshots. Not for the listing text (see asc-ops-handoff) or for recording snapshot baselines (see apple-dev-skills:swift-testing-baseline).
---

# App Store Screenshot Pipeline

Two trees exist. Only one is uploaded.

| Tree | Made by | Content | Upload it? |
|---|---|---|---|
| `docs/app-store/screenshots-ascspec/<app>/<device>/<locale>/NN-screen.png` | `mise run store:screenshots build-ascspec` | Framed marketing images at the exact App Store Connect (ASC) size, RGB, no alpha | Yes |
| `docs/app-store/screenshots/<app>/<device>/<locale>/NN-screen.png` | `mise run store:screenshots sync` | Preview links to raw snapshot baselines | Never: wrong size and has alpha, ASC rejects it |

Devices in the upload tree: `iphone-6.9` (1290×2796), `ipad-13` (2064×2752), `mac` (2880×1800). Locales: the 7 listing locales.

## Sources of a frame

Each slot (`01-home`, `02-daily`, `03-board`, …) has one source, set in the `SLOTS` table of `scripts/build-ascspec-screenshots.py`:

- `Slot(...)`: a committed snapshot-test baseline under `Packages/*/Tests/*/__Snapshots__/`. One baseline feeds all 7 locales.
- `CaptureSlot(...)`: a live-simulator capture under `docs/app-store/captures/<app>/<device>/<locale>/`. One capture feeds one locale. Used for `03-board` on `iphone-6.9` in both apps, because the snapshot renderer cannot draw Liquid Glass.

`03-board` on `ipad-13` and `mac` still uses a snapshot baseline and shows no glass (#1110 for iPad, #1054 for Mac).

## Procedure: a source image changed

1. If a capture-sourced board changed, re-capture it. This builds a Debug app and boots simulators that the task creates and deletes itself:

   ```
   mise run store:capture --app <sudoku|minesweeper|all> --device iphone-6.9
   ```

   - `--verify` re-captures and compares against the committed captures without changing them.
   - `--staging-only` captures into `build/store-capture/staging/` without publishing.
   - The task publishes all cells of the run or none.
2. Rebuild the frames (needs macOS: the script loads system fonts):

   ```
   mise run store:screenshots build-ascspec
   mise run store:screenshots build-ascspec --verify-only   # check size and mode only
   ```

3. Open one frame per locale and look at it. The size check passes even when the text is wrong: CJK and Thai captions have rendered as empty boxes before.
4. Commit the changed captures and every regenerated frame in the same PR.
5. Run the gates locally:

   ```
   mise run scan:store_frame_drift --base origin/main
   mise run scan:store_baseline_orphans
   ```

## Procedure: upload (user-owned gate)

Upload only when the user asks. Without `--i-am-sure` the command is a dry run that prints what it would upload.

```
source secrets/.env
swift run --package-path Packages/ASCRegisterKit ASCRegister metadata screenshots \
  --key "$ASC_API_KEY_PATH" --key-id "$ASC_API_KEY_ID" --issuer "$ASC_API_ISSUER_ID" \
  --app <sudoku|minesweeper> --platform <ios|macos|all> --locale <repo-locale> \
  --screenshots-dir docs/app-store/screenshots-ascspec [--i-am-sure]
```

- Run once per locale.
- A file whose name is already in the ASC screenshot set is skipped, not replaced.
- `mise run preflight:submission <app> <platform>` reports which locales still lack screenshots.

## Preview tree

```
mise run store:screenshots list                               # mapping, with [ok] or [MISSING-BASELINE] per slot
mise run store:screenshots sync  [--app sudoku|minesweeper|all]   # create or refresh the relative symlinks
mise run store:screenshots clean [--app sudoku|minesweeper|all]   # remove the symlinks
```

- The mapping is the `MAP` array in `mise-tasks/store/screenshots`. It holds light-mode, `en` slots only.
- `sync` skips a slot whose baseline is missing and reports it. That is not an error.
- The PNG files committed in `docs/app-store/screenshots/` today are placeholders, not `sync` output: regular files, many with identical bytes. Do not use them as evidence of what a screen looks like. Run `sync` to replace them with links.

## Gates (CI, `lint.yml`)

| Gate | Fails when |
|---|---|
| `mise run scan:store_frame_drift` | A baseline or capture that feeds a frame changed, and not every frame it feeds was regenerated in the same PR |
| `mise run scan:store_baseline_orphans` | A mapped baseline is missing, or no test function records it any more |

## Adding or changing a slot

1. Edit `SLOTS` (and the caption tables) in `scripts/build-ascspec-screenshots.py`.
2. Mirror the change in `MAP` in `mise-tasks/store/screenshots`.
3. Prefer a baseline rendered inside its production container over an isolated component render when both exist.
4. Run the procedure above.

## See also

- `docs/app-store/screenshot-strategy.md`: storyline, caption copy, capture rules.
- `asc-ops-handoff`: which App Store Connect steps the user owns.
- `mise-task-operations`: index of all ops tasks.
