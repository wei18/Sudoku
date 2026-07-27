import XCTest

// #950 — Restore Purchases with nothing entitled (N23 follow-up). Split out
// of `NegativeNavigationE2ESupport.swift` to keep that file under the
// 400-line SwiftLint ceiling (same pattern as `SudokuE2ETests+MonetizationFlows`
// — Tuist's shared-target source glob picks this file up automatically).
extension NegativeNavigationE2ESupport {
    /// Settings "Restore Purchases" row (`RestorePurchasesRow`, #950).
    static let restorePurchasesRowID = "settings.iap.restore"

    /// Info-style toast id (`Toast.Style.info`, #950).
    static let monetizationToastInfoID = "monetization.toast.info"

    /// #950 (N23 follow-up): caller already routed to Settings with
    /// `-uitest-iap-script` set — `UITestScriptedIAPClient.restorePurchases()`
    /// always returns `[]` (nothing entitled), so tapping "Restore Purchases"
    /// must raise the informational "No purchases to restore" toast, never
    /// the false "Purchases restored" success claim `MonetizationStateController`
    /// used to show unconditionally.
    @MainActor
    static func assertRestoreWithNothingToRestoreShowsInfoToast(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let restore = app.buttons[restorePurchasesRowID]
        XCTAssertTrue(
            restore.waitForExistence(timeout: 15),
            "#950: Settings Restore Purchases row should be present",
            file: file, line: line
        )
        let infoToast = app.descendants(matching: .any)[monetizationToastInfoID]
        let successToast = app.descendants(matching: .any)[monetizationToastSuccessID]

        restore.tap()
        XCTAssertTrue(
            infoToast.waitForExistence(timeout: 10),
            "#950: an empty restore result should raise the info toast under -uitest-iap-script",
            file: file, line: line
        )
        XCTAssertFalse(
            successToast.exists,
            "#950: an empty restore must never show the false 'Purchases restored' success toast",
            file: file, line: line
        )
        XCTAssertTrue(restore.exists, "#950: should remain on Settings after restore", file: file, line: line)
    }
}
