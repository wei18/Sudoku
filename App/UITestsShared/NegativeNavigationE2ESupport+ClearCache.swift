import XCTest

// #935 batch 5 N19 (clear-cache Cancel/failure-toast) — split out of
// `NegativeNavigationE2ESupport.swift` to keep that file under the 400-line
// SwiftLint ceiling (same pattern as `NegativeNavigationE2ESupport+Restore.swift`
// — Tuist's shared-target source glob picks this file up automatically).
extension NegativeNavigationE2ESupport {
    /// Settings Storage "Clear cache" row + confirmation-dialog buttons
    /// (`SettingsStorageSection`, #935 batch 5 N19).
    static let clearCacheRowID = "settings.storage.clearCache"
    static let clearCacheConfirmID = "settings.storage.clearCache.confirm"
    static let clearCacheCancelID = "settings.storage.clearCache.cancel"
    static let monetizationToastFailureID = "monetization.toast.failure"
    static let monetizationToastSuccessID = "monetization.toast.success"

    /// #956: zero-size, non-localized anchor (`SettingsStorageSection`'s
    /// `.background` sibling marker) that exists ONLY once
    /// `SettingsViewModel.isCacheStateReady` is `true` — i.e. once
    /// `clearCache()`'s `if let candidate = resumeCandidate` precondition has
    /// settled. Waiting for this BEFORE tapping the row closes the N19 race
    /// (see the doc comment on `assertClearCacheCancelAndFailureToast` below).
    static let clearCacheStateReadyID = "settings.storage.cacheReady"

    /// #956: the `.confirmationDialog` popover's full-screen dismiss backdrop
    /// — verified empirically (idb `ui_describe_all` on iOS 26.5) to be a
    /// discrete accessibility element in its own right (role Group, AXLabel
    /// "dismiss popup", `AXUniqueId "PopoverDismissRegion"`), distinct from
    /// `clearCacheCancelID`'s button (which still renders no element). Tapping
    /// THIS element — instead of a fixed normalized-offset coordinate — lets
    /// XCUITest resolve its own hittable point against the CURRENT layout on
    /// every run, so the dismiss tap can never land inside the dialog's box
    /// regardless of Dynamic Type or a longer localized title.
    static let popoverDismissRegionID = "PopoverDismissRegion"

    /// N19 (#935 batch 5): caller already routed to Settings with
    /// `-uitest-clear-cache-fail` set (`UITestClearCacheFailPersistence` — a
    /// synthetic in-progress saved game so the row/dialog are reachable,
    /// `deleteAbandoned` throws). Cancel half: dialog dismisses, no toast,
    /// stays on Settings. Failure half: confirming raises the failure toast,
    /// stays on Settings, no navigation.
    ///
    /// The "Storage" section is the LAST section on `SETTINGS`'s long Form
    /// (Purchases/GC/Reminders/Sound/About/Notices all precede it) — it does
    /// NOT exist in the accessibility tree until scrolled into view (SwiftUI
    /// `Form`/`List` lazily materializes rows), so this scrolls first
    /// (verified empirically via idb `ui_describe_all` — the row only
    /// appears after two swipe-ups on an iPhone 17 Pro–class screen).
    ///
    /// Also verified empirically: on this environment, `.confirmationDialog`
    /// presents as a CENTERED POPOVER, not a bottom action sheet — the
    /// `role: .cancel` "Cancel" button renders no separate accessibility
    /// element at all (idb's `ui_describe_all` shows only the destructive
    /// confirm button), but the popover's own full-screen dismiss backdrop
    /// DOES (`popoverDismissRegionID`, #956) — Cancel is a tap on that
    /// element.
    ///
    /// #956 diagnosis: the issue's original "fixed backdrop coordinate"
    /// hypothesis turned out to be WRONG. Repeat-running under contention
    /// reproduced a flake at a consistent ~15-50% rate (worse under heavier
    /// host load, but present even in a clean single-suite run with no
    /// deliberate contention) — always the SAME assertion, and the
    /// Cancel/backdrop-dismiss half always succeeded. Root cause (confirmed
    /// by reading `SettingsViewModel.clearCache()`,
    /// `Packages/GameAppKit/Sources/GameAppKit/SettingsViewModel.swift:87-112`):
    /// `deleteAbandoned` is only called `if let candidate = resumeCandidate`,
    /// and `resumeCandidate` is populated by `bootstrap()`'s async
    /// `persistence.latestInProgress()` fetch, fired from
    /// `SettingsView`'s `.task`. If that fetch hadn't resolved by the time
    /// this test tapped Confirm — a race, worse under host CPU contention —
    /// `clearCache()` silently fell through to the UNCONDITIONAL SUCCESS
    /// toast branch instead of the failure one, so the failure toast this
    /// assertion waits for never appeared. This was a genuine
    /// precondition/timing race in `SettingsViewModel`, not a test-harness
    /// element-handling defect — closed product-side (#956) by
    /// `SettingsViewModel.isCacheStateReady` + `clearCacheStateReadyID`
    /// (above): this test now waits for that anchor before touching the row
    /// at all, so it can never race the async load.
    ///
    /// Also hardened here, per issue direction (a) — genuine improvements to
    /// the Cancel/backdrop half, confirmed correct by repeat-running (every
    /// pre-fix failure was at the toast assertion above, never at these
    /// waits): wait for the confirm button to be genuinely `isHittable` (not
    /// merely `exists`) before every tap, and re-query a FRESH handle for
    /// the reopened dialog instead of reusing the pre-Cancel one — a
    /// still-tearing-down duplicate from the first presentation could in
    /// principle satisfy `.exists` without being the live, on-screen button.
    @MainActor
    static func assertClearCacheCancelAndFailureToast(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let row = app.buttons[clearCacheRowID]
        scrollUntilVisible(row, in: app)
        XCTAssertTrue(
            row.waitForExistence(timeout: 10),
            "N19: Settings Storage clear-cache row should be present",
            file: file, line: line
        )
        // #956: wait for the cache-state-ready anchor BEFORE tapping the
        // row — closes the race where `clearCache()`'s `resumeCandidate`
        // precondition hasn't loaded yet, which used to make it silently
        // take the success branch instead of the failure one this test
        // expects. 15s (not 10s) matches this file's own ceiling for "an
        // app-level async load has settled" waits (e.g. `gcRow`/`home`/
        // `removeAds` above) — this repo's dev machine routinely runs many
        // concurrent Claude Code agent sessions, so a trivial async fetch
        // can still queue behind real CPU contention.
        XCTAssertTrue(
            app.descendants(matching: .any)[clearCacheStateReadyID].waitForExistence(timeout: 15),
            "N19: SettingsViewModel.isCacheStateReady should settle before interacting with Clear cache",
            file: file, line: line
        )
        row.tap()

        // #935 batch 5: `.matching(identifier:).firstMatch` (not the plain
        // `app.buttons[id]` subscript) — a transient duplicate can briefly
        // coexist with the popover's own dismiss animation between the
        // Cancel tap below and this dialog's reopen, and `app.buttons[id]`
        // hard-fails ("Multiple matching elements found") rather than just
        // picking one; both duplicates are the same button either way.
        var confirm = app.buttons.matching(identifier: clearCacheConfirmID).firstMatch
        XCTAssertTrue(
            confirm.waitForExistence(timeout: 10),
            "N19: clear-cache confirmation dialog should present the destructive confirm action",
            file: file, line: line
        )
        waitUntilHittable(
            confirm, timeout: 5, context: "N19: clear-cache confirm button",
            file: file, line: line
        )

        // Cancel: tap the popover's own dismiss-backdrop element (#956 —
        // see doc comment above), not a raw coordinate.
        let dismissRegion = app.descendants(matching: .any)[popoverDismissRegionID]
        XCTAssertTrue(
            dismissRegion.waitForExistence(timeout: 5),
            "N19: the confirmation dialog's dismiss backdrop should be present",
            file: file, line: line
        )
        dismissRegion.tap()
        XCTAssertTrue(
            confirm.waitForNonExistence(timeout: 5),
            "N19: tapping the dialog backdrop should dismiss it (Cancel)",
            file: file, line: line
        )
        XCTAssertFalse(
            app.descendants(matching: .any)[monetizationToastFailureID].exists,
            "N19: Cancel must never raise a toast",
            file: file, line: line
        )
        XCTAssertTrue(
            row.exists,
            "N19: should remain on Settings after Cancel — no navigation",
            file: file, line: line
        )

        row.tap()
        // #956: re-query for a FRESH confirm handle rather than reusing the
        // pre-Cancel one (see doc comment above) — repro'd 7/16 concurrent
        // runs silently swallowing the confirm tap otherwise.
        confirm = app.buttons.matching(identifier: clearCacheConfirmID).firstMatch
        XCTAssertTrue(
            confirm.waitForExistence(timeout: 10),
            "N19: clear-cache confirmation dialog should present the destructive confirm action (reopen)",
            file: file, line: line
        )
        waitUntilHittable(
            confirm, timeout: 5, context: "N19: clear-cache confirm button (reopen)",
            file: file, line: line
        )
        confirm.tap()

        let failureToast = app.descendants(matching: .any)[monetizationToastFailureID]
        XCTAssertTrue(
            failureToast.waitForExistence(timeout: 10),
            "N19: a throwing deleteAbandoned should raise the failure toast under -uitest-clear-cache-fail",
            file: file, line: line
        )
        XCTAssertTrue(
            row.exists,
            "N19: should remain on Settings after the failure toast — no navigation",
            file: file, line: line
        )
    }

    /// #956: polls until `element` is not just present in the accessibility
    /// tree but `isHittable` — a dialog's presentation transition (or a
    /// not-yet-torn-down duplicate from a just-dismissed one) can satisfy
    /// `.exists` before/without ever being the genuinely interactive,
    /// on-screen element. Uses `XCTNSPredicateExpectation` + `XCTWaiter` —
    /// Apple's documented pattern for waiting on an XCUIElement property
    /// beyond mere existence — rather than a hand-rolled sleep/poll loop.
    @MainActor
    private static func waitUntilHittable(
        _ element: XCUIElement,
        timeout: TimeInterval,
        context: String,
        file: StaticString,
        line: UInt
    ) {
        let predicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(
            result, .completed,
            "\(context) should become hittable (finish presenting) before interacting with it",
            file: file, line: line
        )
    }

    /// Swipes up on `app` until `element` appears in the accessibility tree
    /// (bounded) — `SETTINGS`'s long `Form` lazily materializes off-screen
    /// rows (#935 batch 5 N19: the "Storage" section sits below
    /// Purchases/GC/Reminders/Sound/About/Notices).
    @MainActor
    private static func scrollUntilVisible(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 6
    ) {
        var attempts = 0
        while !element.exists, attempts < maxSwipes {
            app.swipeUp()
            attempts += 1
        }
    }
}
