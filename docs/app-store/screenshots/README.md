# App Store screenshots — preview tree

This tree is a preview of the store storyline. It is never uploaded.

- The PNG files committed here today are placeholders: regular files, many with identical bytes. They do not show the real screens.
- The screenshots that go to App Store Connect are in [`../screenshots-ascspec/`](../screenshots-ascspec/), built by `mise run store:screenshots build-ascspec`.
- The full procedure (capture, build, check, upload) is in `.claude/skills/appstore-screenshot-pipeline/SKILL.md`.

## What `sync` produces

```sh
mise run store:screenshots list                 # print the mapping and any missing baseline
mise run store:screenshots sync [--app sudoku]  # create or refresh the links
mise run store:screenshots clean                # remove the links
```

`sync` creates relative symlinks at `<app>/<device>/<locale>/NN-screen.png` that point at the committed snapshot-test baselines under `Packages/*/Tests/*/__Snapshots__/`. Re-recording a snapshot therefore updates the preview with no copy step. The mapping is the `MAP` array in `mise-tasks/store/screenshots`.

## Why this tree cannot be uploaded

Snapshot baselines are raw renders with an alpha channel, at the snapshot layout size. App Store Connect requires exact pixel sizes and no alpha, and rejects these files before review. `build-ascspec` composites the same sources into framed images at the required size (iPhone 6.9" 1290×2796, iPad 13" 2064×2752, Mac 2880×1800), RGB, no alpha.

`TASKS.md` in this folder is a historical task spec for an approach that was not pursued.
