// CompletionMotionPlan — the completion panel's animation table (#1023),
// modeled as a pure value so every call site and test reads the SAME derived
// forms instead of each animating view re-deriving reduce-motion logic.
//
// docs/designs/v3/design.md §6 rows M1/M2/M3/M4/M10 + the Reduce Motion
// column. Reduce Motion here is NOT "off" (unlike `MotionGate`'s existing
// uniform gate for the rest of the design system) — HIG's Reduce Motion
// guidance replaces axis transitions with a fade, it doesn't remove the
// transition outright (accessibility.md:177-181, cited by the design doc).
// `MotionGate` itself is untouched; this is a NEW, completion-specific seam
// that happens to disagree with `MotionGate`'s "nil = off" default.
//
// Ritual (M1 accent seep, M3 streak pip, M4 streak counter) plays ONLY for
// `(liveSolve, .success)` — a review re-view or an MS loss never gets it.
// M10 (panel rise) plays for any `liveSolve` presentation (win OR loss — the
// panel still needs to enter the screen); `review` skips it entirely, which
// is the mechanical definition of "the panel doesn't rise" from §3.5's variant
// table. M2 (hero reveal) is ordinary content reveal, not ritual — it plays
// in both variants; only Reduce Motion changes its form.

public struct CompletionMotionPlan: Sendable, Equatable {
    public var accentSeep: AccentSeepForm
    public var heroReveal: HeroRevealForm
    public var streakPip: StreakPipForm
    public var streakCounter: StreakCounterForm
    public var panelRise: PanelRiseForm

    public init(
        accentSeep: AccentSeepForm,
        heroReveal: HeroRevealForm,
        streakPip: StreakPipForm,
        streakCounter: StreakCounterForm,
        panelRise: PanelRiseForm
    ) {
        self.accentSeep = accentSeep
        self.heroReveal = heroReveal
        self.streakPip = streakPip
        self.streakCounter = streakCounter
        self.panelRise = panelRise
    }

    /// M1 — accent seep behind the glass. Default: 0.6s ease-out, non-blocking.
    /// RM: crossfade 0.25s. `.none` when no ritual plays.
    public enum AccentSeepForm: Sendable, Equatable {
        case seep(duration: Double)
        case crossfade(duration: Double)
        case none
    }

    /// M2 — hero reveal. Default: 350ms fade + 8pt rise, 60ms stagger per
    /// element. RM: fade only, same duration/stagger, no rise (§6 — a
    /// deliberate change from the pre-#1023 snap-to-end-state behavior).
    public enum HeroRevealForm: Sendable, Equatable {
        case riseAndFade(duration: Double, rise: Double, stagger: Double)
        case fadeOnly(duration: Double, stagger: Double)
    }

    /// M3 — streak pip advance. Default: 0.35s fill + 1.0→1.12→1.0 scale.
    /// RM: fill only, no scale bounce. `.none` when no ritual plays.
    public enum StreakPipForm: Sendable, Equatable {
        case fillAndScale(duration: Double, peakScale: Double)
        case fillOnly(duration: Double)
        case none
    }

    /// M4 — streak count +1. Default: 0.3s slide-replace. RM: crossfade
    /// instead of slide. `.none` when no ritual plays.
    public enum StreakCounterForm: Sendable, Equatable {
        case slideReplace(duration: Double)
        case crossfade(duration: Double)
        case none
    }

    /// M10 — panel rises from the bottom. Default: 0.45s rise + 0.6s glow.
    /// RM: fade into place, no rise. `.none` for `review` (panel doesn't
    /// "rise" at all — appears already in place, per §3.5's variant table).
    public enum PanelRiseForm: Sendable, Equatable {
        case rise(duration: Double, glowDuration: Double)
        case fadeInPlace(duration: Double)
        case none
    }
}

public extension CompletionMotionPlan {
    /// Derive the plan for a given presentation. Pure function — no
    /// environment reads — so tests can exercise every `(variant, outcomeKind,
    /// reduceMotion)` combination directly.
    static func plan(
        variant: CompletionVariant,
        outcomeKind: CompletionOutcome.Kind,
        reduceMotion: Bool
    ) -> CompletionMotionPlan {
        let heroReveal: HeroRevealForm = reduceMotion
            ? .fadeOnly(duration: 0.35, stagger: 0.06)
            : .riseAndFade(duration: 0.35, rise: 8, stagger: 0.06)

        let panelRise: PanelRiseForm
        switch variant {
        case .liveSolve:
            panelRise = reduceMotion
                ? .fadeInPlace(duration: 0.45)
                : .rise(duration: 0.45, glowDuration: 0.6)
        case .review:
            panelRise = .none
        }

        let playsRitual = variant == .liveSolve && outcomeKind == .success

        let accentSeep: AccentSeepForm = playsRitual
            ? (reduceMotion ? .crossfade(duration: 0.25) : .seep(duration: 0.6))
            : .none
        let streakPip: StreakPipForm = playsRitual
            ? (reduceMotion ? .fillOnly(duration: 0.35) : .fillAndScale(duration: 0.35, peakScale: 1.12))
            : .none
        let streakCounter: StreakCounterForm = playsRitual
            ? (reduceMotion ? .crossfade(duration: 0.3) : .slideReplace(duration: 0.3))
            : .none

        return CompletionMotionPlan(
            accentSeep: accentSeep,
            heroReveal: heroReveal,
            streakPip: streakPip,
            streakCounter: streakCounter,
            panelRise: panelRise
        )
    }
}
