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
