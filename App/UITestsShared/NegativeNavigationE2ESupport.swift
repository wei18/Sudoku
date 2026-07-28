import XCTest

// #935 — shared host-driven E2E support for the negative navigation flows in
// docs/navigation-flows.md §4 (N1/N2/N8/N9/N10/N11/N12/N13/N14): every exit affordance
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

    /// Settings Game Center row (`SettingsScreen`, shared SettingsUI — same
    /// id both apps render). N14's tap target AND, after the alert dismisses,
    /// its own "origin unchanged" anchor.
    static let settingsGameCenterRowID = "settings.gameCenter"

    /// N14 (#935 batch 4): tapping the Settings GC row while signed out must
    /// show the system `GC-SIGNED-OUT-ALERT` and OK must dismiss it WITHOUT
    /// any route change — the stranding check. Caller must already be routed
    /// to Settings with `-uitest-gc-signed-out` set
    /// (`UITestSignedOutGameCenterClient`), so `authState` is deterministically
    /// `.unauthenticated`.
    @MainActor
    static func assertGCSignedOutAlertDismissesInPlace(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let gcRow = app.buttons[settingsGameCenterRowID]
        XCTAssertTrue(
            gcRow.waitForExistence(timeout: 15),
            "N14: Settings GC row (\(settingsGameCenterRowID)) should be present",
            file: file, line: line
        )
        gcRow.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(
            alert.waitForExistence(timeout: 10),
            "N14: GC signed-out alert should appear under the -uitest-gc-signed-out seam",
            file: file, line: line
        )
        alert.buttons.firstMatch.tap()

        XCTAssertTrue(
            alert.waitForNonExistence(timeout: 5),
            "N14: OK should dismiss the alert",
            file: file, line: line
        )
        XCTAssertTrue(
            gcRow.waitForExistence(timeout: 5),
            "N14: origin (Settings GC row) should remain present — no route change",
            file: file, line: line
        )
    }

    /// "Not now" on the ATT primer sheet (`ATTPrimerSheet`, #935 batch 5 N15).
    static let attPrimerNotNowID = "att.primer.notNow"

    /// N15 (#935 batch 5): caller already launched with
    /// `-uitest-fake-ad-gate-repoll` + `-uitest-att-primer` and lands on
    /// HOME. The banner slot's ad-gate (faked open only after a real
    /// background→foreground cycle — same mechanism
    /// `ScenePhaseRepollE2ESupport` pins) fires `onAdContext` on its first
    /// load, which is the ATT primer's ONLY trigger
    /// (`ATTPrimerCoordinator.maybePresentOnAdContext()`), so the sheet
    /// presents only after that first cycle. Asserts "Not now" dismisses it,
    /// Home stays present, and a SECOND background→foreground cycle does
    /// NOT re-present it (the `hasOffered` latch).
    @MainActor
    static func assertATTPrimerDeclineDismissesAndLatches(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let home = app.descendants(matching: .any)[homeRootID]
        XCTAssertTrue(
            home.waitForExistence(timeout: 15),
            "N15: should land on Home before the ad-gate repoll",
            file: file, line: line
        )

        let notNow = app.buttons[attPrimerNotNowID]
        XCTAssertFalse(
            notNow.waitForExistence(timeout: 3),
            "N15: the ATT primer should NOT present before a real background→foreground cycle",
            file: file, line: line
        )

        ScenePhaseRepollE2ESupport.cycleThroughBackground(app, file: file, line: line)

        XCTAssertTrue(
            notNow.waitForExistence(timeout: 15),
            "N15: ATT primer sheet should present after the ad-gate repoll opens under -uitest-att-primer",
            file: file, line: line
        )
        notNow.tap()

        XCTAssertTrue(
            notNow.waitForNonExistence(timeout: 5),
            "N15: 'Not now' should dismiss the primer sheet",
            file: file, line: line
        )
        XCTAssertTrue(
            home.exists,
            "N15: Home should remain present — no navigation on decline",
            file: file, line: line
        )

        // Latch check: a second background→foreground cycle must NOT re-offer.
        ScenePhaseRepollE2ESupport.cycleThroughBackground(app, file: file, line: line)
        XCTAssertFalse(
            notNow.waitForExistence(timeout: 5),
            "N15: the primer should stay latched (hasOffered) and not re-present after a second cycle",
            file: file, line: line
        )
    }

    /// Settings "Remove Ads" row (`RemoveAdsRow`, #935 batch 5 N22).
    static let removeAdsRowID = "settings.iap.removeAds"

    /// N22 (#935 batch 5): caller already routed to Settings with
    /// `-uitest-iap-script` set (`UITestScriptedIAPClient` — cancel → fail →
    /// pending, in that order). Walks all three `purchaseRemoveAds()`
    /// branches from one Remove Ads row: cancel is silent (no toast), fail
    /// raises the failure toast, pending raises its own failure-style toast
    /// — throughout, no navigation, no system sheet/alert, and the row stays
    /// present (no entitlement granted).
    @MainActor
    static func assertIAPPurchaseCancelFailPendingStayInPlace(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let removeAds = app.buttons[removeAdsRowID]
        XCTAssertTrue(
            removeAds.waitForExistence(timeout: 15),
            "N22: Settings Remove Ads row should be present",
            file: file, line: line
        )
        let successToast = app.descendants(matching: .any)[monetizationToastSuccessID]
        let failureToast = app.descendants(matching: .any)[monetizationToastFailureID]

        // 1) userCancelled — silent, no toast.
        removeAds.tap()
        XCTAssertFalse(
            successToast.waitForExistence(timeout: 3) || failureToast.waitForExistence(timeout: 1),
            "N22: a cancelled purchase must never raise a toast",
            file: file, line: line
        )
        XCTAssertTrue(removeAds.exists, "N22: should remain on Settings after cancel", file: file, line: line)

        // 2) failed(reason:) — failure toast.
        removeAds.tap()
        XCTAssertTrue(
            failureToast.waitForExistence(timeout: 10),
            "N22: a failed purchase should raise the failure toast under -uitest-iap-script",
            file: file, line: line
        )
        XCTAssertTrue(removeAds.exists, "N22: should remain on Settings after a failed purchase", file: file, line: line)

        // Wait out the auto-dismiss (Toast.duration default 3s) so the
        // pending toast below isn't confused with a still-visible one.
        XCTAssertTrue(
            failureToast.waitForNonExistence(timeout: 6),
            "N22: the failure toast should auto-dismiss",
            file: file, line: line
        )

        // 3) pending — its own failure-style toast (MonetizationStateController
        // routes `.pending` through the same `.failure` toast style).
        removeAds.tap()
        XCTAssertTrue(
            failureToast.waitForExistence(timeout: 10),
            "N22: a pending purchase should raise its own (failure-style) toast",
            file: file, line: line
        )
        XCTAssertTrue(removeAds.exists, "N22: should remain on Settings after a pending purchase", file: file, line: line)
        XCTAssertFalse(app.sheets.firstMatch.exists, "N22: no system payment sheet should ever appear", file: file, line: line)
        XCTAssertFalse(app.alerts.firstMatch.exists, "N22: no system alert should ever appear", file: file, line: line)
    }
}
