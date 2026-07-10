// UITestLaunchArg — shared launch-argument constants for DEBUG-only test hooks.
//
// Lives in GameAppKit so both Sudoku and Minesweeper share a single source of
// truth for the argument string without duplicating the literal. The entire
// namespace is compiled out of Release builds via `#if DEBUG` so none of
// these symbols ship.
//
// Usage (host process):
//   xcrun simctl launch <udid> com.wei18.sudoku -uitest-near-win
//
// Usage (Swift):
//   #if DEBUG
//   if ProcessInfo.processInfo.arguments.contains(UITestLaunchArg.nearWin) { … }
//   #endif

#if DEBUG

internal import Foundation

public enum UITestLaunchArg {
    /// Signals both apps to boot into a board that is one move from winning,
    /// so the real win → completion flow can be exercised with a single tap.
    /// Absent from Release builds — the guard `#if DEBUG` above ensures the
    /// entire enum is stripped by the compiler.
    public static let nearWin = "-uitest-near-win"

    /// Signals Sudoku to boot into a near-win board presented through the
    /// PRODUCTION modal path (path == nil fullScreenCover), so the #610
    /// in-board Completion overlay can be exercised with a single tap.
    /// Distinct from `nearWin` which uses a push NavigationStack (path != nil).
    /// Absent from Release builds — the `#if DEBUG` guard ensures the entire
    /// enum is stripped by the compiler.
    public static let nearWinModal = "-uitest-near-win-modal"

    /// Forces both loaders (`BoardLoaderView` / `MinesweeperBoardLoaderView`)
    /// straight into `.failed(.unknown)` on mount, skipping the real
    /// persistence fetch entirely (#719). Sim verification of the loader's
    /// `.failed` exit affordance is otherwise blocked — there is no way to
    /// reliably fail a CloudKit fetch from a signed-in-but-offline simulator
    /// on demand. Absent from Release builds via the `#if DEBUG` guard.
    public static let loaderFail = "-uitest-loader-fail"

    /// Deep-link launch flag (#510): boot straight into a named screen so a
    /// reviewer / XCUITest reaches it in one launch instead of tapping through
    /// the home stack. Takes the NEXT argument as the screen key, e.g.
    ///   `xcrun simctl launch <udid> com.wei18.sudoku -uitest-route settings`
    /// Each app maps the key → its own `Route` (home / daily / practice /
    /// settings). Board + completion stay on the near-win hooks above. Absent
    /// from Release builds via the `#if DEBUG` guard.
    public static let route = "-uitest-route"

    /// The screen key value following `-uitest-route` in this process's launch
    /// arguments, or nil when the flag is absent / has no value. `"home"` (or
    /// absent) means stay at the root.
    public static func routeValue() -> String? {
        routeValue(in: ProcessInfo.processInfo.arguments)
    }

    /// Testable core: the screen key following `-uitest-route` in `arguments`.
    public static func routeValue(in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: route),
              index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}

#endif
