// CellFeedbackReduceMotionTests — #1018: the public Reduce Motion test seam.

import SwiftUI
import Testing
@testable import GameShellUI

@Suite("CellFeedback Reduce Motion seam (#1018)")
struct CellFeedbackReduceMotionTests {

    @Test("un-injected override defaults to nil")
    func defaultIsNil() {
        #expect(EnvironmentValues().cellFeedbackReduceMotionOverride == nil)
    }

    @Test("un-injected timing defaults to .design; an injected timing reads back")
    func timingDefaultAndReadBack() {
        #expect(EnvironmentValues().cellFeedbackTiming == .design)
        var values = EnvironmentValues()
        let slow = CellFeedbackMotionPlan.Timing(unitSweep: 2, waveStagger: 0.5, cellFade: 1, waveCap: 9)
        values.cellFeedbackTiming = slow
        #expect(values.cellFeedbackTiming == slow)
    }

    @Test("the shared plan follows the override and the timing")
    func sharedPlanFollowsOverrideAndTiming() {
        var values = EnvironmentValues()
        #expect(values.cellFeedbackMotionPlan == CellFeedbackMotionPlan.plan(reduceMotion: false))

        values.cellFeedbackReduceMotionOverride = true
        #expect(values.cellFeedbackMotionPlan == CellFeedbackMotionPlan.plan(reduceMotion: true))

        let slow = CellFeedbackMotionPlan.Timing(unitSweep: 2, waveStagger: 0.5, cellFade: 1, waveCap: 9)
        values.cellFeedbackReduceMotionOverride = false
        values.cellFeedbackTiming = slow
        #expect(values.cellFeedbackMotionPlan == CellFeedbackMotionPlan.plan(reduceMotion: false, timing: slow))
    }

    @Test("an injected override reads back")
    func overrideReadsBack() {
        var values = EnvironmentValues()
        values.cellFeedbackReduceMotionOverride = true
        #expect(values.cellFeedbackReduceMotionOverride == true)
        values.cellFeedbackReduceMotionOverride = false
        #expect(values.cellFeedbackReduceMotionOverride == false)
    }

    @Test("effectiveReduceMotion = override ?? system", arguments: [
        (nil as Bool?, false, false),
        (nil as Bool?, true, true),
        (false as Bool?, true, false),
        (true as Bool?, false, true),
        (true as Bool?, true, true),
        (false as Bool?, false, false),
    ])
    func truthTable(override: Bool?, system: Bool, expected: Bool) {
        #expect(CellFeedbackMotionPlan.effectiveReduceMotion(override: override, system: system) == expected)
    }
}
