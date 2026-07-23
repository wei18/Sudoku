import XCTest

// #510 Phase 3 — Minesweeper host-driven E2E happy path (#633).
//
// Named `MinesweeperE2ETests` (mirrors `SudokuE2ETests`) to avoid colliding
// with the SPM snapshot/unit target `MinesweeperUITests` in Packages; this one
// drives the real app on the simulator.
//
// Reaches win → completion deterministically via the #510 Phase-1 DEBUG hook
// `-uitest-near-win`: the app boots into a fixed-seed board with every safe
// cell revealed except one, presented under a paused cover. Unlike Sudoku — a
// wrong digit there is harmless and can be brute-forced — a wrong tap here hits
// a hidden mine (a loss), so the test must tap the EXACT remaining safe cell.
// Its runtime (row, col) is surfaced by the DEBUG winning-cell beacon
// (`game.uitest.winningCell.r<R>.c<C>`, MinesweeperNearWinModifier); the test
// parses it and taps that cell by its unique, non-localized a11y label.
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

    /// Happy path: near-win board → resume → reveal the one safe cell →
    /// completion overlay appears.
    func test_winToCompletion() {
        let app = XCUIApplication()
        app.launchArguments += [UITestLaunchArg.nearWin]
        app.launch()
        Self.driveToWin(app)
    }

    /// #935 N11: Completion Close (`MinesweeperBoardView`'s in-board overlay,
    /// always `dismiss()`) must land the player back on Home — never
    /// stranded on the solved board.
    func test_completionCloseLandsOnHome_N11() {
        let app = XCUIApplication()
        app.launchArguments += [UITestLaunchArg.nearWin]
        app.launch()
        Self.driveToWin(app)

        app.buttons[NegativeNavigationE2ESupport.completionCloseID].tap()
        NegativeNavigationE2ESupport.assertLandedOnHome(
            in: app,
            departedBoardAnchorID: "minesweeper.board.pauseToggle"
        )
    }

    /// #935 N9: Pause → Leave (`MinesweeperBoardView`'s `PauseOverlayView
    /// (onLeave: { dismiss() })`) must land the player back on Home. The
    /// near-win board mounts already paused, so Leave is available immediately.
    func test_pauseLeaveLandsOnHome_N9() {
        let app = XCUIApplication()
        app.launchArguments += [UITestLaunchArg.nearWin]
        app.launch()

        let leave = app.buttons[NegativeNavigationE2ESupport.pauseLeaveID]
        XCTAssertTrue(
            leave.waitForExistence(timeout: 20),
            "N9: near-win board should mount paused with Leave available"
        )
        leave.tap()

        NegativeNavigationE2ESupport.assertLandedOnHome(
            in: app,
            departedBoardAnchorID: "minesweeper.board.pauseToggle"
        )
    }

    /// #935 N8: tapping the pause mask OUTSIDE the card resumes IN PLACE —
    /// same as tapping Resume, no navigation. The near-win board mounts
    /// already paused.
    func test_pauseMaskTapResumesInPlace_N8() {
        let app = XCUIApplication()
        app.launchArguments += [UITestLaunchArg.nearWin]
        app.launch()

        let resume = app.buttons[GameE2ESupport.resumeButtonID]
        XCTAssertTrue(
            resume.waitForExistence(timeout: 20),
            "near-win board should mount under the paused cover"
        )

        NegativeNavigationE2ESupport.tapPauseMaskOutsideCard(in: app)

        XCTAssertTrue(
            resume.waitForNonExistence(timeout: 5),
            "N8: mask tap should resume (Resume overlay gone)"
        )
        let pauseToggle = app.buttons["minesweeper.board.pauseToggle"]
        XCTAssertTrue(
            pauseToggle.waitForExistence(timeout: 10),
            "N8: board should remain present — resumed in place, no navigation"
        )
    }

    /// #935 N2: `.resumeBoard` load failure (`MinesweeperBoardLoaderView` →
    /// `.failed`) — MS's ONLY reachable path to that loader. A missing
    /// resume record honestly fails, never a silent fresh board. Retry
    /// re-runs `load()` in place (stays failed — the record is still
    /// missing); Close lands back on Home.
    func test_resumeLoadFailureRetryThenCloseLandsOnHome_N2() {
        let app = XCUIApplication()
        app.launchArguments += [UITestLaunchArg.route, "resumeFail"]
        app.launch()

        let retry = app.buttons["minesweeper.boardLoader.retry"]
        XCTAssertTrue(
            retry.waitForExistence(timeout: 15),
            "N2: missing resume record should honestly fail, never a silent fresh board"
        )

        retry.tap()
        XCTAssertTrue(
            retry.waitForExistence(timeout: 10),
            "N2: Retry re-runs load() in place and stays failed (record still missing) — no crash/blank"
        )

        app.buttons["minesweeper.boardLoader.close"].tap()
        NegativeNavigationE2ESupport.assertLandedOnHome(
            in: app,
            departedBoardAnchorID: "minesweeper.boardLoader.retry"
        )
    }

    /// #935 batch 3 N13: Completion Close on the daily RE-VIEW route
    /// (`MS-COMPLETION-REVIEW`, pushed from a completed daily card — NOT the
    /// in-board overlay N11 already covers) pops exactly one path entry back
    /// to the Daily hub (#697 fix, symmetric with Sudoku's N12).
    /// Completed-daily state lives in CloudKit Private DB and can't be
    /// produced by real play on the CI simulator, so
    /// `-uitest-seed-completed-daily` (DEBUG-only fake
    /// `MinesweeperDailyOverlayReading`) seeds today's trio as already
    /// completed. Unlike Sudoku, MS's completed-card tap is fully
    /// synchronous (no snapshot fetch) — no async hop to wait out.
    func test_completionReviewCloseLandsOnDailyHub_N13() {
        let app = XCUIApplication()
        app.launchArguments += [
            UITestLaunchArg.seedCompletedDaily,
            UITestLaunchArg.route, "daily",
        ]
        app.launch()

        // All three seeded daily cards render completed, so this identifier
        // is not unique on the hub — `.firstMatch` (any of the three works;
        // the assertion only cares that Close pops back to the hub).
        let completedCard = app.descendants(matching: .any)
            .matching(identifier: "minesweeper.dailyHub.card.completed")
            .firstMatch
        XCTAssertTrue(
            completedCard.waitForExistence(timeout: 15),
            "N13: a completed daily card should appear under the -uitest-seed-completed-daily seam"
        )
        completedCard.tap()

        GameE2ESupport.assertCompletionAppears(in: app)

        app.buttons[NegativeNavigationE2ESupport.completionCloseID].tap()
        NegativeNavigationE2ESupport.assertLandedOnHub(
            in: app,
            hubAnchorID: "minesweeper.dailyHub.root",
            departedBoardAnchorID: GameE2ESupport.completionHeroID
        )
    }

    /// #935 batch 4 N14: GC signed-out alert (`GC-SIGNED-OUT-ALERT`) — the
    /// Settings GC row, while Game Center is signed out, must show the
    /// system alert and OK must dismiss it WITHOUT any route change (the
    /// stranding check). `-uitest-gc-signed-out` forces `authState` to
    /// `.unauthenticated` (`UITestSignedOutGameCenterClient`) — CI sim GC is
    /// signed out in practice, but the live handshake is nondeterministic.
    func test_gcSignedOutAlertDismissesInPlace_N14() {
        let app = XCUIApplication()
        app.launchArguments += [
            UITestLaunchArg.gcSignedOut,
            UITestLaunchArg.route, "settings",
        ]
        app.launch()
        NegativeNavigationE2ESupport.assertGCSignedOutAlertDismissesInPlace(in: app)
    }

    /// Shared near-win drive (#935: reused by both the happy-path smoke test
    /// and the N9/N8/N11 negative-flow tests). Unlike Sudoku — a wrong digit
    /// there is harmless and can be brute-forced — a wrong tap here hits a
    /// hidden mine (a loss), so the test must tap the EXACT remaining safe
    /// cell. Its runtime (row, col) is surfaced by the DEBUG winning-cell
    /// beacon (`game.uitest.winningCell.r<R>.c<C>`,
    /// MinesweeperNearWinModifier); this parses it and taps that cell by its
    /// unique, non-localized a11y label.
    @MainActor
    private static func driveToWin(_ app: XCUIApplication) {
        // Read the winning cell's (row, col) from the DEBUG beacon.
        let beacon = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "game.uitest.winningCell."))
            .firstMatch
        guard beacon.waitForExistence(timeout: 20) else {
            XCTFail("near-win winning-cell beacon should be present after launch.\n\(app.debugDescription)")
            return
        }
        guard let (row, col) = Self.parseWinningCell(beacon.identifier) else {
            XCTFail("could not parse winning cell from beacon id '\(beacon.identifier)'")
            return
        }

        // The near-win board mounts paused — dismiss the cover before revealing.
        // `viewModel.resume()` is async (`Task { await … }`), and the safe cell
        // already exists in the a11y tree behind the cover, so we must wait for
        // the resume button to LEAVE the tree (cover dismissed) before tapping —
        // otherwise the cover can swallow the reveal tap on a slow machine.
        let resume = app.buttons[GameE2ESupport.resumeButtonID]
        XCTAssertTrue(
            resume.waitForExistence(timeout: 10),
            "near-win board should mount under the paused cover"
        )
        resume.tap()
        XCTAssertTrue(
            resume.waitForNonExistence(timeout: 5),
            "pause cover should dismiss after tapping resume"
        )

        // Tap the one remaining safe cell by its unique positional label
        // (coordinates are 1-based in the a11y label). "Hidden" is the covered
        // state set by MinesweeperCellButton. As of #741 (Hidden) and #755
        // (Row/Column) all three tokens are catalog-routed, so this query
        // matches the en-locale rendering only — the E2E suite runs under the
        // simulator's default en locale.
        let safeCell = app.buttons["Row \(row + 1), Column \(col + 1), Hidden"]
        XCTAssertTrue(
            safeCell.waitForExistence(timeout: 10),
            "the one safe cell (Row \(row + 1), Column \(col + 1)) should be tappable after resume"
        )
        safeCell.tap()

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

    /// Parse `game.uitest.winningCell.r<R>.c<C>` → (row, col).
    private static func parseWinningCell(_ identifier: String) -> (row: Int, col: Int)? {
        let parts = identifier.components(separatedBy: ".")
        guard
            let rToken = parts.first(where: { $0.hasPrefix("r") && Int($0.dropFirst()) != nil }),
            let cToken = parts.first(where: { $0.hasPrefix("c") && Int($0.dropFirst()) != nil }),
            let row = Int(rToken.dropFirst()),
            let col = Int(cToken.dropFirst())
        else { return nil }
        return (row, col)
    }
}
