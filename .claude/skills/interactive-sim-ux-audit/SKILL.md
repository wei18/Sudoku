---
name: interactive-sim-ux-audit
description: Project-specific setup for driving Sudoku or Minesweeper in the iOS Simulator - how to build and install a current Debug app, the DEBUG launch arguments that jump to a screen or a near-win board, which iCloud and Game Center sign-in states each check needs, and what to probe. Use together with apple-dev-skills:interactive-simulator-ux-audit when asked to test the UI, find UX problems, or verify a navigation, modal or completion flow in the running app. Not for scripted end-to-end tests (use `mise run test:ui`) and not for App Store captures (use appstore-screenshot-pipeline).
---

# Interactive Simulator UX Audit (project setup)

This skill holds only what is specific to this repo. The general method is in the plugin skills:

| Need | Skill |
|---|---|
| Install `idb`, the describe → tap → screenshot loop, coordinate rules | `apple-dev-skills:interactive-simulator-ux-audit` |
| Create, use and delete your own simulator; DerivedData location | `apple-dev-skills:parallel-agent-xcode-hygiene` |
| Decide whether a change needs a runtime check at all | `apple-dev-skills:simulator-runtime-verification` |

## Procedure

1. Create your own simulator and boot it, as `apple-dev-skills:parallel-agent-xcode-hygiene` describes. Keep its UDID. Never use a simulator another session booted.
2. In a worktree, seed the gitignored build files first. Run this from the main checkout:

   ```
   mise run worktree:seed <worktree-path>
   ```

   Without it the app is built with empty AdMob and App Store values and stops at launch. That stop is a setup fault, not an app bug.
3. Build, install and capture every screen in light and dark:

   ```
   mise run ui:tour --app <sudoku|minesweeper|all> --udid <UDID>
   ```

   - Always pass `--udid`. Without it the task picks whichever simulator is already booted.
   - The task builds a Debug app into `build/tour-sim/`, refuses to install an app whose Info.plist has unresolved values, and writes screenshots to `build/tour/<app>/<light|dark>/`.
   - `--no-build` reuses the installed app.
4. Mute the background music before driving, then relaunch the app:

   ```
   xcrun simctl spawn <UDID> defaults write com.wei18.sudoku      com.wei18.sudoku.audio.musicEnabled      -bool false
   xcrun simctl spawn <UDID> defaults write com.wei18.minesweeper com.wei18.minesweeper.audio.musicEnabled -bool false
   ```

5. Confirm the installed version in the app (Settings → Version) matches the commit you mean to test.
6. Drive the app with the plugin skill's loop.
7. Delete your simulator and `build/tour-sim/` when done.

## Launch arguments (DEBUG builds only)

Pass them after the bundle id: `xcrun simctl launch <UDID> com.wei18.sudoku <argument>`.

| Argument | Effect |
|---|---|
| `-uitest-route daily` / `practice` / `settings` | Open that tab or screen directly |
| `-uitest-near-win` | Open a board one move from a win (both apps) |
| `-uitest-near-win-modal` | Sudoku only: the same board, presented through the modal path |
| `-uitest-seed-completed-daily` | Report today's daily puzzles as already completed |
| `-uitest-gc-signed-out` | Make Game Center sign-in fail, to show the signed-out alert |
| `-uitest-loader-fail` | Make the board loader fail |
| `-uitest-iap-script` | Make purchases return cancelled, failed, then pending; Restore finds nothing |
| `-uitest-open-ad-gate` | Force the banner slot open so a test ad renders |

The full list, with the exact behavior of each argument, is `Packages/GameAppKit/Sources/GameAppKit/UITestLaunchArg.swift`.

A win cannot be reached by blind taps. Use `-uitest-near-win`. A Minesweeper loss can be reached by tapping covered cells until one is a mine.

## Sign-in states

iCloud and Game Center are separate sign-ins in Simulator → Settings.

| State | What it is for | Expected behavior |
|---|---|---|
| Network on, iCloud signed out | Daily hub, resume, leaderboard screens | Core gameplay still works. No spinner may stay forever: CloudKit calls can hang in this state |
| Network off | The same screens | CloudKit calls fail at once; screens show their offline state |
| iCloud signed in (sandbox Apple ID) | Resume pill, saved games, records | Only this state shows a resume pill. Signed out, `latestInProgress()` returns nil by design |
| Game Center signed in | Score submit, achievements | The Game Center dashboard is a system overlay; `idb` cannot read it |

Test both "network on, iCloud signed out" and "network off". They fail differently, and a pass in one does not cover the other.

Signing an Apple ID into the simulator is the user's step. Ask the user; do not enter credentials.

## What to probe

- Navigation: the board appears after choosing a difficulty; Close leads to the Leave Game confirmation; pause; repeated back.
- End of game: win and loss completion, and score submit when Game Center is unavailable.
- Safe area: completion and overlay content is not clipped by the Dynamic Island and does not overlap the board controls.
- Purchases: cancel the Remove Ads purchase; Restore with nothing to restore (`-uitest-iap-script`).
- Negative flows: the numbered rows N1… in `docs/navigation-flows.md` list each failure path and its expected result.
- Dynamic Type: `xcrun simctl ui <UDID> content_size accessibility-extra-extra-extra-large`, relaunch, check, then reset with `content_size large`.
- Both apps: check every shared screen in Sudoku and in Minesweeper.

## Reporting a finding

1. Attach the screenshot path and the steps to reproduce.
2. State the sign-in state and the installed version.
3. Say whether the cause is the environment (no iCloud, stale build, unseeded worktree) or the app.
4. Reproduce on a fresh build of `origin/main` before calling it an app bug.
