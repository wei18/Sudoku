import XCTest

// #931 — shared host-driven E2E drive logic for the two scenePhase re-poll
// sites, glob'd into BOTH SudokuE2ETests and MinesweeperE2ETests (mirror
// principle, matching GameE2ESupport). Each site's DEBUG-only "flip on
// background" fake (`UITestFlipOnBackgroundNotificationAuthorizing` /
// `UITestFlipOnBackgroundAdGateStateStore`, wired in
// `MakeGameApp+UITestOverrides.swift`) reports one answer until the process
// is observed entering the background, then a different one — so these
// assertions ONLY pass if a real background→foreground cycle produces a
// poll, which only the `.onChange(of: scenePhase)` hook under test can do
// (`.task` never re-fires on foreground return). Removing that hook, or
// inverting its `== .active` guard, leaves the pre-flip state forever and
// the corresponding assertion below times out.
enum ScenePhaseRepollE2ESupport {
    /// `ReminderSettingsSection`'s denied-state row (#929/#931).
    static let reminderDeniedID = "reminders.settings.denied"
    /// The not-yet-authorized enable row — one of the two rows a `.denied` →
    /// `.authorized` flip can land on (the other is `reminderDisableID`,
    /// depending on the fresh-install `isScheduled` seed).
    static let reminderEnableID = "reminders.settings.enable"
    static let reminderDisableID = "reminders.settings.disable"

    /// `BannerSlotView`'s stable slot anchor (#341/#931).
    static let bannerSlotID = "monetization.banner.slot"

    /// Reminders case: launch already routed to Settings with
    /// `-uitest-fake-reminder-repoll` set. Asserts the denied row renders at
    /// launch (the fake authorizer starts `.denied`), then that it flips to
    /// an authorized-state row ONLY after a real background→foreground cycle.
    @MainActor
    static func assertReminderScenePhaseRepoll(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let denied = app.descendants(matching: .any)[reminderDeniedID]
        XCTAssertTrue(
            denied.waitForExistence(timeout: 15),
            "reminders.settings.denied should render at launch (fake authorizer starts denied)",
            file: file, line: line
        )

        XCUIDevice.shared.press(.home)
        app.activate()

        let enable = app.descendants(matching: .any)[reminderEnableID]
        let disable = app.descendants(matching: .any)[reminderDisableID]
        let becameAuthorized = enable.waitForExistence(timeout: 15) || disable.waitForExistence(timeout: 1)
        XCTAssertTrue(
            becameAuthorized,
            "reminder row should flip off 'denied' after a real background→foreground cycle"
                + " (scenePhase re-poll) — dropping .onChange(of: scenePhase) leaves it denied forever",
            file: file, line: line
        )
        XCTAssertFalse(
            denied.exists,
            "reminders.settings.denied should no longer exist once the scenePhase repoll re-authorizes",
            file: file, line: line
        )
    }

    /// Banner case: launch already carries `-uitest-fake-ad-gate-repoll`
    /// (lands on Home, which renders `BannerSlotView`). Asserts the slot is
    /// absent at launch (the fake gate store throws until backgrounded), then
    /// that it appears ONLY after a real background→foreground cycle.
    @MainActor
    static func assertBannerScenePhaseRepoll(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let slot = app.descendants(matching: .any)[bannerSlotID]
        XCTAssertFalse(
            slot.waitForExistence(timeout: 3),
            "monetization.banner.slot should be absent at launch (fake ad-gate store throws until backgrounded)",
            file: file, line: line
        )

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            slot.waitForExistence(timeout: 15),
            "monetization.banner.slot should reappear after a real background→foreground cycle"
                + " (scenePhase re-poll) — dropping .onChange(of: scenePhase) leaves it hidden forever",
            file: file, line: line
        )
    }
}
