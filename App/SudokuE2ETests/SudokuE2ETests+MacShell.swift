import XCTest
#if os(macOS)
import AppKit
#endif

// #1020 carried condition (#1019 → #1020): before merging the sidebarAdaptable
// shell rewrite, verify the #763 guarantee NATIVELY on macOS via the XCUITest
// coordinate-click pattern — idb cannot drive AppKit, so the sim-driven
// negative-flow suite (App/UITestsShared) proves nothing here.
//
// The macOS shape (RootShellView.swift, BoardModalOverlayHoist.swift): a
// board is a `NavigationStack` push inside the selected tab, and its
// Pause/Completion overlay is hoisted out to a ZStack sibling of the
// `TabView`, where its full-screen scrim + `.isModal` trait are what lock the
// shell (no `.disabled()` on the TabView — toggling one unmounts the pushed
// board on macOS, the regression this test caught). This file pins three
// observable behaviors while a pause overlay is up:
//   (a) the sidebar/tab rows (Today/Practice/Progress) do not switch tabs
//       when clicked — `.isModal` on the overlay can drop them from the a11y
//       tree entirely, or they can report `isEnabled == false`, or a click
//       can simply have no navigation effect. All three satisfy the
//       guarantee, so this test tolerates any of them.
//   (b) the overlay's OWN Resume button still works — dismisses the overlay,
//       board stays.
//   (c) Leave pops back to the tab root (Practice hub).
//
// Reaching a pushed board on macOS: the iOS-only DEBUG launch hooks
// (`-uitest-near-win-modal`, `-uitest-route`) are inert no-ops on macOS
// (`UITestRouteModifier.body` is `#if os(iOS)`; the near-win modifiers gate
// the same way — see SudokuAppComposition.swift). So this test navigates for
// real: launch → click the Practice tab/sidebar row → click the Practice
// hub's "New Game" CTA (`sudoku.practiceHub.start`) → wait for the board
// (`sudoku.board.pauseToggle`) → click pause.
//
// Coordinate-click pattern (repo memory `macos-xcuitest-coordinate-clicks`,
// verified 2026-07-04): `element.tap()` on SwiftUI-on-Mac throws
// `point.x != INFINITY`; `app.coordinate(withNormalizedOffset:)` resolves to
// `(-inf, -inf)`. Element FRAMES are finite, so every click here is anchored
// on the window's own coordinate space.
#if os(macOS)
@MainActor
extension SudokuE2ETests {

    /// #1019/#1020: the #763 shell-lock guarantee, verified natively on macOS.
    func test_pauseOverlayLocksShellOnMac_1019() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 15),
            "Sudoku app should reach the foreground after launch"
        )

        // #1019 triage: `app.windows.firstMatch` is a LIVE query re-evaluated
        // on every access. During a NavigationStack push transition macOS
        // briefly surfaces a second, unidentified "ghost" window (no
        // `identifier`, origin offset from the real one — captured via
        // `debugDescription` while diagnosing this test). If `firstMatch`
        // happens to resolve to that ghost mid-tap, the coordinate math below
        // computes an offset from the WRONG origin and the click misses its
        // target entirely. The real content window carries a stable
        // identifier ending in `-1-AppWindow-1` (SwiftUI's generated window
        // id) that the ghost never has, so pin to that instead of `firstMatch`.
        let window = app.windows.matching(NSPredicate(format: "identifier CONTAINS[c] %@", "AppWindow")).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15), "app window should exist")

        // MARK: navigate to a pushed board (Practice tab → New Game → board)

        let practiceRow = Self.tabRow(labeled: "Practice", in: app)
        XCTAssertTrue(
            practiceRow.waitForExistence(timeout: 15),
            "Practice tab/sidebar row should be present before the overlay is ever up.\n\(app.debugDescription)"
        )
        Self.click(practiceRow.frame, in: app, window: window)

        let startCTA = app.buttons["sudoku.practiceHub.start"]
        XCTAssertTrue(
            startCTA.waitForExistence(timeout: 15),
            "Practice hub 'New Game' CTA should appear after selecting the Practice tab.\n\(app.debugDescription)"
        )
        Self.click(startCTA.frame, in: app, window: window)

        let pauseToggle = app.buttons["sudoku.board.pauseToggle"]
        XCTAssertTrue(
            pauseToggle.waitForExistence(timeout: 30),
            "board (sudoku.board.pauseToggle) should appear after New Game.\n\(app.debugDescription)"
        )

        // MARK: open the pause overlay

        Self.click(pauseToggle.frame, in: app, window: window)

        let resume = app.buttons["game.pause.resume"]
        XCTAssertTrue(
            resume.waitForExistence(timeout: 10),
            "pause overlay (game.pause.resume) should present after tapping the pause toggle."
                + " frontmost app: \(Self.frontmostAppTitle())\n\(app.debugDescription)"
        )

        print("=== #1019 shell state WHILE pause overlay is up ===")
        print(app.debugDescription)
        Self.attachScreenshot(named: "overlay-up", to: self)

        // MARK: (a) sidebar/tab rows must not switch tabs while the overlay is up

        for label in ["Today", "Practice", "Progress"] {
            Self.assertTabRowInertWhileOverlayUp(
                labeled: label,
                app: app,
                window: window,
                pauseToggle: pauseToggle,
                resume: resume
            )
        }
        Self.attachScreenshot(named: "after-sidebar-clicks", to: self)

        // MARK: (b) Resume still works — dismisses the overlay, board stays

        Self.click(resume.frame, in: app, window: window)
        XCTAssertTrue(
            resume.waitForNonExistence(timeout: 5),
            "Resume should dismiss the pause overlay"
        )
        XCTAssertTrue(
            pauseToggle.waitForExistence(timeout: 5),
            "board should remain present after Resume — resumed in place, no navigation"
        )
        Self.attachScreenshot(named: "after-resume", to: self)

        // MARK: (c) Leave pops back to the Practice hub root

        Self.click(pauseToggle.frame, in: app, window: window)
        let leave = app.buttons["game.pause.leave"]
        XCTAssertTrue(
            leave.waitForExistence(timeout: 10),
            "pause overlay should present Leave on the second pause"
        )
        Self.click(leave.frame, in: app, window: window)

        XCTAssertTrue(
            startCTA.waitForExistence(timeout: 15),
            "Leave should pop back to the Practice hub ('New Game' CTA visible again)"
        )
        XCTAssertTrue(
            pauseToggle.waitForNonExistence(timeout: 5),
            "board (sudoku.board.pauseToggle) should be gone after Leave"
        )
    }

    // MARK: - Helpers

    /// Locates a tab/sidebar row by its title text. `sidebarAdaptable` renders
    /// `Tab(tab.titleKey, …)` items whose title text appears on macOS as an
    /// `Outline` `Cell`'s `StaticText` child — verified via a captured
    /// `debugDescription` dump (`SudokuE2ETests+MacShell.swift` evidence,
    /// #1019/#1020): that `StaticText` reports the title through AXValue, not
    /// AXLabel (`StaticText, …, value: Practice`, `label` empty), so matching
    /// on `label` alone (the pre-fix bug) never found it. There is no
    /// dedicated a11y identifier on `AppTab`, so this matches on EITHER
    /// `label` or `value` across every element kind — covers both this macOS
    /// sidebar rendering and any iPad/iOS tab-bar rendering that might expose
    /// the title via `label` instead.
    private static func tabRow(labeled label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR value == %@", label, label))
            .firstMatch
    }

    /// (a): while the pause overlay is up, a tab row must satisfy ONE of —
    /// absent from the a11y tree (`.isModal`), reported `isEnabled == false`,
    /// or a click that has no navigation effect (board + overlay unchanged).
    @MainActor
    private static func assertTabRowInertWhileOverlayUp(
        labeled label: String,
        app: XCUIApplication,
        window: XCUIElement,
        pauseToggle: XCUIElement,
        resume: XCUIElement
    ) {
        let row = tabRow(labeled: label, in: app)
        guard row.exists else {
            // Absent from the tree under `.isModal` — the guarantee holds.
            return
        }
        if !row.isEnabled {
            // Reported disabled — the guarantee holds.
            return
        }
        // Element exists and reports enabled: click it and prove it had no
        // navigational effect — the board + its own overlay must remain.
        click(row.frame, in: app, window: window)
        XCTAssertTrue(
            resume.exists,
            "clicking the '\(label)' tab row while the pause overlay is up must not"
                + " dismiss/navigate past it (#763).\n\(app.debugDescription)"
        )
        XCTAssertTrue(
            pauseToggle.exists,
            "clicking the '\(label)' tab row while the pause overlay is up must leave"
                + " the board in place (#763)."
        )
    }

    /// Coordinate-click pattern for SwiftUI-on-Mac (`element.tap()` throws
    /// `point.x != INFINITY`; `app.coordinate(withNormalizedOffset:)` resolves
    /// to `(-inf, -inf)`). Element FRAMES are finite, so anchor on the window.
    ///
    /// This machine runs many concurrent agent sessions with their own
    /// windows, so the app can lose key-window / frontmost status between
    /// steps. `app.activate()` re-raises it immediately before every
    /// synthesized click — cheap and idempotent when it is already frontmost.
    private static func click(_ rect: CGRect, in app: XCUIApplication, window: XCUIElement) {
        app.activate()
        let origin = window.frame.origin
        window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: rect.midX - origin.x, dy: rect.midY - origin.y))
            .tap()
    }

    /// Diagnostic only (assertion-failure messages): which app NSWorkspace
    /// currently reports as frontmost, to distinguish "the click landed on
    /// the wrong window" (shared-desktop focus contention) from a real
    /// regression in the app's own overlay logic.
    private static func frontmostAppTitle() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "<none>"
    }

    /// The runner sandbox can't write `/tmp`; screenshots are attached to the
    /// test report instead and exported afterward via `xcresulttool`.
    private static func attachScreenshot(named name: String, to testCase: XCTestCase) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }
}
#endif
