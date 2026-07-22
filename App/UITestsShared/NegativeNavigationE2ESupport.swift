import XCTest

// #935 — shared host-driven E2E support for the negative navigation flows in
// docs/navigation-flows.md §4 (N1/N2/N8/N9/N10/N11): every exit affordance
// (Leave, Close, mask-tap-resume, Retry/Close on a load failure) must land
// the player on the DOCUMENTED screen, never stranded on a dismissed
// board/pause/completion surface (the #667 regression class a unit or
// snapshot test structurally cannot catch — only a host-driven launch +
// navigate + assert-landing round trip proves the wiring). Glob'd into BOTH
// SudokuE2ETests and MinesweeperE2ETests (mirror principle, matching
// GameE2ESupport / ScenePhaseRepollE2ESupport).
enum NegativeNavigationE2ESupport {
    /// Shared HOME scaffold anchor (`GameShellUI.HomeScreen`, #935). Both
    /// apps render this at the Home root, so it doubles as "landed back on
    /// Home" for every near-win-launched board (N8/N9/N10/N11 — presented as
    /// a `fullScreenCover` directly over Home by the DEBUG near-win
    /// modifiers) and MS's resume-load-failure loader (N2: `-uitest-route
    /// resumeFail` replaces `path` with a single `.resumeBoard` entry that
    /// `GameBoardRedirect` immediately pops back to empty, presenting the
    /// loader modally over Home — see `GameBoardRedirect.swift`).
    static let homeRootID = "game.home.root"

    /// Close button on the shared `CompletionOverlayScaffold` (N10/N11, #935).
    static let completionCloseID = "game.completion.close"

    /// Leave button on the shared `PauseOverlayView` (N9, #935).
    static let pauseLeaveID = "game.pause.leave"

    /// N10/N11/N9: asserts the player landed back on Home after a
    /// Close/Leave — the stranded-on-solved-board / stranded-on-paused-board
    /// check. The Home anchor must be present AND both the caller's own
    /// board anchor (e.g. `sudoku.board.pauseToggle`) and the completion
    /// hero must be gone.
    @MainActor
    static func assertLandedOnHome(
        in app: XCUIApplication,
        departedBoardAnchorID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let home = app.descendants(matching: .any)[homeRootID]
        XCTAssertTrue(
            home.waitForExistence(timeout: 15),
            "should land back on Home (\(homeRootID)) — not stranded",
            file: file, line: line
        )
        assertDeparted(
            in: app, anchorID: departedBoardAnchorID, surfaceName: "board",
            file: file, line: line
        )
        assertDeparted(
            in: app, anchorID: GameE2ESupport.completionHeroID, surfaceName: "completion",
            file: file, line: line
        )
    }

    /// N1/N2: asserts the player landed back on a NAMED hub (not necessarily
    /// Home — e.g. Practice Hub after Close on a board-load-failure block)
    /// via a caller-supplied stable anchor, and that the departed board
    /// loader's failed block is gone.
    @MainActor
    static func assertLandedOnHub(
        in app: XCUIApplication,
        hubAnchorID: String,
        departedBoardAnchorID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let hub = app.descendants(matching: .any)[hubAnchorID]
        XCTAssertTrue(
            hub.waitForExistence(timeout: 15),
            "should land back on the entry hub (\(hubAnchorID)) — not stranded",
            file: file, line: line
        )
        assertDeparted(
            in: app, anchorID: departedBoardAnchorID, surfaceName: "board loader",
            file: file, line: line
        )
    }

    @MainActor
    private static func assertDeparted(
        in app: XCUIApplication,
        anchorID: String,
        surfaceName: String,
        file: StaticString,
        line: UInt
    ) {
        let element = app.descendants(matching: .any)[anchorID]
        XCTAssertTrue(
            element.waitForNonExistence(timeout: 5),
            "the \(surfaceName) surface (\(anchorID)) should be gone after exiting",
            file: file, line: line
        )
    }

    /// N8: taps the pause overlay's blur mask OUTSIDE the centred card — the
    /// mask (`PauseOverlayView`'s full-screen `Rectangle`) carries no
    /// accessibility identifier of its own, so this taps a point near the
    /// top of the screen. The card is vertically centred and width-capped
    /// (max 340pt, Dynamic Type capped at `.accessibility2`), so a point
    /// near the top edge is reliably outside it on every supported device.
    @MainActor
    static func tapPauseMaskOutsideCard(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
    }
}
