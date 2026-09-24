// SudokuUITestRouteTests — coverage for `SudokuAppComposition.uitestRoute(for:)`,
// the DEBUG-only `-uitest-route` key resolver (#510 / #1020 / #1054). No
// prior test covered this resolver directly (unlike Minesweeper's
// `MinesweeperAppCompositionTests`); this fills that gap and adds the new
// #1054 `board:showcase` key.

import Testing
@testable import SudokuAppComposition
import GameAppKit
import SudokuUI

#if DEBUG

@MainActor
@Suite("SudokuAppComposition.uitestRoute(for:)")
struct SudokuUITestRouteTests {

    @Test func dailyResolvesToTodayTab() {
        #expect(SudokuAppComposition.uitestRoute(for: "daily") == .tab(.today))
    }

    @Test func practiceResolvesToPracticeTab() {
        #expect(SudokuAppComposition.uitestRoute(for: "practice") == .tab(.practice))
    }

    @Test func settingsResolvesToSettingsPush() {
        #expect(SudokuAppComposition.uitestRoute(for: "settings") == .push(.settings, tab: .today))
    }

    // #1054: the fixed showcase board — pushed onto the Practice tab, same
    // shape a real Start tap from Practice would produce.
    @Test func boardShowcaseResolvesToFixedShowcaseBoard() {
        #expect(
            SudokuAppComposition.uitestRoute(for: "board:showcase")
                == .push(.board(puzzleId: SudokuShowcaseBoard.puzzleId), tab: .practice)
        )
    }

    @Test func unknownKeyResolvesToNil() {
        #expect(SudokuAppComposition.uitestRoute(for: "bogus") == nil)
        #expect(SudokuAppComposition.uitestRoute(for: "board:showcase ") == nil)
        #expect(SudokuAppComposition.uitestRoute(for: "") == nil)
    }
}

#endif
