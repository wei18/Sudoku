// CellFeedbackMotionPlanTests — #1018: pins the shared cell-feedback motion
// table (design.md §6 M12/M13) so Sudoku and Minesweeper read one set of
// forms, one delay arithmetic and one set of lifetimes.

import Testing
@testable import GameShellUI

@Suite("CellFeedbackMotionPlan — forms, delay arithmetic, lifetimes (#1018)")
struct CellFeedbackMotionPlanTests {

    // MARK: Forms

    @Test("default plan: sweep 180 ms, wave 8 ms stagger / 80 ms cell / 200 ms cap")
    func defaultForms() {
        let plan = CellFeedbackMotionPlan.plan(reduceMotion: false)
        #expect(plan.unitSweep == .sweep(duration: 0.18))
        #expect(plan.regionReveal == .wave(stagger: 0.008, cellDuration: 0.08, cap: 0.2))
    }

    @Test("Reduce Motion plan: static flash and simultaneous reveal, no travel")
    func reduceMotionForms() {
        let plan = CellFeedbackMotionPlan.plan(reduceMotion: true)
        #expect(plan.unitSweep == .staticFlash(duration: 0.18))
        #expect(plan.regionReveal == .simultaneous)
    }

    // MARK: Timing seam

    @Test("design timing is pinned to the §6 values (literals, not the constants)")
    func designTimingIsPinned() {
        let design = CellFeedbackMotionPlan.Timing.design
        #expect(design.unitSweep == 0.18)
        #expect(design.waveStagger == 0.008)
        #expect(design.cellFade == 0.08)
        #expect(design.waveCap == 0.2)
    }

    @Test("plan without a timing argument equals the design-timing plan", arguments: [false, true])
    func defaultTimingIsDesign(reduceMotion: Bool) {
        #expect(
            CellFeedbackMotionPlan.plan(reduceMotion: reduceMotion)
                == CellFeedbackMotionPlan.plan(reduceMotion: reduceMotion, timing: .design)
        )
    }

    @Test("a custom timing flows into both forms of both rows")
    func customTimingFlowsThrough() {
        let slow = CellFeedbackMotionPlan.Timing(unitSweep: 2, waveStagger: 0.5, cellFade: 1, waveCap: 9)
        let motion = CellFeedbackMotionPlan.plan(reduceMotion: false, timing: slow)
        #expect(motion.unitSweep == .sweep(duration: 2))
        #expect(motion.regionReveal == .wave(stagger: 0.5, cellDuration: 1, cap: 9))
        let reduced = CellFeedbackMotionPlan.plan(reduceMotion: true, timing: slow)
        #expect(reduced.unitSweep == .staticFlash(duration: 2))
        #expect(reduced.regionReveal == .simultaneous)
    }

    @Test("resolved builds the plan from override ?? system and the given timing")
    func resolvedPlan() {
        let slow = CellFeedbackMotionPlan.Timing(unitSweep: 2, waveStagger: 0.5, cellFade: 1, waveCap: 9)
        #expect(
            CellFeedbackMotionPlan.resolved(reduceMotionOverride: nil, systemReduceMotion: true, timing: slow)
                == CellFeedbackMotionPlan.plan(reduceMotion: true, timing: slow)
        )
        #expect(
            CellFeedbackMotionPlan.resolved(reduceMotionOverride: false, systemReduceMotion: true, timing: .design)
                == CellFeedbackMotionPlan.plan(reduceMotion: false)
        )
    }

    // MARK: Delay arithmetic

    private var wave: CellFeedbackMotionPlan.RegionRevealForm {
        CellFeedbackMotionPlan.plan(reduceMotion: false).regionReveal
    }

    @Test("small region keeps the plain 8 ms stagger")
    func smallRegionUsesPlainStagger() {
        #expect(wave.delay(ring: 0, maxRing: 5) == 0)
        #expect(abs(wave.delay(ring: 3, maxRing: 5) - 0.024) < 1e-9)
        #expect(abs(wave.delay(ring: 5, maxRing: 5) - 0.040) < 1e-9)
        #expect(abs(wave.totalDuration(maxRing: 5) - 0.120) < 1e-9)
    }

    @Test("worst case on 16x30 Expert (maxRing 29) finishes within the 200 ms cap")
    func worstCaseWithinCap() {
        #expect(wave.totalDuration(maxRing: 29) <= 0.2 + 1e-9)
    }

    @Test("compression keeps the wave strictly increasing over 0...29")
    func compressedWaveStrictlyIncreasing() {
        let delays = (0...29).map { wave.delay(ring: $0, maxRing: 29) }
        #expect(delays.first == 0)
        for index in 1..<delays.count {
            #expect(delays[index] > delays[index - 1])
        }
    }

    @Test("Reduce Motion form has zero delay for every ring")
    func simultaneousIsZero() {
        let form = CellFeedbackMotionPlan.plan(reduceMotion: true).regionReveal
        for ring in 0...29 {
            #expect(form.delay(ring: ring, maxRing: 29) == 0)
        }
        #expect(form.totalDuration(maxRing: 29) == 0)
    }

    @Test("degenerate inputs: maxRing 0, ring above maxRing, negative ring")
    func degenerateInputs() {
        #expect(wave.delay(ring: 0, maxRing: 0) == 0)
        #expect(wave.delay(ring: 4, maxRing: 0) == 0)
        #expect(wave.delay(ring: 9, maxRing: 5) == wave.delay(ring: 5, maxRing: 5))
        #expect(wave.delay(ring: -3, maxRing: 5) == 0)
        #expect(wave.delay(ring: 2, maxRing: -1) == 0)
        #expect(abs(wave.totalDuration(maxRing: 0) - 0.08) < 1e-9)
    }

    // MARK: Lifetimes

    @Test("an event's lifetime covers the animation of both forms plus the slack")
    func lifetimesCoverBothFormsPlusSlack() {
        let slack = CellFeedbackMotionPlan.lifetimeSlack
        #expect(slack >= .milliseconds(200), "the slack must be generous enough to absorb a busy main actor")
        for reduceMotion in [false, true] {
            let plan = CellFeedbackMotionPlan.plan(reduceMotion: reduceMotion)
            let sweepSeconds: Double
            switch plan.unitSweep {
            case let .sweep(duration), let .staticFlash(duration): sweepSeconds = duration
            }
            #expect(CellFeedbackMotionPlan.unitSweepLifetime >= .seconds(sweepSeconds) + slack)
            // Same 1e-9 s float slack as the cap test (compressed total can be one ulp over 0.2).
            #expect(CellFeedbackMotionPlan.regionRevealLifetime >= .seconds(plan.regionReveal.totalDuration(maxRing: 29) - 1e-9) + slack)
            #expect(CellFeedbackMotionPlan.regionRevealLifetime >= .seconds(plan.regionReveal.totalDuration(maxRing: 0) - 1e-9) + slack)
        }
    }
}
