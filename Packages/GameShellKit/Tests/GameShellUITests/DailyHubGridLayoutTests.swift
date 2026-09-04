import SwiftUI
import Testing
@testable import GameShellUI

// MARK: - DailyHubGridLayout.columnCount(sizeClass:dynamicTypeSize:)
//
// #1021 Phase G: `DailyHubShellView`'s 1-or-3-column grid rule, hoisted into
// this standalone helper so `DailyHubView` (Sudoku) and
// `MinesweeperDailyHubView`'s `loading:` skeleton grids call the SAME rule
// instead of re-deriving it (the pre-Phase-G drift risk this pins against).
// An accessibility Dynamic Type size (AX1–AX5, `.isAccessibilitySize`)
// forces a single column REGARDLESS of size class — at AX3 on a regular
// iPad width, 3 ~262pt columns wrapped every status word onto its own line
// and hyphenated (design.md §5.6/§7 forbids that even though nothing was
// clipped).
@Suite("GameShellUI — DailyHubGridLayout.columnCount")
struct DailyHubGridLayoutTests {

    @Test func compactSizeClassNormalTypeIsOneColumn() {
        #expect(DailyHubGridLayout.columnCount(sizeClass: .compact, dynamicTypeSize: .large) == 1)
    }

    @Test func regularSizeClassNormalTypeIsThreeColumns() {
        #expect(DailyHubGridLayout.columnCount(sizeClass: .regular, dynamicTypeSize: .large) == 3)
    }

    @Test func compactSizeClassAccessibilityTypeIsOneColumn() {
        #expect(DailyHubGridLayout.columnCount(sizeClass: .compact, dynamicTypeSize: .accessibility3) == 1)
    }

    // The G1 fix: a regular size class alone used to be sufficient for 3
    // columns — an accessibility Dynamic Type size must now override that
    // and force a single column even on iPad-width regular layouts.
    @Test func regularSizeClassAccessibilityTypeIsOneColumn() {
        #expect(DailyHubGridLayout.columnCount(sizeClass: .regular, dynamicTypeSize: .accessibility3) == 1)
    }

    @Test func regularSizeClassEveryAccessibilityStepIsOneColumn() {
        for step in [DynamicTypeSize.accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5] {
            #expect(DailyHubGridLayout.columnCount(sizeClass: .regular, dynamicTypeSize: step) == 1)
        }
    }

    @Test func nilSizeClassNormalTypeIsOneColumn() {
        #expect(DailyHubGridLayout.columnCount(sizeClass: nil, dynamicTypeSize: .large) == 1)
    }

    @Test func nilSizeClassAccessibilityTypeIsOneColumn() {
        #expect(DailyHubGridLayout.columnCount(sizeClass: nil, dynamicTypeSize: .accessibility3) == 1)
    }

    // The largest non-accessibility step (xxxLarge) must still route through
    // the ordinary size-class rule — `isAccessibilitySize` is false for it.
    @Test func regularSizeClassLargestStandardTypeIsThreeColumns() {
        #expect(DailyHubGridLayout.columnCount(sizeClass: .regular, dynamicTypeSize: .xxxLarge) == 3)
    }
}
