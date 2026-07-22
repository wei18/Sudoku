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

    /// #931: swaps in `UITestFlipOnBackgroundNotificationAuthorizing` for the
    /// live `NotificationAuthorizing` in `makeGameApp`. Reports `.denied`
    /// until the process is observed entering the background, then
    /// `.authorized` — deterministically pinning
    /// `ReminderSettingsSection`'s `.onChange(of: scenePhase)` re-poll hook
    /// as an E2E regression: a poll before any real background→foreground
    /// cycle always sees `.denied`. Absent from Release builds via the
    /// `#if DEBUG` guard.
    public static let fakeReminderRepoll = "-uitest-fake-reminder-repoll"

    /// #931: swaps in `UITestFlipOnBackgroundAdGateStateStore` +
    /// `UITestNoopAdProvider` for the live ad-gate store / provider in
    /// `makeGameApp`. The fake store throws until the process is observed
    /// entering the background (so `AdGate` never caches an "open" decision
    /// early), then resolves to an always-open gate — deterministically
    /// pinning `BannerSlotView`'s `.onChange(of: scenePhase)` repoll hook
    /// (`repollGate()`) as an E2E regression: the banner slot cannot appear
    /// before a real background→foreground cycle. Absent from Release builds
    /// via the `#if DEBUG` guard.
    public static let fakeAdGateRepoll = "-uitest-fake-ad-gate-repoll"

    /// #935 batch 2: signals Sudoku to fault a specific `PuzzleProviderProtocol`
    /// call so the N3/N4/N5 negative Daily/Practice hub flows
    /// (docs/navigation-flows.md §4) can be exercised deterministically —
    /// Sudoku's `PuzzleStore` is a live generator, so there is no reliable way
    /// to force `.failed`/`.exhausted` from a real fetch on demand. Takes the
    /// NEXT argument as the fault-mode key, one of `practiceFail` /
    /// `dailyExhausted` / `dailyFail` (see `SudokuAppComposition`'s
    /// `UITestFaultingPuzzleProvider` for the per-mode throw behavior).
    /// Sudoku-only: MS's daily/practice fetches are synchronous and
    /// non-throwing (N6 — structurally unreachable there). Absent from
    /// Release builds via the `#if DEBUG` guard.
    public static let puzzleFault = "-uitest-puzzle-fault"

    /// The fault-mode key value following `-uitest-puzzle-fault` in this
    /// process's launch arguments, or nil when the flag is absent / has no
    /// value.
    public static func puzzleFaultValue() -> String? {
        puzzleFaultValue(in: ProcessInfo.processInfo.arguments)
    }

    /// Testable core: the fault-mode key following `-uitest-puzzle-fault` in
    /// `arguments`.
    public static func puzzleFaultValue(in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: puzzleFault),
              index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// #935 batch 3: Sudoku + MS, signals a DEBUG-only fake to report today's
    /// daily trio as already completed, so the N12/N13 re-view completion
    /// route (`SUD-COMPLETION-REVIEW` / `MS-COMPLETION-REVIEW`,
    /// docs/navigation-flows.md) can be exercised deterministically —
    /// completed-daily state lives in CloudKit Private DB and cannot be
    /// produced by real play on a signed-out/offline CI simulator (the
    /// near-win boards use no-op persistence and write nothing). Absent from
    /// Release builds via the `#if DEBUG` guard.
    public static let seedCompletedDaily = "-uitest-seed-completed-daily"
}

#endif
