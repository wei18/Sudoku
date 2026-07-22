import XCTest

// #510 Phase 3 — Sudoku host-driven E2E happy path.
//
// Named `SudokuE2ETests` (not `SudokuUITests`) to avoid colliding with the SPM
// snapshot/unit target of that name in Packages/SudokuKit (which renders views
// headless, no host app); this one drives the real app on the simulator.
//
// Reaches the win → completion flow deterministically via the #510 Phase-1
// DEBUG launch hook `-uitest-near-win-modal`: the app boots straight into a
// fixed-seed board one move from winning, presented through the PRODUCTION
// modal path so the #610 in-board Completion overlay fires on the winning tap.
//
// Element queries: only the completion hero is locale-independent — it
// exposes the identifier `game.completion.hero` (added in GameShellUI for
// this flow). The digit-pad buttons' a11y labels ("Digit 1"…"Digit 9") are
// catalog-routed via the "Digit %lld" key (LocalizedStringKey literal), and
// the one empty board cell's "Row R, Column C, Empty" label is catalog-routed
// as of #755/#771 — so those queries match the en-locale rendering only; the
// E2E suite runs under the simulator's default en locale.
@MainActor
final class SudokuE2ETests: XCTestCase {

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
            "Sudoku app should reach the foreground after launch"
        )
    }

    /// Happy path: near-win board → winning move → completion overlay appears.
    func test_winToCompletion() {
        let app = XCUIApplication()
        app.launchArguments += [UITestLaunchArg.nearWinModal]
        app.launch()
        Self.driveToWin(app)
    }

    /// #935 N10: Completion Close (`BoardView+Completion.exitToHub`) must land
    /// the player back on Home — never stranded on the solved board (the #667
    /// regression class). Reaches completion via the same near-win-modal path
    /// as `test_winToCompletion`, then asserts Close's destination.
    func test_completionCloseLandsOnHome_N10() {
        let app = XCUIApplication()
        app.launchArguments += [UITestLaunchArg.nearWinModal]
        app.launch()
        Self.driveToWin(app)

        app.buttons[NegativeNavigationE2ESupport.completionCloseID].tap()
        NegativeNavigationE2ESupport.assertLandedOnHome(
            in: app,
            departedBoardAnchorID: "sudoku.board.pauseToggle"
        )
    }

    /// #935 N9: Pause → Leave (`BoardView`'s `PauseOverlayView(onLeave:
    /// { dismiss() })`) must land the player back on Home.
    func test_pauseLeaveLandsOnHome_N9() {
        let app = XCUIApplication()
        app.launchArguments += [UITestLaunchArg.nearWinModal]
        app.launch()

        let pauseToggle = app.buttons["sudoku.board.pauseToggle"]
        XCTAssertTrue(
            pauseToggle.waitForExistence(timeout: 20),
            "near-win board should present after launch"
        )
        pauseToggle.tap()

        let leave = app.buttons[NegativeNavigationE2ESupport.pauseLeaveID]
        XCTAssertTrue(leave.waitForExistence(timeout: 10), "N9: pause overlay should present Leave")
        leave.tap()

        NegativeNavigationE2ESupport.assertLandedOnHome(
            in: app,
            departedBoardAnchorID: "sudoku.board.pauseToggle"
        )
    }

    /// #935 N8: tapping the pause mask OUTSIDE the card resumes IN PLACE —
    /// same as tapping Resume, no navigation (`PauseOverlayView`'s
    /// `.onTapGesture { onResume() }` on the full-screen blur).
    func test_pauseMaskTapResumesInPlace_N8() {
        let app = XCUIApplication()
        app.launchArguments += [UITestLaunchArg.nearWinModal]
        app.launch()

        let pauseToggle = app.buttons["sudoku.board.pauseToggle"]
        XCTAssertTrue(
            pauseToggle.waitForExistence(timeout: 20),
            "near-win board should present after launch"
        )
        pauseToggle.tap()

        let resume = app.buttons[GameE2ESupport.resumeButtonID]
        XCTAssertTrue(resume.waitForExistence(timeout: 10), "N8: pause overlay should present Resume")

        NegativeNavigationE2ESupport.tapPauseMaskOutsideCard(in: app)

        XCTAssertTrue(
            resume.waitForNonExistence(timeout: 5),
            "N8: mask tap should resume (Resume overlay gone)"
        )
        XCTAssertTrue(
            pauseToggle.exists,
            "N8: board should remain present — resumed in place, no navigation"
        )
    }

    /// #935 N1: fresh `.board` load failure (`BoardLoaderView` → `.failed`)
    /// via the practice hub's "New Game" CTA. Retry re-runs `load()` in place
    /// (stays failed under the `-uitest-loader-fail` seam, no crash/blank);
    /// Close lands back on Practice Hub, never stranded on the loader.
    func test_boardLoadFailureRetryThenCloseLandsOnHub_N1() {
        let app = XCUIApplication()
        app.launchArguments += [
            UITestLaunchArg.loaderFail,
            UITestLaunchArg.route, "practice",
        ]
        app.launch()

        let start = app.buttons["sudoku.practiceHub.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "practice hub CTA should be present")
        start.tap()

        let retry = app.buttons["sudoku.boardLoader.retry"]
        XCTAssertTrue(
            retry.waitForExistence(timeout: 15),
            "N1: board-load-failure block should appear under the -uitest-loader-fail seam"
        )

        retry.tap()
        XCTAssertTrue(
            retry.waitForExistence(timeout: 10),
            "N1: Retry re-runs load() in place and stays failed under the seam — no crash/blank"
        )

        app.buttons["sudoku.boardLoader.close"].tap()
        NegativeNavigationE2ESupport.assertLandedOnHub(
            in: app,
            hubAnchorID: "sudoku.practiceHub.start",
            departedBoardAnchorID: "sudoku.boardLoader.retry"
        )
    }

    /// #935 batch 2 N3: Sudoku Practice draw failure
    /// (`PracticeHubViewModel.drawPuzzle()`'s catch branch, seeded via
    /// `-uitest-puzzle-fault practiceFail`) shows an inline failure caption on
    /// the hub — no navigation, and the "New Game" CTA stays re-enabled for a
    /// retry.
    func test_practiceDrawFailureShowsCaptionNoNavigation_N3() {
        let app = XCUIApplication()
        app.launchArguments += [
            UITestLaunchArg.puzzleFault, "practiceFail",
            UITestLaunchArg.route, "practice",
        ]
        app.launch()

        let start = app.buttons["sudoku.practiceHub.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "practice hub CTA should be present")
        start.tap()

        let failure = app.descendants(matching: .any)["sudoku.practiceHub.failure"]
        XCTAssertTrue(
            failure.waitForExistence(timeout: 10),
            "N3: draw failure should show an inline caption under the -uitest-puzzle-fault seam"
        )
        XCTAssertTrue(start.exists, "N3: CTA should stay on the hub — no navigation on a failed draw")
        XCTAssertTrue(start.isEnabled, "N3: CTA should be re-enabled after a failed draw")
    }

    /// #935 batch 2 N4: Sudoku Daily `.exhausted` (generator defect, seeded
    /// via `-uitest-puzzle-fault dailyExhausted`) — "Practice" swaps the last
    /// path entry `.daily` → `.practice`, landing on the Practice hub.
    func test_dailyExhaustedPracticeLandsOnPracticeHub_N4() {
        let app = XCUIApplication()
        app.launchArguments += [
            UITestLaunchArg.puzzleFault, "dailyExhausted",
            UITestLaunchArg.route, "daily",
        ]
        app.launch()

        let exhausted = app.descendants(matching: .any)["sudoku.dailyHub.exhausted"]
        XCTAssertTrue(
            exhausted.waitForExistence(timeout: 15),
            "N4: exhausted block should appear under the -uitest-puzzle-fault seam"
        )

        app.buttons["sudoku.dailyHub.exhausted.practice"].tap()

        NegativeNavigationE2ESupport.assertLandedOnHub(
            in: app,
            hubAnchorID: "sudoku.practiceHub.start",
            departedBoardAnchorID: "sudoku.dailyHub.exhausted"
        )
    }

    /// #935 batch 2 N4: Sudoku Daily `.exhausted` — "Cancel" pops back to
    /// HOME rather than leaving the player on the exhausted hub's blank
    /// backdrop (#686).
    func test_dailyExhaustedCancelLandsOnHome_N4() {
        let app = XCUIApplication()
        app.launchArguments += [
            UITestLaunchArg.puzzleFault, "dailyExhausted",
            UITestLaunchArg.route, "daily",
        ]
        app.launch()

        let exhausted = app.descendants(matching: .any)["sudoku.dailyHub.exhausted"]
        XCTAssertTrue(
            exhausted.waitForExistence(timeout: 15),
            "N4: exhausted block should appear under the -uitest-puzzle-fault seam"
        )

        app.buttons["sudoku.dailyHub.exhausted.cancel"].tap()

        NegativeNavigationE2ESupport.assertLandedOnHome(
            in: app,
            departedBoardAnchorID: "sudoku.dailyHub.exhausted"
        )
    }

    /// #935 batch 2 N5: Sudoku Daily `.failed` (fetch error, not exhaustion,
    /// seeded via `-uitest-puzzle-fault dailyFail`) — inline warning + reason
    /// text, NO system alert, no navigation off the hub.
    func test_dailyLoadFailureShowsInlineWarning_N5() {
        let app = XCUIApplication()
        app.launchArguments += [
            UITestLaunchArg.puzzleFault, "dailyFail",
            UITestLaunchArg.route, "daily",
        ]
        app.launch()

        let failure = app.descendants(matching: .any)["sudoku.dailyHub.failure"]
        XCTAssertTrue(
            failure.waitForExistence(timeout: 15),
            "N5: inline failure surface should appear under the -uitest-puzzle-fault seam"
        )
        XCTAssertFalse(
            app.alerts.firstMatch.exists,
            "N5: a daily fetch failure must never surface a system alert"
        )
        XCTAssertTrue(failure.exists, "N5: should remain on the daily hub's inline failure surface, no navigation")
    }

    /// Shared winning-move drive for the near-win-modal board (#935: reused
    /// by both the happy-path smoke test and the N10 negative-flow test).
    /// The fixed-seed near-win board has exactly ONE empty cell, whose a11y
    /// label ends in "Empty". Query across element types — SwiftUI cells
    /// carrying the `.isButton` trait are not always classified as buttons.
    @MainActor
    private static func driveToWin(_ app: XCUIApplication) {
        let emptyCell = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label ENDSWITH %@", "Empty"))
            .firstMatch
        if !emptyCell.waitForExistence(timeout: 20) {
            XCTFail("near-win board (one empty cell) should present after launch.\n\(app.debugDescription)")
            return
        }

        // Resolve the empty cell to an ABSOLUTE screen point once — its a11y
        // label flips from "…Empty" to "…value N" as soon as a digit lands, so
        // an element-anchored coordinate would go stale on the second attempt.
        // An app-relative offset keeps re-selecting the same physical cell.
        let cellFrame = emptyCell.frame
        let cellPoint = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: cellFrame.midX, dy: cellFrame.midY))

        let completionHero = app.descendants(matching: .any)[GameE2ESupport.completionHeroID]

        // Brute-force the winning digit: this Sudoku has no mistake limit, so a
        // wrong digit is simply overwritten by the next. The correct digit wins
        // → the #610 completion overlay presents → we stop.
        for digit in 1...9 {
            cellPoint.tap()
            app.buttons["Digit \(digit)"].tap()
            if completionHero.waitForExistence(timeout: 2) { break }
        }

        GameE2ESupport.assertCompletionAppears(in: app)
    }

    /// #931: pins `ReminderSettingsSection`'s `.onChange(of: scenePhase)`
    /// re-poll hook (#929) — the denied → authorized row swap only happens
    /// after a real background→foreground cycle (see
    /// ScenePhaseRepollE2ESupport for the discriminating-fake design).
    func test_reminderSettingsRepollsOnForeground() {
        let app = XCUIApplication()
        app.launchArguments += [
            UITestLaunchArg.fakeReminderRepoll,
            UITestLaunchArg.route, "settings",
        ]
        app.launch()
        ScenePhaseRepollE2ESupport.assertReminderScenePhaseRepoll(in: app)
    }

    /// #931: pins `BannerSlotView`'s `.onChange(of: scenePhase)` repoll hook
    /// (`repollGate()`, #341) — the hidden → visible slot swap only happens
    /// after a real background→foreground cycle.
    func test_bannerSlotRepollsOnForeground() {
        let app = XCUIApplication()
        app.launchArguments += [UITestLaunchArg.fakeAdGateRepoll]
        app.launch()
        ScenePhaseRepollE2ESupport.assertBannerScenePhaseRepoll(in: app)
    }
}
