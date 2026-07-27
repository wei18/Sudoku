import XCTest

// #935 batch 5 — Sudoku's ATT primer / clear-cache / IAP negative flows
// (N15/N19/N22). Split out of `SudokuE2ETests.swift` to keep that file under
// the 400-line SwiftLint ceiling (Tuist's `App/SudokuE2ETests/**/*.swift`
// source glob picks this file up automatically — same target, same scheme).
@MainActor
extension SudokuE2ETests {

    /// #935 batch 5 N15: ATT primer decline (`ATT-PRIMER`) — "Not now" must
    /// dismiss the app-owned priming sheet without firing the system ATT
    /// dialog, and the one-offer-per-launch latch must hold across a second
    /// background→foreground cycle. `-uitest-fake-ad-gate-repoll` opens the
    /// banner ad-gate (this primer's only trigger, `onAdContext`) after a
    /// real cycle; `-uitest-att-primer` forces `isNotDetermined` → true /
    /// `requestSystemPrompt` → no-op so the sheet is reachable without
    /// depending on the simulator's real (once-per-install) ATT status.
    func test_attPrimerDeclineDismissesAndLatches_N15() {
        let app = XCUIApplication()
        app.launchArguments += [
            UITestLaunchArg.fakeAdGateRepoll,
            UITestLaunchArg.attPrimer,
        ]
        app.launch()
        NegativeNavigationE2ESupport.assertATTPrimerDeclineDismissesAndLatches(in: app)
    }

    /// #935 batch 5 N19: Settings Storage "Clear cache" — Cancel is a no-op;
    /// confirming under a throwing `deleteAbandoned` (`-uitest-clear-cache-fail`)
    /// raises the failure toast instead of the false "Cache cleared" success
    /// claim (#687, fixed by ca21ca9/#690, unified into GameAppKit by #832).
    func test_clearCacheCancelAndFailureToast_N19() {
        let app = XCUIApplication()
        app.launchArguments += [
            UITestLaunchArg.clearCacheFail,
            UITestLaunchArg.route, "settings",
        ]
        app.launch()
        NegativeNavigationE2ESupport.assertClearCacheCancelAndFailureToast(in: app)
    }

    /// #935 batch 5 N22: Settings "Remove Ads" — walks all three
    /// `purchaseRemoveAds()` branches (cancel/fail/pending) via the scripted
    /// `-uitest-iap-script` fake, never the real StoreKit 2 payment sheet.
    func test_iapPurchaseCancelFailPendingStayInPlace_N22() {
        let app = XCUIApplication()
        app.launchArguments += [
            UITestLaunchArg.iapScript,
            UITestLaunchArg.route, "settings",
        ]
        app.launch()
        NegativeNavigationE2ESupport.assertIAPPurchaseCancelFailPendingStayInPlace(in: app)
    }

    /// #950 (N23 follow-up): Settings "Restore Purchases" with nothing
    /// entitled — `UITestScriptedIAPClient.restorePurchases()` always
    /// returns `[]`, so tapping Restore under `-uitest-iap-script` must
    /// raise the informational "No purchases to restore" toast, never the
    /// false "Purchases restored" success claim.
    func test_restoreWithNothingToRestoreShowsInfoNotSuccess() {
        let app = XCUIApplication()
        app.launchArguments += [
            UITestLaunchArg.iapScript,
            UITestLaunchArg.route, "settings",
        ]
        app.launch()
        NegativeNavigationE2ESupport.assertRestoreWithNothingToRestoreShowsInfoToast(in: app)
    }
}
