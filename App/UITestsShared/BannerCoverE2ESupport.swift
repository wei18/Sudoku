import XCTest

// #1058 cover-env E2E, shared by both apps (mirror principle). `makeGameApp`
// injects the session's `BannerSessionModel` next to `\.theme`, and `GameRoot`
// re-injects it on the board `fullScreenCover`, so a board presented through
// that cover renders its own banner slot.
//
// Slots are counted by their "Advertisement" label. A `.fullScreen`
// presentation keeps Today's subtree (and its slot) in the accessibility
// tree, and Today's slot identifier is shadowed by `game.today.root` (#1072),
// so neither an identifier query nor a board-root scope can tell the two
// slots apart: Today's count is measured first and the board must add one.
enum BannerCoverE2ESupport {

    /// Caller already launched with `-uitest-fake-ad-gate-repoll` and lands on
    /// Today. Opens the gate with a real background→foreground cycle, then
    /// opens a daily board through `GameRoot`'s cover.
    /// - Parameters:
    ///   - dailyCardLabelPrefix: the accessibility-label prefix of the daily
    ///     card to open (e.g. "Easy,").
    ///   - boardPauseToggleID: the board's leave/pause control.
    ///   - startGame: brings a freshly opened board into play so its pause
    ///     control pauses (Minesweeper boards stay idle until the first reveal).
    @MainActor
    static func assertBoardCoverRendersBannerSlot(
        in app: XCUIApplication,
        dailyCardLabelPrefix: String,
        boardPauseToggleID: String,
        startGame: (XCUIApplication) -> Void = { _ in },
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let todayRoot = app.descendants(matching: .any)[NegativeNavigationE2ESupport.todayRootID]
        XCTAssertTrue(todayRoot.waitForExistence(timeout: 30), "Today should mount", file: file, line: line)

        ScenePhaseRepollE2ESupport.cycleThroughBackground(app, file: file, line: line)
        ScenePhaseRepollE2ESupport.dismissATTPrimerIfPresent(in: app)
        let slots = ScenePhaseRepollE2ESupport.bannerSlots(in: app)
        XCTAssertTrue(
            slots.firstMatch.waitForExistence(timeout: 15),
            "Today's banner slot should show once the repoll opens the gate",
            file: file, line: line
        )
        let todayCount = slots.count

        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", dailyCardLabelPrefix)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "daily card '\(dailyCardLabelPrefix)' should be on Today", file: file, line: line)
        card.tap()

        let pauseToggle = app.buttons[boardPauseToggleID]
        XCTAssertTrue(
            pauseToggle.waitForExistence(timeout: 30),
            "the board should present through GameRoot's fullScreenCover",
            file: file, line: line
        )
        startGame(app)

        XCTAssertTrue(
            waitForCount(slots, todayCount + 1),
            "a board presented through GameRoot's cover should render its own banner slot"
                + " (Today \(todayCount) + board 1), got \(slots.count)",
            file: file, line: line
        )

        // The paused half is also the Pause row's E2E pin: a paused board is a
        // moment of intentional quiet (v2.3.5 calm contract), so only Today's
        // slot remains.
        pauseToggle.tap()
        XCTAssertTrue(
            app.buttons[GameE2ESupport.resumeButtonID].waitForExistence(timeout: 10),
            "the pause overlay should present",
            file: file, line: line
        )
        XCTAssertTrue(
            waitForCount(slots, todayCount),
            "a paused board should render no banner slot (Today \(todayCount)), got \(slots.count)",
            file: file, line: line
        )
    }

    @MainActor
    private static func waitForCount(_ query: XCUIElementQuery, _ expected: Int, timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while query.count != expected {
            if Date() >= deadline { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return true
    }
}
