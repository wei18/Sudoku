// CellFeedbackReduceMotion — #1018: Reduce Motion override seam for the
// shared cell-feedback layer.

public import SwiftUI

private struct CellFeedbackReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

public extension EnvironmentValues {
    /// Test seam: `accessibilityReduceMotion` is read-only, so tests inject
    /// the Reduce Motion state here. `nil` (default) means "use the system
    /// setting". Public, unlike `completionReduceMotionOverride`, because its
    /// readers live in other packages (SudokuUI, MinesweeperUI).
    var cellFeedbackReduceMotionOverride: Bool? {
        get { self[CellFeedbackReduceMotionOverrideKey.self] }
        set { self[CellFeedbackReduceMotionOverrideKey.self] = newValue }
    }
}

private struct CellFeedbackTimingKey: EnvironmentKey {
    static let defaultValue = CellFeedbackMotionPlan.Timing.design
}

public extension EnvironmentValues {
    /// Test seam: lets a rendered test inject a deliberately slow timing so a
    /// windowed render can observe the stagger / travel. Production never
    /// sets it, so the design values always apply.
    var cellFeedbackTiming: CellFeedbackMotionPlan.Timing {
        get { self[CellFeedbackTimingKey.self] }
        set { self[CellFeedbackTimingKey.self] = newValue }
    }
}

public extension CellFeedbackMotionPlan {
    /// The seam falls through to the live `accessibilityReduceMotion` unless
    /// a test set it.
    nonisolated static func effectiveReduceMotion(override: Bool?, system: Bool) -> Bool {
        override ?? system
    }

    /// The one resolver both games' views call to build the plan.
    nonisolated static func resolved(
        reduceMotionOverride: Bool?,
        systemReduceMotion: Bool,
        timing: Timing
    ) -> CellFeedbackMotionPlan {
        plan(
            reduceMotion: effectiveReduceMotion(override: reduceMotionOverride, system: systemReduceMotion),
            timing: timing
        )
    }
}
