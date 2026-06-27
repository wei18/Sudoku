import XCTest

// #510 Phase 3 — shared host-driven E2E helpers, glob'd into BOTH the
// SudokuE2ETests and MinesweeperE2ETests targets (mirror principle). The
// game-specific winning move stays in each app's test (Sudoku brute-forces the
// digit pad; Minesweeper taps the one safe cell via its #633 beacon), but the
// stable anchor identifiers and the completion assertion are identical, so they
// live here once.
enum GameE2ESupport {
    /// Completion overlay hero — `CompletionScreen.hero` in GameShellUI. Both
    /// apps render that shared view, so this single identifier serves both.
    static let completionHeroID = "game.completion.hero"

    /// Resume button on the shared `PauseOverlayView` (GameShellUI). Lets a test
    /// dismiss the paused-board cover without depending on its localized label.
    static let resumeButtonID = "game.pause.resume"

    /// Wait for the completion overlay to present after the winning move.
    @MainActor
    static func assertCompletionAppears(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let hero = app.descendants(matching: .any)[completionHeroID]
        XCTAssertTrue(
            hero.waitForExistence(timeout: 10),
            "completion overlay (\(completionHeroID)) should appear after the winning move",
            file: file,
            line: line
        )
    }
}
