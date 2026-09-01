import Testing
@testable import GameShellUI

// MARK: - CompletionMotionPlan (#1023)
//
// Pins design.md §6 rows M1/M2/M3/M4/M10 as a pure value, independent of any
// rendered view — `CompletionOverlayScaffold`/`CompletionScreen` both consume
// `CompletionMotionPlan.plan(...)`, so asserting on the plan directly covers
// every call site without a render tree.

@Suite("GameShellUI — CompletionMotionPlan (#1023)")
struct CompletionMotionPlanTests {

    // MARK: - liveSolve default forms (§6 timings)

    @Test func liveSolveSuccessDefaultForms() {
        let plan = CompletionMotionPlan.plan(variant: .liveSolve, outcomeKind: .success, reduceMotion: false)
        #expect(plan.accentSeep == .seep(duration: 0.6))
        #expect(plan.heroReveal == .riseAndFade(duration: 0.35, rise: 8, stagger: 0.06))
        #expect(plan.streakPip == .fillAndScale(duration: 0.35, peakScale: 1.12))
        #expect(plan.streakCounter == .slideReplace(duration: 0.3))
        #expect(plan.panelRise == .rise(duration: 0.45, glowDuration: 0.6))
    }

    // MARK: - 5 explicit Reduce-Motion fallback assertions (one per M row)

    @Test func reduceMotion_M1_accentSeepFallsBackToCrossfade() {
        let plan = CompletionMotionPlan.plan(variant: .liveSolve, outcomeKind: .success, reduceMotion: true)
        #expect(plan.accentSeep == .crossfade(duration: 0.25))
    }

    @Test func reduceMotion_M2_heroRevealFallsBackToFadeOnly() {
        let plan = CompletionMotionPlan.plan(variant: .liveSolve, outcomeKind: .success, reduceMotion: true)
        #expect(plan.heroReveal == .fadeOnly(duration: 0.35, stagger: 0.06))
    }

    @Test func reduceMotion_M3_streakPipFallsBackToFillOnly() {
        let plan = CompletionMotionPlan.plan(variant: .liveSolve, outcomeKind: .success, reduceMotion: true)
        #expect(plan.streakPip == .fillOnly(duration: 0.35))
    }

    @Test func reduceMotion_M4_streakCounterFallsBackToCrossfade() {
        let plan = CompletionMotionPlan.plan(variant: .liveSolve, outcomeKind: .success, reduceMotion: true)
        #expect(plan.streakCounter == .crossfade(duration: 0.3))
    }

    @Test func reduceMotion_M10_panelRiseFallsBackToFadeInPlace() {
        let plan = CompletionMotionPlan.plan(variant: .liveSolve, outcomeKind: .success, reduceMotion: true)
        #expect(plan.panelRise == .fadeInPlace(duration: 0.45))
    }

    // MARK: - review ⇒ no M10 rise + no ritual entries

    @Test func reviewHasNoRiseAndNoRitual() {
        let plan = CompletionMotionPlan.plan(variant: .review, outcomeKind: .success, reduceMotion: false)
        #expect(plan.panelRise == .none)
        #expect(plan.accentSeep == .none)
        #expect(plan.streakPip == .none)
        #expect(plan.streakCounter == .none)
        // M2 still plays for review — it's content reveal, not ritual.
        #expect(plan.heroReveal == .riseAndFade(duration: 0.35, rise: 8, stagger: 0.06))
    }

    @Test func reviewUnderReduceMotionStillHasNoRitual() {
        let plan = CompletionMotionPlan.plan(variant: .review, outcomeKind: .success, reduceMotion: true)
        #expect(plan.panelRise == .none)
        #expect(plan.accentSeep == .none)
        #expect(plan.streakPip == .none)
        #expect(plan.streakCounter == .none)
    }

    // MARK: - liveSolve failure (MS loss): panel still rises, ritual does not play

    @Test func liveSolveFailurePanelRisesButNoRitual() {
        let plan = CompletionMotionPlan.plan(variant: .liveSolve, outcomeKind: .failure, reduceMotion: false)
        #expect(plan.panelRise == .rise(duration: 0.45, glowDuration: 0.6))
        #expect(plan.accentSeep == .none)
        #expect(plan.streakPip == .none)
        #expect(plan.streakCounter == .none)
    }
}
