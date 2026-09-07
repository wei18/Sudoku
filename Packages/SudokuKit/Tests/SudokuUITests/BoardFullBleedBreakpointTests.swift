// BoardFullBleedBreakpointTests — #1022: the board renders full-bleed at each
// of design.md §3.4's three cell-size breakpoints.
//
// §3.4's table quotes one cell side per device width, and the existing
// `BoardViewTests` matrix only ever renders the middle one (393pt). These three
// pin the other two so a future inset creeping back in is caught at the widths
// the table is actually about, not just at iPhone 15/17 Pro.
//
// What these baselines DO and DO NOT show. They show the grid running edge to
// edge with no horizontal inset, which is the thing #1022 changed. They do NOT
// show the G4 cluster's glass: Liquid Glass renders as nothing in this
// NSHostingView capture path (standard materials and `.bordered` render fine —
// measured both ways, see #1022's PR body and #1054), so the cluster's controls
// appear as bare glyphs. That is the renderer's blind spot, not missing
// controls. The two glass groups are proven structurally by
// `BoardControlClusterLayoutTests` and visually by the simulator sweep on the
// PR, which is the only faithful compositor for this material.

#if canImport(AppKit)
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import SudokuUI

import SudokuEngine
import SudokuGameState
import SudokuPersistence

@MainActor
@Suite("BoardView — full-bleed at §3.4's three cell-size breakpoints (#1022)")
struct BoardFullBleedBreakpointTests {

    private static let inProgressClues =
        "53..7...." +
        "6..195..." +
        ".98....6." +
        "8...6...3" +
        "4..8.3..1" +
        "7...2...6" +
        ".6....28." +
        "...419..5" +
        "....8..79"

    private func makeViewModel() throws -> GameViewModel {
        GameViewModel(
            identity: PuzzleIdentity(puzzleId: "test-easy", kind: .practice, difficulty: .easy),
            board: try Board(clues: Self.inProgressClues),
            status: .playing,
            elapsedSeconds: 201,
            errorIndices: [],
            selection: nil,
            canUndo: false
        )
    }

    // `testName` is forwarded so each baseline is filed under the TEST's name
    // rather than this helper's — otherwise all three land under
    // `assertFullBleed-width-height-named.*`, which reads as one recording and
    // breaks the baseline↔`@Test` correspondence `scan:store_baseline_orphans`
    // relies on.
    private func assertFullBleed(
        width: CGFloat,
        height: CGFloat,
        named: String,
        testName: String = #function
    ) throws {
        let host = hostingView(
            BoardView(viewModel: try makeViewModel()),
            size: CGSize(width: width, height: height),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: named, testName: testName)
        }
    }

    /// iPhone SE (3rd gen) — §3.4's narrowest row. Table figure 35.1pt; the
    /// real full-bleed side is 320 / 9 = 35.6pt (the table deducts a 4pt outer
    /// frame this board does not have — see the PR body).
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func fullBleed_iPhoneSE_320() throws {
        try assertFullBleed(width: 320, height: 568, named: "Board-320-fullBleed")
    }

    /// iPhone 15 / 17 Pro — the width every other board baseline uses.
    /// Table 43.2pt; real 393 / 9 = 43.7pt.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func fullBleed_iPhonePro_393() throws {
        try assertFullBleed(width: 393, height: 852, named: "Board-393-fullBleed")
    }

    /// iPhone Pro Max — §3.4's widest row, and the first size class to clear
    /// the HIG 44pt default. Table 47.3pt; real 430 / 9 = 47.8pt.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func fullBleed_iPhoneProMax_430() throws {
        try assertFullBleed(width: 430, height: 932, named: "Board-430-fullBleed")
    }
}
#endif
