// CompletionStreakAdvance — pre→post Daily-streak state for the M3/M4 ritual
// (#1023 Phase B / docs/designs/v3/design.md §6 rows M3/M4).
//
// Constructed by each app's own `makeFetchStreakAdvance` factory (mirrors
// `DailyCompletionProgress`/`MinesweeperDailyCompletionProgress`'s injection
// shape) from the SAME `DailyStripLogic`/`MinesweeperDailyStripLogic`
// `computeStreak(days:)` the Daily hub's week strip already uses — this type
// does not compute anything itself, it only carries the two already-computed
// counts + the settled pip fill state across the app/GameShellUI boundary.

public struct CompletionStreakAdvance: Sendable, Equatable {
    /// 7-slot pip fill state, oldest (index 0) → today (last index), AFTER
    /// this solve — the settled state `CompletionStreakView` renders once its
    /// reveal animation completes. Today's slot is always `true`: this value
    /// is only ever constructed on a fresh Daily win.
    public let pipStates: [Bool]
    /// Streak count BEFORE this solve (the Daily hub's rolling-7-day
    /// `computeStreak` result, with today's just-solved puzzleId excluded).
    public let preCount: Int
    /// Streak count AFTER this solve (with today's puzzleId included). Always
    /// `>= preCount`.
    public let postCount: Int

    public init(pipStates: [Bool], preCount: Int, postCount: Int) {
        self.pipStates = pipStates
        self.preCount = preCount
        self.postCount = postCount
    }

    /// M3/M4 gate: whether today's pip + the streak counter need to visibly
    /// ADVANCE. `false` when the player already completed a different
    /// difficulty earlier today — today's pip (and the streak) was already
    /// advanced before this solve, so there is nothing left to animate
    /// (replaying the advance a second time the same day would be exactly
    /// the false "fresh accomplishment" report design.md §3.5 rules out for
    /// review paths — here it's the same day, not a re-view, but the
    /// underlying state genuinely didn't change, so there is nothing to
    /// show moving).
    ///
    /// Provably equivalent to "did today's own pip flip off→on": every other
    /// day's completion state is fixed by the time this value is
    /// constructed, so `preCount` and `postCount` can only differ because of
    /// today's slot.
    public var todayAdvanced: Bool { preCount != postCount }

    /// Pip fill state BEFORE this solve — derived from `pipStates` (the
    /// settled/POST state) by flipping today's (last) slot off when
    /// `todayAdvanced`. Every other slot is fixed, so this is the only
    /// derivation needed; exposed as a pure function (mirrors
    /// `CompletionMotionPlan.plan`'s testable-pure-function shape) so the
    /// pre→post pip math is unit-testable without mounting `CompletionStreakView`.
    public var prePipStates: [Bool] {
        guard todayAdvanced, let lastIndex = pipStates.indices.last else { return pipStates }
        var states = pipStates
        states[lastIndex] = false
        return states
    }
}

public extension CompletionStreakAdvance {
    /// Pure visibility gate for the M3/M4 streak ritual (design.md §3.5:
    /// `liveSolve` + success + a Daily context plays "滲透波 + streak 推進",
    /// every other combination plays neither). Exposed as a static function
    /// on this plain `Sendable` value type — NOT on `CompletionOverlayScaffold`
    /// itself, which conforms to `View` and is therefore `@MainActor`-isolated
    /// — so every `(variant, outcomeKind, context, advance)` combination is
    /// unit-testable directly from a non-isolated test context, mirroring
    /// `CompletionMotionPlan.plan`'s testable-pure-function shape. The
    /// scaffold's own `showsStreakSection` computed property forwards here.
    static func showsStreakSection(
        variant: CompletionVariant,
        outcomeKind: CompletionOutcome.Kind,
        context: CompletionContext,
        advance: CompletionStreakAdvance?
    ) -> Bool {
        guard advance != nil, variant == .liveSolve, outcomeKind == .success else { return false }
        switch context {
        case .dailyMoreToday, .dailyAllDone: return true
        case .practice, .loss: return false
        }
    }
}
