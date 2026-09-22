// CompletionAccentGlow — the accent glow painted BEHIND the completion glass
// (#1023 §3.5, `color.md:68`: glass has no inherent color, it picks up what
// sits behind it). Fixed for #1065.
//
// One view owns BOTH glows that `CompletionOverlayScaffold` used to fold into
// a single `if case .rise` branch: M1's accent seep (the success ritual) and
// M10's accompanying glow while the panel rises (any `liveSolve`, so an MS
// loss keeps its `status.error` wash). #1065: that gate keyed the glow on M10
// being in its non-Reduce-Motion `.rise` form, so under Reduce Motion the
// glow was dropped outright while `motionPlan.accentSeep`'s `.crossfade` was
// computed and never rendered. design.md §6 M1 + hard constraint 2 ("Reduce
// Motion 不是關掉,是換 fade"): the seep must still appear, as a 0.25 s
// opacity crossfade — no sweep, no positional motion.
//
// `form(for:)` and `animation(for:)` are the pure resolutions the view body
// renders through, and what `CompletionAccentGlowTests` pins — there is no
// second, unrendered copy of the Reduce Motion decision any more.

import SwiftUI

struct CompletionAccentGlow: View {
    let motionPlan: CompletionMotionPlan
    let tint: Color
    let revealed: Bool

    var body: some View {
        let form = Self.form(for: motionPlan)
        if case .none = form {
            EmptyView()
        } else {
            // Subtle by design — this paints BEHIND the glass so the glass
            // itself picks up the tint (§3.5); it must not overpower the
            // CTA text sitting on top of the glass. Both forms settle at the
            // same tint; only the way opacity gets there differs.
            RadialGradient(
                colors: [tint.opacity(revealed ? 0.16 : 0), .clear],
                center: .bottom,
                startRadius: 0,
                endRadius: 260
            )
            .ignoresSafeArea()
            .animation(Self.animation(for: form), value: revealed)
        }
    }

    /// Which glow plays, from the plan alone:
    /// - the ritual's M1 form (`.seep` / `.crossfade`) whenever it plays;
    /// - otherwise M10's glow (`.seep(glowDuration)`) while the panel rises
    ///   — the MS-loss error wash, unchanged from before #1065;
    /// - otherwise `.none` (`review`, and a loss under Reduce Motion — M10's
    ///   Reduce-Motion row says nothing about its glow; left as-is here).
    static func form(for plan: CompletionMotionPlan) -> CompletionMotionPlan.AccentSeepForm {
        switch (plan.accentSeep, plan.panelRise) {
        case (.seep, _), (.crossfade, _):
            plan.accentSeep
        case (.none, .rise(_, let glowDuration)):
            .seep(duration: glowDuration)
        case (.none, .fadeInPlace), (.none, .none):
            .none
        }
    }

    /// `.seep` keeps the pre-#1065 0.6 s ease-out; `.crossfade` is a plain
    /// symmetric opacity fade so nothing reads as the seep's outward push.
    static func animation(for form: CompletionMotionPlan.AccentSeepForm) -> Animation? {
        switch form {
        case .seep(let duration): .easeOut(duration: duration)
        case .crossfade(let duration): .easeInOut(duration: duration)
        case .none: nil
        }
    }
}
