// CompletionStreakView — M3 (streak pip advance) + M4 (streak counter +1)
// consumer (#1023 Phase B / docs/designs/v3/design.md §6 rows M3/M4).
//
// ONE shared component (R2 — no per-app copy-paste, unlike the Daily hub's
// own `DailyStripView`/`MinesweeperDailyStripView`, which #774 deliberately
// duplicates per app for a much richer surface: weekday labels, tap-to-review,
// a calendar-card container. This view is a simpler, completion-panel-scoped
// ritual: 7 fill-state pips + a streak-count caption, no interaction, no
// per-day metadata beyond fill state).
//
// Mounted ONLY by `CompletionOverlayScaffold` when its own `showsStreakSection`
// gate passes (variant == .liveSolve, outcome == .success, context is a Daily
// row, and a `CompletionStreakAdvance` was actually resolved) — this view
// assumes it should always render once mounted; it does not re-derive that
// gate itself.
//
// Reveal-latch pattern mirrors `CompletionScreen`'s `heroRevealed` /
// `CompletionOverlayScaffold`'s `panelRevealed`: starts at the PRE-solve
// state, flips to POST on `.onAppear` (or immediately under
// `completionHeroSkipsReveal`, the same offline-renderer escape hatch those
// two views use — headless snapshot/ASC-screenshot captures never fire
// `.onAppear`, so without it they'd render a permanently pre-advance frame).

public import SwiftUI

public struct CompletionStreakView: View {
    @Environment(\.theme) private var theme
    @Environment(\.completionHeroSkipsReveal) private var skipsReveal

    private let advance: CompletionStreakAdvance
    private let motionPlan: CompletionMotionPlan

    /// Starts `false`; flips `true` on appear. Mirrors `CompletionScreen
    /// .heroRevealed` / `CompletionOverlayScaffold.panelRevealed` — one latch
    /// per presentation, not replayed on every body re-evaluation.
    @State private var revealed = false

    // Structural (fixed, not Dynamic-Type-scaled) — mirrors
    // `DailyStripView`'s dot geometry rationale: 7 pips must never wrap or
    // reflow at any text size. Smaller than the hub's 28pt calendar dot
    // (10pt here) since this row carries no weekday label / tap target, just
    // a compact ritual indicator inside an already-dense completion panel.
    private static let pipDiameter: CGFloat = 10
    private static let pipGap: CGFloat = 6

    public init(advance: CompletionStreakAdvance, motionPlan: CompletionMotionPlan) {
        self.advance = advance
        self.motionPlan = motionPlan
    }

    private var isRevealed: Bool { revealed || skipsReveal || !advance.todayAdvanced }

    public var body: some View {
        VStack(spacing: theme.spacing.extraSmall) {
            pipRow
            countCaption
        }
        .accessibilityElement(children: .combine)
        .onAppear { revealed = true }
    }

    // MARK: - M3: pip row

    /// `advance.pipStates` (POST) once revealed, `advance.prePipStates` (PRE)
    /// before — both pure derivations on `CompletionStreakAdvance` itself
    /// (unit-tested independently of this view).
    private var displayedPipStates: [Bool] {
        isRevealed ? advance.pipStates : advance.prePipStates
    }

    private var pipRow: some View {
        HStack(spacing: Self.pipGap) {
            ForEach(Array(displayedPipStates.enumerated()), id: \.offset) { index, filled in
                pip(filled: filled, isToday: index == displayedPipStates.count - 1)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func pip(filled: Bool, isToday: Bool) -> some View {
        Circle()
            .foregroundStyle(filled ? theme.accent.celebratory.resolved : theme.streak.pipOff.resolved)
            .frame(width: Self.pipDiameter, height: Self.pipDiameter)
            .animation(fillAnimation, value: filled)
            .modifier(PipBounce(
                enabled: isToday && advance.todayAdvanced,
                trigger: isRevealed,
                form: motionPlan.streakPip
            ))
    }

    private var fillAnimation: Animation? {
        switch motionPlan.streakPip {
        case .fillAndScale(let duration, _), .fillOnly(let duration): .easeOut(duration: duration)
        case .none: nil
        }
    }

    /// M3's 1.0→1.12→1.0 scale bounce, played once when `trigger` flips.
    /// `.phaseAnimator` is the official SwiftUI primitive for a triggered
    /// multi-step animation — no hand-rolled timer/offset chain needed.
    /// Reduce Motion (`.fillOnly`/`.none`) never applies this modifier at
    /// all (§6 M3 RM row: "只填色,不縮放").
    private struct PipBounce: ViewModifier {
        let enabled: Bool
        let trigger: Bool
        let form: CompletionMotionPlan.StreakPipForm

        func body(content: Content) -> some View {
            if enabled, case .fillAndScale(let duration, let peakScale) = form {
                content.phaseAnimator([1.0, peakScale, 1.0], trigger: trigger) { view, phase in
                    view.scaleEffect(phase)
                } animation: { _ in .easeOut(duration: duration / 2) }
            } else {
                content
            }
        }
    }

    // MARK: - M4: streak count

    private var countCaption: some View {
        streakCaption(count: isRevealed ? advance.postCount : advance.preCount)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(theme.text.primary.resolved)
            .contentTransition(counterContentTransition)
            .animation(counterAnimation, value: isRevealed)
    }

    /// Reuses the Daily hub's existing streak-caption keys verbatim (R5) —
    /// `DailyStripView.streakCaption` mints the same two keys; both already
    /// carry all 7 locales in each app's own `Localizable.xcstrings`.
    private func streakCaption(count: Int) -> Text {
        count >= 7
            ? Text("7+ day streak", bundle: .main)
            : Text("\(count) day streak", bundle: .main)
    }

    private var counterContentTransition: ContentTransition {
        switch motionPlan.streakCounter {
        case .slideReplace: .numericText()
        case .crossfade: .opacity
        case .none: .identity
        }
    }

    private var counterAnimation: Animation? {
        switch motionPlan.streakCounter {
        case .slideReplace(let duration), .crossfade(let duration): .easeOut(duration: duration)
        case .none: nil
        }
    }
}
