# Impl Notes — fix(minesweeper): completion screen safe area + chrome overlay fix #518 (2026-06-16)

Status: IN_PROGRESS
Owner: Developer (Sonnet 4.6)
Dispatched by: Leader
Started: 2026-06-16T00:00:00Z

## 設計決定 (Design decisions)

- **Safe-area strategy** — The `.ignoresSafeArea()` on `completionSurface()` in `MinesweeperBoardView.swift` line 199 was a blanket ignore. The `CompletionScreen.body` already uses `.background(theme.surface.background.resolved)` on the outer `ScrollView`, which is what should bleed to edges. The `ScrollView` content inside uses `.padding(20)` + `.frame(maxWidth: 480)` centering, so the CONTENT is already constrained. The fix: keep `.ignoresSafeArea()` on the container (to fill behind status bar / home indicator) but add `.safeAreaPadding(.top)` on the `ScrollView` inside `CompletionScreen` — NO, that changes the shared component. Instead: in `completionSurface()` in `MinesweeperBoardView`, use `.ignoresSafeArea()` for the background only while letting content sit in the safe area. Pattern: `ZStack { background.ignoresSafeArea(); content }`. Chose to keep the fix entirely in `MinesweeperBoardView.completionSurface()` — wrapping `MinesweeperCompletionView` in a `ZStack` that separates background (ignores safe area) from content (stays in safe area).

- **Chrome visibility** — `GameModalContent` in `GameRoot.swift` renders the timer chip + ✕ button in a `ZStack(alignment: .top)` with `.padding(.top, 56)`. The board view (`MinesweeperBoardView`) is `view` inside `GameModalContent`. The completion overlay is an `.overlay` on the board's body. So layering from back to front is: board → completion overlay → chrome `HStack`. The completion overlay IS above the board but BELOW the chrome (which is in `GameModalContent`'s own `ZStack`). Fix: hide the chrome when `isTerminal` is true. The cleanest spot is to gate the `HStack` in `GameModalContent` body. But `GameModalContent` is private and doesn't know about the game's terminal state. Alternative: use `chromeState` — add a `isTerminal` flag to `GameChromeState` that the board sets, then gate in `GameModalContent`. OR: the board view itself can use `.ignoresSafeArea(regions: .all)` plus a full `ZStack` approach to cover the chrome too — but that can't work because chrome is ABOVE in the view hierarchy. Chose: inject `isGameTerminal` into `GameChromeState` so `GameModalContent` can hide the `HStack` when true. `GameChromeState` already exists in `GameAppKit`; adding a `isHidingChrome` flag there is minimal and avoids cross-module layering.

- **Centering** — `CompletionScreen.body` already has `.frame(maxWidth: .infinity, maxHeight: .infinity)` on the ScrollView, so it should fill the full screen. But the ScrollView's content starts at the top (content gravity). The `VStack(spacing: 24)` inside has `.padding(20)`. The ScrollView itself expands to fill. The issue was `.ignoresSafeArea()` causing the content to start at y=0 (under the Dynamic Island). With the safe-area fix above, the ScrollView will respect the top safe area and content will start below the Dynamic Island. The natural vertical positioning of `ScrollView` content that is shorter than the screen starts at top + safe area inset — that may leave empty space at the bottom. For proper centering, wrap the `VStack` in a `frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)` within the scroll view, or use `Spacer`. Chose: wrap the content VStack in a `GeometryReader` or use `ScrollView { content.frame(minHeight: geometry.size.height) }` pattern. Actually simpler: look at what Sudoku does — its `CompletionScreen` is inside a pushed route which handles centering. For the MS overlay, we want the content centered. Will add `.contentMargins(.top, safeAreaInsets.top)` or use `GeometryReader` to center.

## 折衷 (Tradeoffs)

- **Where to hide chrome** — Option A: add `isHidingChrome: Bool` property to `GameChromeState` (in `GameAppKit/GameChromeState.swift`) + gate `HStack` in `GameModalContent`. Option B: Make completion overlay use `.zIndex(999)` — won't work, `GameModalContent`'s ZStack is a separate view. Option C: Board sets chromeState to hide via existing API. **Chose Option A** — minimal, clean, surgical. `MinesweeperBoardView` sets `chromeState?.hideChrome(true)` when terminal, `chromeState?.hideChrome(false)` when not. `GameModalContent` gates the HStack.

- **Safe area for background** — Rather than change `CompletionScreen` (shared, Sudoku uses it), the approach is: in `completionSurface()`, wrap the view so the background extends into safe areas but content stays within them. This matches SwiftUI footguns guidance: background should `.ignoresSafeArea()`, content should not.

## 未決 (Open questions)

None — the fix approach is clear from the confirmed root cause.
