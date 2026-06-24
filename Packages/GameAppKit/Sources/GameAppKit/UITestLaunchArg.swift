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

    /// The sentinel puzzleId used when the modal hook is active. Stored here
    /// so `SudokuNearWinModalModifier` and `LiveRouteFactory` share the same
    /// literal without duplication.
    public static let nearWinModalPuzzleId = "uitest-near-win-modal"
}

#endif
