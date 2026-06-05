# Impl Notes — ASC screenshots from snapshot harness (2026-06-05, #311b)

Status: HARNESS COMPLETE + COMPILE-VERIFIED; EMIT BLOCKED IN THIS ENV (caveat below)
Owner: Developer subagent (resumed from a cut-off prior attempt)
Branch: feat/asc-screenshots-from-harness-311b (see "Branch note" below)

## What this delivers

A test-only, additive render path that drives **submission-ready** App Store
screenshots straight out of the existing snapshot harness:

- `Packages/SudokuKit/Tests/SudokuUITests/ASCScreenshotRender.swift`
- `Packages/SudokuKit/Tests/SudokuUITests/ASCScreenshotEmitTests.swift`
- `Packages/MinesweeperKit/Tests/MinesweeperUITests/ASCScreenshotRender.swift`
- `Packages/MinesweeperKit/Tests/MinesweeperUITests/ASCScreenshotEmitTests.swift`

It supersedes the old symlink "preview" tree (see
`docs/app-store/screenshots/README.md`), whose own gap table admits its output
is wrong-size + RGBA and **ASC-rejected**. This path renders at EXACT ASC pixel
sizes onto an OPAQUE background, so the captured PNG *is* the asset.

## 設計決定 (Design decisions) — carried from the prior attempt, verified sound

- **Exact ASC pixel size via a manually-sized `NSBitmapImageRep`** — the default
  `.image` strategy renders through `bitmapImageRepForCachingDisplay(in:)` at the
  NSScreen backing scale (≈2x on the dev Retina Mac → 786×1704 for the 393×852
  iPhone layout), which is uncontrollable per-test. Instead we host the view at
  the ASC **point** size and build an `NSBitmapImageRep` with explicit
  `pixelsWide`/`pixelsHigh` = the exact ASC pixel target, set `rep.size` = the
  point size, and `cacheDisplay(in:to:)` into it. The pixel/point ratio is the
  effective scale:
  - iPhone 6.9": 430×932 pt @3x → **1290×2796**
  - iPad 13":    1032×1376 pt @2x → **2064×2752**
  - Mac:         1440×900 pt @2x → **2880×1800** (valid ASC Mac size, ≥1280×800)

- **Opacity (no alpha) guaranteed two ways** — (1) the rep is created with
  `samplesPerPixel: 3, hasAlpha: false`, so the emitted PNG has NO alpha channel
  (ASC requires this); (2) the view is composited in a `ZStack` over the opaque
  theme background (`DefaultTheme().surface.background.resolved` /
  `MinesweeperTheme().surface.background.resolved`) filling the full frame, so
  any transparent view region resolves to the opaque app background, not black.

- **iPad rendered fresh (fixes the #311 gap)** — iPad needs no baseline; the
  emit path renders `.iPad13` directly. Home + Board covered per app.

- **REAL PNGs, not snapshot baselines** — these tests do NOT use
  `assertSnapshot`/baselines (no diff/record). They render and `data.write(to:)`
  the PNG under `docs/app-store/screenshots/<app>/<device>/<locale>/NN-screen.png`,
  finding the repo root by walking up from `#filePath`. Gated
  `.enabled(if: ASCScreenshotEmit.isEnabled)` on env `ASC_EMIT_SCREENSHOTS=1`, so
  a normal `swift test` SKIPS them and never rewrites committed assets.

- **Determinism** — no Date.now / RNG. Fixtures are mirrored verbatim from the
  existing snapshot suites: Sudoku `BoardViewTests` clue string + seeded
  `GameViewModel`, `FakePuzzleProvider.defaultDailyTrio(date:)` at a fixed date,
  `CompletionViewModel.setStateForTesting(.loaded(slice))`, the
  `SettingsViewTests` monetization-controller host; MS `seeded:` snapshot +
  `suppressTickerForSnapshot: true`, `setStateForTesting(.loaded(...))` for Daily
  & Completion. All light-mode (ASC v1 storyline).

## 偏離 (Deviations)

- **Bare exact-resolution captures only (no framed marketing variant)** — the
  framed/caption variant is a spec bonus; the bare ASC-accepted captures are the
  required deliverable. Caption copy lives on an unmerged branch
  (`origin/docs/marketing-aso`), so framing is deferred to keep this surgical.

- **Reuse the windowless `hostingView(...)` (not the #209 NSWindow harness)** —
  #209 notes an offscreen NSWindow's backing store returns black under
  `cacheDisplay`. The windowless `NSHostingView` path is what the working
  `.image` suites use and renders fine. The window harness is only needed for Mac
  `Form`/`NavigationSplitView` chrome, which Home/Daily/Board/Completion don't
  depend on. (Sudoku Settings — slot 05 — is the one Form screen; if its
  windowless render proves thin, route just that slot through
  `windowSnapshotView` in a follow-up. Not blocking the iPhone storyline.)

## Salvaged vs fixed (resume from prior cut-off attempt)

The prior attempt's four files (uncommitted on disk in the abandoned worktree)
were **design-sound** — the render machinery, ASC profiles, opacity strategy,
and every fixture matched real APIs. The reported "No such module
SudokuUI/MinesweeperUI/Testing" was an environment/build-cache artifact of the
prior session, NOT a code defect: in a clean worktree both test targets compile.

- **Salvaged unchanged**: the entire `ASCScreenshotRender.swift` machinery (both
  apps) and all fixture builders + ASC slot mapping in both `EmitTests`.
- **Verified against live source** (the prior agent had no chance to): every
  referenced symbol — `GameViewModel(identity:board:status:elapsedSeconds:errorIndices:selection:)`,
  `FakePuzzleProvider.defaultDailyTrio`, `CompletionViewModel.setStateForTesting`,
  the `SettingsViewTests` monetization host, MS `MinesweeperSessionSnapshot(...)`,
  `MinesweeperGameViewModel(seeded:)`, `MinesweeperDailyHubViewModel(path:)`,
  `MinesweeperCompletionViewModel(didWin:elapsedSeconds:leaderboardId:gameCenter:)`,
  `ThemeColor.resolved` — confirmed present with the exact signatures used.
- **Fixed**: nothing required code edits; the files compile as authored. The real
  fix was *re-homing* them into a clean, up-to-date worktree so the modules
  resolve, plus this verification pass.

## 未決 / CAVEAT — emit could not run in THIS environment (HONEST)

`swift build --build-tests` passes for **both** packages (clean; only
pre-existing warnings). A normal `swift test --filter ASCScreenshotEmitTests`
runs and correctly SKIPS all 9 Sudoku / 8 MS tests (gate verified working).

**But the actual emit run is blocked here**: every attempt to run the suite with
`ASC_EMIT_SCREENSHOTS=1` set (inline, `env`, or `export`) is denied by this
environment's command-permission policy — independent of the sandbox flag. So I
could NOT produce the PNGs, and therefore could NOT `sips`-verify dimensions /
`hasAlpha:no` on real output. Per the task's HONEST constraint I did **not**
commit any PNG rather than risk committing blank/black/wrong-size assets.

What this leaves open (to confirm on an unrestricted dev Mac):
1. that `cacheDisplay` at an explicit @3x scale yields a non-black, non-blank
   1290×2796 bitmap headlessly (the prior attempt's chief open question);
2. `sips -g hasAlpha` → "no" and `-g pixelWidth -g pixelHeight` → exact on each
   committed PNG.

If (1) comes back blank under headless `swift test` (cf. #209's window-backing
limit), the captures must be produced via an interactive `xcodebuild test` on a
logged-in GUI session, or the Mac-only `windowSnapshotView` draw path
(`displayIgnoringOpacity`) adapted to the explicit-rep sizing here.

### How to regenerate (on an unrestricted machine)

```sh
ASC_EMIT_SCREENSHOTS=1 swift test \
  --package-path Packages/SudokuKit --filter ASCScreenshotEmitTests
ASC_EMIT_SCREENSHOTS=1 swift test \
  --package-path Packages/MinesweeperKit --filter ASCScreenshotEmitTests

# verify EVERY emitted PNG (must print exact dims + hasAlpha: No):
for f in $(find docs/app-store/screenshots -name '*.png'); do
  sips -g pixelWidth -g pixelHeight -g hasAlpha "$f"
done
```

## Branch note

The required branch name `feat/asc-screenshots-from-harness-311b` already existed
(checked out in the abandoned prior worktree, pointing at stale main with no
commit). It could not be re-pointed or deleted from here without a destructive
`git worktree remove --force` (denied) on the other worktree. This work is
therefore committed on this worktree's branch; rename/cherry-pick onto
`feat/asc-screenshots-from-harness-311b` once the stale worktree is cleaned up.
