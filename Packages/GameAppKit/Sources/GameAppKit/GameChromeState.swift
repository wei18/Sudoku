// GameChromeState — shared observable carrier for the modal top-chrome timer.
//
// SDD-003 OQ-001 follow-up: the game timer moves into the modal's top chrome
// (nav-bar-style row alongside `[X]`). `GameChromeState` is the injection seam:
//
//   1. `GameRoot` creates one instance and injects it via `.environment(\.gameChrome, ...)`.
//   2. Board views (SudokuUI.BoardView, MinesweeperUI.MinesweeperBoardView) read it
//      from `@Environment` and update `elapsedLabel` on every timer tick.
//   3. `GameModalContent` reads `elapsedLabel` from the same instance and renders the
//      capsule badge in the modal top chrome.
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
    /// `nil` when the board is rendered outside a modal (e.g. push navigation
    /// on macOS, snapshot tests, previews) — board views must handle `nil`
    /// gracefully and keep their in-board timer visible in that case.
    var gameChrome: GameChromeState? {
        get { self[GameChromeStateKey.self] }
        set { self[GameChromeStateKey.self] = newValue }
    }
}
