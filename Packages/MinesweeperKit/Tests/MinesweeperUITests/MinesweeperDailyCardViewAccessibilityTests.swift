// MinesweeperDailyCardViewAccessibilityTests — #886 composed VoiceOver
// label. Mirrors SudokuKit's `DailyPuzzleCardAccessibilityTests`.
//
// `MinesweeperDailyCardView` switched from
// `.accessibilityElement(children: .combine)` to an explicit composed
// `.accessibilityLabel`, mirroring `MinesweeperStatsTileView`. These tests
// pin `MinesweeperDailyCardView.accessibilityDescription(...)` (a
// `static func`, no `@Environment` context needed) directly, independent of
// visual snapshot rendering — including the MS-only `isFailed` third state.

import Foundation
import Testing
@testable import MinesweeperUI

import MinesweeperEngine

@Suite("MinesweeperDailyCardView — accessibility label (#886)")
struct MinesweeperDailyCardViewAccessibilityTests {

    @Test func completedWithBestTimeIncludesAllThreeClauses() {
        let label = MinesweeperDailyCardView.accessibilityDescription(
            difficulty: .beginner,
            isCompleted: true,
            isFailed: false,
            bestTimeSeconds: 65
        )
        #expect(label == "Beginner, Completed, best time 1 minute, 5 seconds")
    }

    @Test func failedIncludesFailedClauseNotCompleted() {
        let label = MinesweeperDailyCardView.accessibilityDescription(
            difficulty: .expert,
            isCompleted: false,
            isFailed: true,
            bestTimeSeconds: 600
        )
        #expect(label == "Expert, Failed, best time 10 minutes")
        #expect(!label.contains("Completed"))
    }

    @Test func notCompletedWithPriorBestOmitsCompletedAndFailedClauses() {
        let label = MinesweeperDailyCardView.accessibilityDescription(
            difficulty: .intermediate,
            isCompleted: false,
            isFailed: false,
            bestTimeSeconds: 240
        )
        #expect(label == "Intermediate, best time 4 minutes")
        #expect(!label.contains("Completed"))
        #expect(!label.contains("Failed"))
    }

    @Test func neverCompletedSaysNoBestTimeYet() {
        let label = MinesweeperDailyCardView.accessibilityDescription(
            difficulty: .beginner,
            isCompleted: false,
            isFailed: false,
            bestTimeSeconds: nil
        )
        #expect(label == "Beginner, no best time yet")
    }

    /// #886: the visual caption (was the board-spec text, `.accessibilityHidden(true)`)
    /// is no longer hidden — this suite existing at all (and asserting the
    /// "best time"/"no best time yet" clause is present) is the regression
    /// guard: pre-#886 the second line contributed nothing to VoiceOver.
    @Test func bestTimeClauseAlwaysPresentEitherForm() {
        let withBest = MinesweeperDailyCardView.accessibilityDescription(
            difficulty: .beginner, isCompleted: true, isFailed: false, bestTimeSeconds: 61
        )
        let withoutBest = MinesweeperDailyCardView.accessibilityDescription(
            difficulty: .beginner, isCompleted: true, isFailed: false, bestTimeSeconds: nil
        )
        #expect(withBest.contains("best time"))
        #expect(withoutBest.contains("no best time yet"))
    }
}
