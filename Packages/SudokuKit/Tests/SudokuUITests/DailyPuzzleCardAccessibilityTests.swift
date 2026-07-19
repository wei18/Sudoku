// DailyPuzzleCardAccessibilityTests — #886 composed VoiceOver label.
//
// `DailyPuzzleCard` switched from `.accessibilityElement(children: .combine)`
// to an explicit composed `.accessibilityLabel`, mirroring `StatsTileView`.
// These tests pin `DailyPuzzleCard.accessibilityDescription(...)` (a
// `static func`, not read off a live `View` instance — no `@Environment`
// context needed) directly, independent of visual snapshot rendering.

import Foundation
import Testing
@testable import SudokuUI

import SudokuEngine

@Suite("DailyPuzzleCard — accessibility label (#886)")
struct DailyPuzzleCardAccessibilityTests {

    @Test func completedWithBestTimeIncludesAllThreeClauses() {
        let label = DailyPuzzleCard.accessibilityDescription(
            difficulty: .easy,
            isCompleted: true,
            bestTimeSeconds: 192
        )
        #expect(label == "Easy, Completed, best time 3 minutes, 12 seconds")
    }

    @Test func notCompletedWithPriorBestOmitsCompletedClause() {
        let label = DailyPuzzleCard.accessibilityDescription(
            difficulty: .hard,
            isCompleted: false,
            bestTimeSeconds: 303
        )
        #expect(label == "Hard, best time 5 minutes, 3 seconds")
        #expect(!label.contains("Completed"))
    }

    @Test func neverCompletedSaysNoBestTimeYet() {
        let label = DailyPuzzleCard.accessibilityDescription(
            difficulty: .medium,
            isCompleted: false,
            bestTimeSeconds: nil
        )
        #expect(label == "Medium, no best time yet")
    }

    /// #886: the visual caption is `.caption`/theme.text.secondary text, no
    /// longer `.accessibilityHidden(true)` — this suite existing at all (and
    /// asserting the "best time"/"no best time yet" clause is present) is
    /// the regression guard for that: pre-#886 the second line contributed
    /// nothing to VoiceOver.
    @Test func bestTimeClauseAlwaysPresentEitherForm() {
        let withBest = DailyPuzzleCard.accessibilityDescription(difficulty: .easy, isCompleted: true, bestTimeSeconds: 61)
        let withoutBest = DailyPuzzleCard.accessibilityDescription(difficulty: .easy, isCompleted: true, bestTimeSeconds: nil)
        #expect(withBest.contains("best time"))
        #expect(withoutBest.contains("no best time yet"))
    }
}
