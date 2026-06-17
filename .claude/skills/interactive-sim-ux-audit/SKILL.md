---
name: interactive-sim-ux-audit
description: Drive the running game apps in the iOS Simulator with idb (tap / describe / screenshot) to find UX + layout bugs that snapshot tests cannot — navigation, modals, back-stack, completion, safe-area/Dynamic-Island clipping, offline/signed-out flows. Use when asked to "test the UI", "find UX problems", or verify an interactive flow.
---

# Interactive Simulator UX Audit (idb-driven)

Snapshot tests render views in a fixed-size `NSHostingView` — they do **not** model
navigation, taps, the device safe area, or the Dynamic Island. A whole class of bugs
only shows when you actually drive the app: blank-board-after-tap (#491), unplayable
when iCloud signed out (#512), completion icon clipped by the Dynamic Island (#518).
This skill is how to run that audit.

## Prereq: idb (one-time install — NOT Homebrew)

The no-Homebrew/CocoaPods policy does **not** forbid idb. Install via **direct GitHub
release download** (user-authorized path). Verified on macOS 26 / Xcode 26 / arm64:

1. `idb_companion`: download `idb-companion.universal.tar.gz` (latest = v1.1.8; 2022 but
   works) from https://github.com/facebook/idb/releases → extract to
   `~/idb-tools/companion/idb-companion.universal/` (binary in `bin/`, `Frameworks/`
   sibling). The objc duplicate-class warning for `FBProcess` is non-fatal.
2. `idb` CLI: `pip3 install --user fb-idb` → `~/Library/Python/3.9/bin/idb`.
3. Put both on PATH at `~/.local/bin` (already on the MCP-inherited PATH): symlink `idb`;
   for the companion use a **wrapper script** that `exec`s the real binary's absolute
   path (a bare symlink breaks `@executable_path/../Frameworks` rpath).
4. Verify: `idb list-targets`, then `idb ui describe-all --udid <booted-sim>` returns the
   a11y tree (frames + AXLabel) in device-**point** space (iPhone 17 Pro = 402×874 pt).

See [[idb-sim-ui-driving-works]] (memory) for the exact commands.

## Build + install the app under test — use a CURRENT build, from the MAIN checkout

- **Check the installed version first.** A stale build silently invalidates findings —
  e.g. the sim once held a `1.0.0` build; Settings → Version exposes it. Confirm it's the
  version you mean to test before reporting any bug.
- Build for the sim: `xcodebuild -workspace Game.xcworkspace -scheme <Sudoku|Minesweeper>
  -sdk iphonesimulator -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
  -derivedDataPath build/sim build`, then `xcrun simctl install <udid> <App.app>`.
- **Build from the main checkout, NOT an agent worktree.** Worktrees lack the gitignored
  `Tuist/AdMob.xcconfig` + `secrets/.env`, so the Debug build's `AppComposition.live()`
  hits an assertion at launch (`EXC_BREAKPOINT`) → app drops to springboard. That crash is
  an env artifact, not a code bug. (Tuist needs `tuist install && tuist generate --no-open`
  first; the workspace is gitignored.)

## The drive loop

```
idb ui describe-all --udid <udid>   # get element frames + AXLabel (pipe to python/jq)
idb ui tap --udid <udid> <x> <y>    # tap at device-point coords (center of a frame)
xcrun simctl io <udid> screenshot <path.png>   # capture; then Read the PNG and eyeball
```

- **Get coords from `describe-all`**, not from screenshot pixels (screenshot is 3× the
  point space). Tap the center of an element's `frame`.
- **EYEBALL every screenshot** (Read the PNG). The a11y tree tells you *what* nodes exist;
  only the image shows clipping, overlap, empty space, tofu glyphs, z-order.
- After each tap, `describe-all` again to confirm where you landed (a tap can miss / hit
  springboard / over-navigate on double-back).

## Gotchas (each cost a real failure here)

- **zsh does NOT word-split unquoted `$var`.** `idb ui tap --udid $S $xy` with `xy="201 488"`
  fails (`invalid int value: '201 488'`). Use `${=xy}` (zsh split) or literal ints. Bare
  literals work; variables need `${=...}`.
- **`idb ui describe-all` / `ui_tap` need `idb` on PATH** — without it the ios-simulator-MCP
  errors `spawn idb ENOENT`. simctl can screenshot but cannot tap.
- **One booted sim = serialize.** Don't run concurrent sim-driving subagents against the
  same sim — they collide. Leader drives; analysis can fan out afterward.
- **Layout stress:** `xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large`
  then relaunch to test Dynamic Type; reset with `content_size large`. `appearance dark|light`
  for color scheme. System alerts (e.g. StoreKit "Sign in to Apple Account") persist across
  app relaunch — dismiss them before reading the app.
- **Reaching win/completion:** blind taps can't solve Sudoku or clear Minesweeper. Use the
  DEBUG near-win launch hook (`-uitest-near-win`) to land one move from a win. A loss is
  reachable by tapping cells until a mine.

## What to probe (this finds what snapshots miss)

- **Negative / offline:** iCloud signed out, no Game Center, airplane mode mid-game, Retry,
  Restore-with-nothing, IAP cancel. (Core gameplay must never gate on iCloud — #512.)
- **Online + iCloud-signed-out ≠ offline — test BOTH.** For any CloudKit-dependent screen
  (Daily Hub, ResumePill, leaderboard) these diverge: **offline**, CK calls fail-fast (throw
  immediately); **online-but-signed-out**, CK calls can **HANG** (network round-trip stalls
  with no authenticated container). A prior offline "pass" can mask an online hang — #536's
  Daily Hub infinite spinner only reproduced online+signed-out (the AdMob banner's network
  load triggered the re-render that exposed it). Drive the sim with network ON + iCloud OUT
  and watch for a spinner that never resolves.
- **Resume / save / Game Center cases need an iCloud-signed-in sim.** Signed out,
  `latestInProgress()` returns nil by graceful-degrade design (#515) so no ResumePill ever
  shows — #4(pill)/#12/#19/#20/#38 + GC completion are un-testable until the user signs a
  **sandbox** Apple ID into Simulator → Settings → Apple Account (iCloud and Game Center are
  SEPARATE sign-ins — GC alone does not enable CloudKit). GKGameCenterViewController is a
  system overlay idb can't introspect; absence of the #513 sign-in alert is the signal GC is
  recognized.
- **Navigation / modals:** does the board actually appear after picking difficulty (#491);
  Close → Leave-Game confirmation; pause; back-stack pressure.
- **Safe area / Dynamic Island:** completion/overlay content clipped or overlapping board
  chrome on a notch/island device (#518) — snapshots can't see this.
- **End-game:** win + loss completion flow, leaderboard submit when GC unavailable.

File each finding with the screenshot evidence + repro; note when it's environmental
(no iCloud / stale build) vs a genuine current bug, and re-validate on a fresh main build
before calling it real.
