import SwiftUI
import Testing
@testable import GameShellUI

// MARK: - CompletionStreakAdvance (#1023 Phase B)
//
// Pins the pre→post pip/count math as a pure value, independent of any
// rendered view — `CompletionStreakView` consumes `pipStates`/`prePipStates`/
// `todayAdvanced` directly, so asserting on the value type covers the M3/M4
// state machine without a render tree. Mirrors `CompletionMotionPlanTests`'s
// shape (design.md §6 rows M1/M2/M3/M4/M10's sibling test file).

@Suite("GameShellUI — CompletionStreakAdvance (#1023 Phase B)")
struct CompletionStreakAdvanceTests {

    // MARK: - todayAdvanced

    @Test func todayAdvancedWhenCountsDiffer() {
        let advance = CompletionStreakAdvance(pipStates: [false, true, true, true, true, true, true], preCount: 5, postCount: 6)
        #expect(advance.todayAdvanced)
    }

    @Test func notAdvancedWhenCountsAreEqual() {
        // Player already completed a different difficulty earlier today —
        // today's pip was already filled before this solve, so pre == post.
        let advance = CompletionStreakAdvance(pipStates: [true, true, true, true, true, true, true], preCount: 6, postCount: 6)
        #expect(!advance.todayAdvanced)
    }

    // MARK: - prePipStates: only today's (last) slot ever differs

    @Test func prePipStatesFlipsOnlyTheLastSlotWhenAdvanced() {
        let post: [Bool] = [false, false, true, true, true, true, true]
        let advance = CompletionStreakAdvance(pipStates: post, preCount: 4, postCount: 5)
        #expect(advance.prePipStates == [false, false, true, true, true, true, false])
    }

    @Test func prePipStatesEqualsPipStatesWhenNotAdvanced() {
        let post: [Bool] = [true, true, true, true, true, true, true]
        let advance = CompletionStreakAdvance(pipStates: post, preCount: 7, postCount: 7)
        #expect(advance.prePipStates == post)
    }

    @Test func prePipStatesHandlesEmptyArraySafely() {
        let advance = CompletionStreakAdvance(pipStates: [], preCount: 0, postCount: 1)
        #expect(advance.prePipStates == [])
    }

    // MARK: - showsStreakSection: the ritual's own gate (design.md §3.5)

    @Test func showsSectionForLiveSolveDailyMoreTodaySuccessWithAdvance() {
        let advance = CompletionStreakAdvance(pipStates: [true], preCount: 0, postCount: 1)
        #expect(CompletionStreakAdvance.showsStreakSection(
            variant: .liveSolve,
            outcomeKind: .success,
            context: .dailyMoreToday(nextDifficultyLabel: "Medium", onNext: {}),
            advance: advance
        ))
    }

    @Test func showsSectionForLiveSolveDailyAllDoneSuccessWithAdvance() {
        let advance = CompletionStreakAdvance(pipStates: [true], preCount: 0, postCount: 1)
        #expect(CompletionStreakAdvance.showsStreakSection(
            variant: .liveSolve,
            outcomeKind: .success,
            context: .dailyAllDone,
            advance: advance
        ))
    }

    @Test func hidesSectionWhenNoProviderResolved() {
        #expect(!CompletionStreakAdvance.showsStreakSection(
            variant: .liveSolve,
            outcomeKind: .success,
            context: .dailyAllDone,
            advance: nil
        ))
    }

    @Test func hidesSectionForReviewVariant() {
        let advance = CompletionStreakAdvance(pipStates: [true], preCount: 0, postCount: 1)
        #expect(!CompletionStreakAdvance.showsStreakSection(
            variant: .review,
            outcomeKind: .success,
            context: .dailyAllDone,
            advance: advance
        ))
    }

    @Test func hidesSectionForPracticeContext() {
        let advance = CompletionStreakAdvance(pipStates: [true], preCount: 0, postCount: 1)
        #expect(!CompletionStreakAdvance.showsStreakSection(
            variant: .liveSolve,
            outcomeKind: .success,
            context: .practice(onPlayAgain: nil),
            advance: advance
        ))
    }

    @Test func hidesSectionForLossContext() {
        let advance = CompletionStreakAdvance(pipStates: [true], preCount: 0, postCount: 1)
        #expect(!CompletionStreakAdvance.showsStreakSection(
            variant: .liveSolve,
            outcomeKind: .failure,
            context: .loss(onTryAgain: nil),
            advance: advance
        ))
    }

    @Test func hidesSectionForFailureOutcomeEvenOnDailyContext() {
        // Defensive: Sudoku is solve-only so this combination is unreachable
        // in production, but the gate must still hold if it ever occurred.
        let advance = CompletionStreakAdvance(pipStates: [true], preCount: 0, postCount: 1)
        #expect(!CompletionStreakAdvance.showsStreakSection(
            variant: .liveSolve,
            outcomeKind: .failure,
            context: .dailyAllDone,
            advance: advance
        ))
    }
}
