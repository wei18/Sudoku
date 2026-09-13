// BoardFullBleedBreakpointTests — #1022: what the board actually measures at
// each of design.md §3.4's three cell-size breakpoints.
//
// Two of the three are full-bleed. The SE case is NOT, and is named for what it
// is (`heightBound_iPhoneSE_320`) rather than filed under a claim it disproves
// — a test named `fullBleed_…` whose own subject is height-bound is the kind of
// contradiction §3.4 itself just had to be corrected for.
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
            adFreeBoard(try makeViewModel()),
            size: CGSize(width: width, height: height),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: named, testName: testName)
        }
    }

    /// iPhone SE (3rd gen) — §3.4's narrowest row, and the one the board does
    /// NOT reach. Removing the horizontal inset buys nothing here: header +
    /// cluster + margins leave ~235pt of vertical room, so the square is bound
    /// by HEIGHT and measures 26.1pt per cell — under §3.4's own 28pt absolute
    /// floor, and nowhere near the table's 35.1pt. This baseline exists to pin
    /// that honestly rather than to demonstrate full-bleed; the fix is a
    /// shorter cluster variant for short screens, #1055. See §3.4 as corrected
    /// in this PR for why the table's SE figure was never reachable (it assumes
    /// a width-binding that has not held on that device since before #1022).
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func heightBound_iPhoneSE_320() throws {
        try assertFullBleed(width: 320, height: 568, named: "Board-320-heightBound")
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
