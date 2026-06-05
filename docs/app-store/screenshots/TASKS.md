# App Store Screenshot Generation — Task Spec (handoff)

> ## STATUS: DEFERRED (2026-06-06)
> Headless emit was attempted THREE ways under `swift test`, all failed to render
> distinct content (every screen of a device collapsed to one image / or empty bytes):
> 1. `hostingView` + bare `NSHostingView.cacheDisplay` → opaque background only.
> 2. `windowSnapshotView` + `displayIgnoringOpacity` (#209 path) → still identical.
> 3. pointfree `Snapshotting<NSView,NSImage>.image` strategy, captured **synchronously**
>    via `.run` → returned nil/empty for several screens.
>
> **Precise remaining gap:** the `.image` strategy's `.run` callback is **asynchronous**
> here; the committed baselines render distinct only because `assertUISnapshot` (pointfree
> `verifySnapshot`) **spins the run-loop** waiting for it. A 4th attempt should add that
> run-loop wait (poll until the callback fires, with a timeout) around the `.image` capture.
> If headless still won't render, fall back to **simulator capture** (`xcrun simctl` /
> XCUITest screenshots), which renders SwiftUI properly.
>
> An **always-on distinctness guard** (`ASCScreenshotDistinctnessTests`, on the unmerged
> screenshot branches) correctly FAILS on the all-identical collapse — keep it when this
> resumes so a bad set can never ship silently. The wrong identical set previously uploaded
> to ASC has been deleted. The screenshot UPLOAD tool (`metadata screenshots`, #369) works
> and is verified — only the source-image generation is pending.


Generate **ASC-submission-spec** screenshots for **Sudoku** and **Minesweeper**, rendered
**by the snapshot-test harness**, with **distinct content per screen**.

> ⚠️ **Why this spec exists / the bug to NOT repeat.** A prior attempt (#365) emitted PNGs at
> the right size + opacity but used a bare `NSHostingView.cacheDisplay` capture that rendered
> **only the opaque background** — every screen of a device came out **pixel-identical** (all
> 17 PNGs collapsed to 3 distinct images). It shipped because nothing asserted distinctness.
> **This task's #1 requirement is distinct, real-content renders, guarded by a test.**

## 1. Capture mechanism (the critical part)

- The committed snapshot baselines under `Packages/*/Tests/*UITests/__Snapshots__/` **do**
  render distinct real content headlessly (verified: 16 distinct among Sudoku iPhone-light).
  **Use the SAME capture path those baselines use** — read `SnapshotConfig.swift`
  (`hostingView(...)` + however `assertUISnapshot` rasterises, likely the pointfreeco
  `SnapshotTesting` `.image` strategy which performs a real layout pass).
- Render at the ASC **point size × scale** (below) so the captured bitmap is the exact ASC
  pixel size. Then guarantee **opaque** (composite over the theme's opaque background so the
  PNG has **no alpha**).
- **Do NOT** reuse the broken `ASCScreenshotRender` bare-`cacheDisplay` path. If you keep that
  file, fix it to go through the proven capture; otherwise replace it.

## 2. Device matrix (exact — ASC rejects wrong size or any alpha)

| Device | ASC `displayType` | Exact pixels (portrait) | Point size @ scale |
|---|---|---|---|
| iPhone 6.9"/6.7" | `APP_IPHONE_67` | **1290 × 2796** | 430 × 932 @3x |
| iPad 13" | `APP_IPAD_PRO_3GEN_129` | **2064 × 2752** | 1032 × 1376 @2x |
| Mac | `APP_DESKTOP` | **2880 × 1800** | 1440 × 900 @2x |

## 3. Screens per app (each MUST be a distinct rendered image)

- **Sudoku** (iPhone + Mac): Home, Daily hub, Board (mid-game, seeded), Completion, Settings.
- **Minesweeper** (iPhone + Mac): Home, Daily hub, Board (mid-reveal, seeded), Completion.
- **iPad**: at least Home + Board per app (rendered fresh — closes the iPad gap).
- Reuse the **deterministic seeded view models** already in the snapshot suites (#297/#303/#308/
  #315 for MS; the Sudoku UITests fixtures) — no `Date.now` / RNG. Light mode (v1 storyline).

## 4. Hard requirements (all verifiable)

1. **Exact pixels** — `sips -g pixelWidth -g pixelHeight` == the table above.
2. **No alpha** — `sips -g hasAlpha` → `no`.
3. **Distinct** — within a device, no two screens are pixel-identical. **Add a test that
   asserts md5/data of each emitted screen differs from the others of that device** — this is
   the guard that was missing. An all-identical regression MUST fail the suite.
4. **Deterministic** — re-emitting yields identical bytes per screen.
5. **Output** — real PNG files at `docs/app-store/screenshots/<app>/<device>/<locale>/NN-screen.png`
   (locale `en` → ASC `en-US`). These feed `metadata screenshots` upload (already built).

## 5. Verification (Leader runs — the emit is gated + denied to subagents)

The emit is gated behind `ASC_EMIT_SCREENSHOTS=1`; the subagent **cannot run it** (denied at
the subagent layer) — build-verify only, and state the exact commands. The Leader runs:

```sh
ASC_EMIT_SCREENSHOTS=1 swift test --package-path Packages/SudokuKit      --filter ASCScreenshotEmitTests
ASC_EMIT_SCREENSHOTS=1 swift test --package-path Packages/MinesweeperKit --filter ASCScreenshotEmitTests
# distinctness + spec check:
for d in iphone-6.9 ipad-13 mac; do
  find docs/app-store/screenshots -path "*/$d/*" -name '*.png' -exec md5 -q {} \; | sort | uniq -d \
    && echo "FAIL: duplicate images in $d" || echo "ok: $d all-distinct"
done
```

## 6. Constraints

- Additive / test-only. Do **not** change production rendering or break existing baselines.
- `swift build --build-tests` must pass for both packages.
- Note: if any screen genuinely cannot render distinctly through the proven headless path,
  say so explicitly (do not ship an identical placeholder) — that screen becomes a documented
  gap for interactive/simulator capture, not a silent duplicate.
