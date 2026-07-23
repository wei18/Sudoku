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

    /// #940 regression guard: `ReminderPrimerSheet` used to self-dismiss ~1s
    /// after presenting — a `.sheet` hosted inside the Settings List's
    /// `Section` got its host duplicated when the tap-time async permission
    /// status write swapped that Section's row content mid-presentation.
    /// Requires launch with `-uitest-route settings` and the REAL (unfaked)
    /// reminder authorizer: the fresh-install `.notDetermined` default plus
    /// the actual `getNotificationSettings` async latency is what reproduced
    /// the race, so this deliberately does NOT use `fakeReminderRepoll`.
    @MainActor
    static func assertReminderPrimerPersistsPastStatusRepoll(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let enableRow = app.descendants(matching: .any)["reminders.settings.enable"]
        XCTAssertTrue(
            enableRow.waitForExistence(timeout: 15),
            "reminders.settings.enable should render at launch (fresh install is notDetermined)",
            file: file, line: line
        )
        enableRow.tap()

        let primer = app.descendants(matching: .any)["reminders.primer.sheet"]
        XCTAssertTrue(
            primer.waitForExistence(timeout: 3),
            "reminders.primer.sheet should present after tapping the enable row",
            file: file, line: line
        )

        // The pre-fix teardown landed ~1–1.5s after presenting; wait past it.
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(
            primer.exists,
            "reminders.primer.sheet should still be presented 3s later — a List row-diffing"
                + " duplicate presentation used to tear it down here",
            file: file, line: line
        )
    }
}
