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

        // The fixed-seed near-win board has exactly ONE empty cell, whose a11y
        // label ends in "Empty". Query across element types — SwiftUI cells
        // carrying the `.isButton` trait are not always classified as buttons.
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
}
