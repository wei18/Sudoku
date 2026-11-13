// CellFeedbackMotionPlan — the per-cell success animation table (#1018),
// modeled as a pure value so Sudoku and Minesweeper read the SAME timings,
// the SAME Reduce Motion choice and the SAME delay arithmetic instead of each
// game re-deriving them (mirror principle).
//
// docs/designs/v3/design.md §6 rows M12 (unit sweep) / M13 (region reveal).
// Reduce Motion here is NOT "off" for the sweep: the HIG accessibility page
// asks for "Replacing transitions in x-, y-, and z-axes with fades to avoid
// motion", so the travelling band becomes a static flash. The outward reveal
// wave has no flash to fall back to: its Reduce Motion form (`.simultaneous`)
// means every cell appears in the same frame with no added animation, exactly
// as a reveal looked before the wave existed. Same shape as
// `CompletionMotionPlan`.
//
// The Sudoku digit-placement scale is deliberately NOT a row here: that
// animation already ships in SudokuUI and is left untouched.

public struct CellFeedbackMotionPlan: Sendable, Equatable {
    public var unitSweep: UnitSweepForm
    public var regionReveal: RegionRevealForm

    public init(unitSweep: UnitSweepForm, regionReveal: RegionRevealForm) {
        self.unitSweep = unitSweep
        self.regionReveal = regionReveal
    }

    /// The four base timings, in seconds. Injectable so rendered tests can
    /// supply a deliberately slow timing (an offscreen render cannot observe
    /// an 8 ms stagger); production always uses `.design`.
    public struct Timing: Sendable, Equatable {
        public var unitSweep: Double
        public var waveStagger: Double
        public var cellFade: Double
        public var waveCap: Double

        public init(unitSweep: Double, waveStagger: Double, cellFade: Double, waveCap: Double) {
            self.unitSweep = unitSweep
            self.waveStagger = waveStagger
            self.cellFade = cellFade
            self.waveCap = waveCap
        }

        /// design.md §6 M12/M13: 180 ms sweep, 8 ms per ring, 80 ms cell fade,
        /// 200 ms cap. Each number lives here exactly once.
        public static let design = Timing(unitSweep: 0.18, waveStagger: 0.008, cellFade: 0.08, waveCap: 0.2)
    }

    /// M12 — a completed Sudoku row / column / box. Default: a light band
    /// travels across the unit (180 ms). RM: the whole unit lights at once
    /// and fades; no travel.
    public enum UnitSweepForm: Sendable, Equatable {
        case sweep(duration: Double)
        case staticFlash(duration: Double)
    }

    /// M13 — a Minesweeper reveal. Default: expands outward from the tapped
    /// cell, `stagger` per ring, each cell fading over `cellDuration`, the
    /// whole thing finished within `cap`. RM: every cell at once with no delay
    /// and no added animation (so it carries no duration: the reveal is
    /// instant, "all cells appear in the same frame").
    public enum RegionRevealForm: Sendable, Equatable {
        case wave(stagger: Double, cellDuration: Double, cap: Double)
        case simultaneous

        /// Delay in seconds for a cell `ring` steps from the tapped cell
        /// (0 = the tapped cell); `maxRing` is the largest ring in the region.
        /// When `maxRing * stagger` would overrun `cap - cellDuration` the
        /// stagger is compressed uniformly (never clamped: clamping would make
        /// the far cells pop together, which is not a wave).
        public func delay(ring: Int, maxRing: Int) -> Double {
            switch self {
            case .simultaneous:
                return 0
            case let .wave(stagger, cellDuration, cap):
                guard maxRing > 0 else { return 0 }
                let clamped = Double(min(max(ring, 0), maxRing))
                let latestDelay = cap - cellDuration
                if Double(maxRing) * stagger <= latestDelay {
                    return clamped * stagger
                }
                return latestDelay * clamped / Double(maxRing)
            }
        }

        /// Seconds from the reveal starting until the last cell finishes.
        public func totalDuration(maxRing: Int) -> Double {
            switch self {
            case .simultaneous:
                return 0
            case let .wave(_, cellDuration, _):
                return delay(ring: maxRing, maxRing: maxRing) + cellDuration
            }
        }
    }

    /// Extra life an event gets on top of its animation. An event's expiry
    /// timer starts when it begins, but its animation only starts at the next
    /// render, so a busy main actor could otherwise remove the event before
    /// its last frames (or before its first). An event is invisible once its
    /// animation has finished, so a longer life costs nothing.
    static let lifetimeSlack = Duration.milliseconds(300)

    /// How long a unit-sweep event stays active: the sweep's length plus
    /// `lifetimeSlack`, valid for BOTH the default and the Reduce Motion form,
    /// for view models that expire an event without knowing the Reduce Motion
    /// setting. This is the EVENT's life, not the animation: the animation is
    /// `Timing.design.unitSweep`.
    public static let unitSweepLifetime = Duration.seconds(Timing.design.unitSweep) + lifetimeSlack

    /// How long a region-reveal event stays active: the wave's cap plus
    /// `lifetimeSlack`, valid for both forms (the simultaneous form is
    /// instant). The 200 ms cap bounds the ANIMATION (`totalDuration`), not
    /// this event life.
    public static let regionRevealLifetime = Duration.seconds(Timing.design.waveCap) + lifetimeSlack
}

public extension CellFeedbackMotionPlan {
    /// Derive the plan. Pure function — no environment reads. The lifetimes
    /// above stay on `.design`: view models have no environment and always
    /// expire on design time.
    static func plan(reduceMotion: Bool, timing: Timing = .design) -> CellFeedbackMotionPlan {
        CellFeedbackMotionPlan(
            unitSweep: reduceMotion
                ? .staticFlash(duration: timing.unitSweep)
                : .sweep(duration: timing.unitSweep),
            regionReveal: reduceMotion
                ? .simultaneous
                : .wave(stagger: timing.waveStagger, cellDuration: timing.cellFade, cap: timing.waveCap)
        )
    }
}
