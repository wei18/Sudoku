// GameChromeState — shared observable carrier for the (retired) modal top-chrome timer.
//
// SDD-003 OQ-001 originally moved the game timer into the modal's top chrome
// (nav-bar-style row alongside `[X]`), with `GameChromeState` as the injection seam:
//
//   1. `GameRoot` creates one instance and injects it via `.environment(\.gameChrome, ...)`.
//   2. Board views (SudokuUI.BoardView, MinesweeperUI.MinesweeperBoardView) read it
//      from `@Environment` and update `elapsedLabel` on every timer tick.
//   3. `GameModalContent` reads `elapsedLabel` from the same instance and renders the
//      capsule badge in the modal top chrome.
//
// #674: the capsule's fixed `.padding(.top, 56)` overlapped the board's own header /
// first grid row on some devices. Minesweeper had already stopped feeding it (#663,
// moved its clock into the status bar); Sudoku followed in #674, moving its timer
// permanently into `BoardView`'s own header row. As of #674 NEITHER board calls
// `updateElapsed` / `setHidingChrome` any more, and `GameModalContent` no longer
// renders the capsule — this class + the `\.gameChrome` environment key are kept as
// an unused injection seam rather than deleted outright (surgical scope for #674).
// Follow-up candidate: if no future board revives this pattern, retire the whole
// seam (this file, the `gameChrome` EnvironmentKey, and `GameModalContent`'s
// `chromeState` property) in a dedicated cleanup PR.
//
// The carrier is in `GameAppKit` (not `GameShellKit`) because it is consumed by the
// board views that live in `SudokuUI` / `MinesweeperUI`, both of which already
// depend on `GameAppKit`. `GameShellKit` stays zero-dependency.
//
// Design choice: `elapsedLabel` is a formatted `String` (not raw `Int`) because the
// label computation differs per game — Sudoku formats `mm:ss`; Minesweeper uses only
// seconds. The board VM owns the format; the chrome renders opaquely.

public import SwiftUI

// MARK: - GameChromeState

/// Lightweight shared carrier pushed down via SwiftUI Environment so the board
/// view can update the modal top chrome's elapsed display without a direct reference.
@MainActor
@Observable
public final class GameChromeState {
    /// The formatted elapsed-time string to display in the modal chrome.
    /// `nil` means the board hasn't started ticking yet (e.g. still loading).
    public private(set) var elapsedLabel: String?

    /// When `true`, `GameModalContent` suppresses the timer chip + ✕ chrome row.
    /// Board views set this when the game reaches a terminal state so the
    /// completion overlay can cover the full screen without chrome bleeding through.
    public private(set) var isHidingChrome: Bool = false

    public init() {}

    /// Called by the board view's timer loop to refresh the chrome label.
    public func updateElapsed(_ label: String) {
        elapsedLabel = label
    }

    /// Called by the board view when the game enters / exits a terminal state so
    /// `GameModalContent` can suppress the chrome row while the completion overlay
    /// is visible. Passing `true` hides the timer chip + ✕; `false` restores them.
    public func setHidingChrome(_ hiding: Bool) {
        isHidingChrome = hiding
    }

    /// Reset when the modal is dismissed so a stale label never bleeds into
    /// the next modal presentation.
    public func reset() {
        elapsedLabel = nil
        isHidingChrome = false
    }
}

// MARK: - EnvironmentKey

private struct GameChromeStateKey: EnvironmentKey {
    static let defaultValue: GameChromeState? = nil
}

public extension EnvironmentValues {
    /// The active `GameChromeState` injected by `GameRoot` for its modal.
    /// #674: kept as an unused injection seam — neither board reads this key
    /// any more (both render their own timer unconditionally in their
    /// header/status row regardless of modal vs. push presentation).
    var gameChrome: GameChromeState? {
        get { self[GameChromeStateKey.self] }
        set { self[GameChromeStateKey.self] = newValue }
    }
}
