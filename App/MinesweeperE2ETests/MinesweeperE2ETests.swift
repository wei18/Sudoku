import XCTest

// #510 Phase 3 — Minesweeper host-driven E2E.
//
// Named `MinesweeperE2ETests` (mirrors `SudokuE2ETests`) to avoid colliding
// with the SPM snapshot/unit target `MinesweeperUITests` in Packages; this one
// drives the real app on the simulator.
//
// PR1 scope: launch smoke only. The win → completion happy path (PR2) needs a
// DEBUG "winning-cell" accessibility beacon first: Minesweeper's near-win board
// keeps every mine hidden alongside the one remaining safe cell, so — unlike
// Sudoku, where a wrong digit is harmless and can be brute-forced — blindly
// tapping a hidden cell here risks hitting a mine (a loss, not a win). The test
// must tap the exact safe cell, whose identity is computed at runtime and so
// must be surfaced by the app. Tracked in #633.
@MainActor
final class MinesweeperE2ETests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Smoke: the app builds, hosts, and reaches the foreground.
    func test_appLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 15),
            "Minesweeper app should reach the foreground after launch"
        )
    }
}
