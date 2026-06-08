// MinesweeperNoATTGuardTests — #371 / #195 F2: Minesweeper must NEVER request ATT.
//
// APPROVED decision F2: ATT is Sudoku-only. Minesweeper keeps non-personalized
// ads and shows no ATT prompt. ATT lives entirely in the shared
// AppMonetizationKit (`ATTPresenter`); the *trigger* lives in SudokuUI
// (`ATTPrimerCoordinator`) + Sudoku's `AppComposition`. MinesweeperKit has no
// ATT code path at all.
//
// This is a structural guard: it scans every MinesweeperKit source file and
// asserts none of them reference any ATT touch point. If a future change wires
// ATT into Minesweeper (a prompt, an `ATTPresenter` call, an
// `ATTrackingManager` import, or an `ATTPrimerCoordinator`), this test fails —
// catching the regression at the source level, which is stronger than a
// runtime spy (MS has nothing to spy because the call site doesn't exist).
//
// The scan walks up from `#filePath` to the MinesweeperKit package's `Sources/`
// directory. If that directory can't be located (e.g. a distributed CI runner
// without the source tree), the test no-ops rather than failing spuriously —
// the local + PR `swift test` run is the enforcing gate.

import Foundation
import Testing

@Suite("Minesweeper — no ATT (F2: Sudoku-only ATT)")
struct MinesweeperNoATTGuardTests {

    /// ATT tokens that must never appear in MinesweeperKit sources.
    private static let forbidden = [
        "ATTrackingManager",
        "requestTrackingAuthorization",
        "ATTPresenter",
        "ATTPrimerCoordinator",
        "AppTrackingTransparency",
    ]

    @Test func minesweeperSourcesReferenceNoATT() throws {
        // #filePath = .../Packages/MinesweeperKit/Tests/MinesweeperUITests/<this file>
        // Walk up to the package root, then scan Sources/.
        let thisFile = URL(fileURLWithPath: #filePath)
        let packageRoot = thisFile
            .deletingLastPathComponent()  // MinesweeperUITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // MinesweeperKit
        let sources = packageRoot.appendingPathComponent("Sources")

        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: sources.path, isDirectory: &isDir), isDir.boolValue else {
            // Source tree not present (distributed runner). The PR `swift test`
            // run enforces this; nothing to assert here.
            return
        }

        guard let walker = fileManager.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            return
        }

        var offenders: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let contents = try String(contentsOf: url, encoding: .utf8)
            for token in Self.forbidden where contents.contains(token) {
                offenders.append("\(url.lastPathComponent): contains '\(token)'")
            }
        }

        #expect(
            offenders.isEmpty,
            "Minesweeper must never request ATT (F2). Offending references: \(offenders)"
        )
    }
}
