import SwiftUI
import Testing
@testable import GameShellUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - CompletionAccentGlow (#1065)
//
// #1065 (B-5 finding): `CompletionMotionPlan.accentSeep` computed the Reduce
// Motion `.crossfade` form but nothing rendered it — the painted glow was
// gated on M10's `.rise` form, so under Reduce Motion the seep was dropped,
// not cross-faded, while the plan-level unit test stayed green. These tests
// therefore pin the RENDERED path, not the plan value:
//
//   1. `form(for:)` / `animation(for:)` — the exact resolutions the view body
//      renders through (a mutation that renders `.crossfade` with the seep's
//      animation goes red here);
//   2. an offscreen AppKit render of the real `CompletionOverlayScaffold`
//      under the Reduce-Motion seam, probing the bottom band the glow is
//      anchored to (restoring the `if case .rise` gate goes red here).
//
// Honest limit of (2): an offscreen `NSHostingView` capture is one settled
// frame, so it proves the glow EXISTS under Reduce Motion at the same settled
// tint as the sweep path; the crossfade-vs-seep timing itself is pinned by
// (1) on the function the body calls, not observed frame-by-frame.

@Suite("GameShellUI — CompletionAccentGlow (#1065)")
struct CompletionAccentGlowTests {

    private static func plan(
        variant: CompletionVariant = .liveSolve,
        outcomeKind: CompletionOutcome.Kind = .success,
        reduceMotion: Bool
    ) -> CompletionMotionPlan {
        CompletionMotionPlan.plan(variant: variant, outcomeKind: outcomeKind, reduceMotion: reduceMotion)
    }

    // MARK: - Which glow plays (resolved from the plan alone)

    @Test func liveSolveSuccessRendersTheSeep() {
        #expect(CompletionAccentGlow.form(for: Self.plan(reduceMotion: false)) == .seep(duration: 0.6))
    }

    @Test func reduceMotionRendersTheCrossfadeNotNothing() {
        #expect(CompletionAccentGlow.form(for: Self.plan(reduceMotion: true)) == .crossfade(duration: 0.25))
    }

    @Test func liveSolveFailureKeepsM10GlowWithoutRitual() {
        // MS loss: no M1 ritual (`accentSeep == .none`), but the panel still
        // rises with its 0.6 s glow — unchanged from before #1065.
        let plan = Self.plan(outcomeKind: .failure, reduceMotion: false)
        #expect(plan.accentSeep == .none)
        #expect(CompletionAccentGlow.form(for: plan) == .seep(duration: 0.6))
    }

    @Test func liveSolveFailureUnderReduceMotionStaysUnlit() {
        // Pre-#1065 behavior kept on purpose (M10's Reduce-Motion row is
        // silent on its glow) — pinned so a change here is a decision, not drift.
        #expect(CompletionAccentGlow.form(for: Self.plan(outcomeKind: .failure, reduceMotion: true)) == .none)
    }

    @Test func reviewRendersNoGlow() {
        #expect(CompletionAccentGlow.form(for: Self.plan(variant: .review, reduceMotion: false)) == .none)
        #expect(CompletionAccentGlow.form(for: Self.plan(variant: .review, reduceMotion: true)) == .none)
    }

    // MARK: - How opacity gets there

    @Test func crossfadeAnimatesOpacityOnlyNotTheSweep() {
        let crossfade = CompletionAccentGlow.animation(for: .crossfade(duration: 0.25))
        let sweep = CompletionAccentGlow.animation(for: .seep(duration: 0.6))
        #expect(crossfade == .easeInOut(duration: 0.25))
        #expect(crossfade != sweep)
    }

    @Test func seepKeepsTheOriginalEaseOut() {
        #expect(CompletionAccentGlow.animation(for: .seep(duration: 0.6)) == .easeOut(duration: 0.6))
        #expect(CompletionAccentGlow.animation(for: .none) == nil)
    }

    // MARK: - The Reduce-Motion seam falls through to the real setting

    @Test func reduceMotionSeamDefaultsToTheSystemSetting() {
        // No override (the production case) → `accessibilityReduceMotion` decides.
        #expect(EnvironmentValues().completionReduceMotionOverride == nil)
        #expect(CompletionOverlayScaffold<EmptyView>.effectiveReduceMotion(override: nil, system: true) == true)
        #expect(CompletionOverlayScaffold<EmptyView>.effectiveReduceMotion(override: nil, system: false) == false)
        #expect(CompletionOverlayScaffold<EmptyView>.effectiveReduceMotion(override: true, system: false) == true)
    }

    // MARK: - Rendered path: the real scaffold under Reduce Motion

    #if canImport(AppKit)
    /// The settled completion screen's bottom band (design.md §3.5 anchors
    /// the radial glow at `.bottom`) — same band #1028/#1065 measured on the
    /// simulator (y 640–870 pt of a 402×874 pt iPhone 17 Pro frame).
    @MainActor
    @Test func reduceMotionStillPaintsTheGlowInTheScaffold() throws {
        let reduceMotionOn = try Self.bottomBandMeanLuminance(reduceMotion: true)
        let reduceMotionOff = try Self.bottomBandMeanLuminance(reduceMotion: false)
        let noGlow = try Self.bottomBandMeanLuminance(variant: .review, reduceMotion: true)

        // Sanity for the probe itself: the sweep path must be measurable.
        #expect(noGlow - reduceMotionOff > 1.0, "sweep path left no tint in the band — probe is blind")
        // #1065: Reduce Motion must still tint the band (crossfade, not off) …
        #expect(noGlow - reduceMotionOn > 1.0, "Reduce Motion dropped the accent glow instead of cross-fading it")
        // … and settle at the same glow as the sweep path.
        #expect(abs(reduceMotionOn - reduceMotionOff) < 0.5)
    }

    /// A live Minesweeper loss keeps M10's `status.error` wash exactly as
    /// before #1065: painted with Reduce Motion off, absent with it on
    /// (M10's Reduce-Motion row is silent on the glow — kept, not decided here).
    @MainActor
    @Test func lossWashIsUnchangedByResolvingFromThePlan() throws {
        let lossOff = try Self.bottomBandMeanLuminance(outcomeKind: .failure, reduceMotion: false)
        let lossOn = try Self.bottomBandMeanLuminance(outcomeKind: .failure, reduceMotion: true)
        let noGlow = try Self.bottomBandMeanLuminance(variant: .review, outcomeKind: .failure, reduceMotion: false)

        #expect(noGlow - lossOff > 1.0, "loss wash no longer paints with Reduce Motion off")
        #expect(abs(lossOn - noGlow) < 0.5, "loss wash started painting under Reduce Motion — that is a design decision, not #1065")
    }

    @MainActor
    private static func bottomBandMeanLuminance(
        variant: CompletionVariant = .liveSolve,
        outcomeKind: CompletionOutcome.Kind = .success,
        reduceMotion: Bool
    ) throws -> Double {
        let scaffold = CompletionOverlayScaffold(
            variant: variant,
            outcomeKind: outcomeKind,
            context: .practice(onPlayAgain: nil),
            onClose: {},
            card: { Color.clear.frame(height: 120) }
        )
        // Offline renderer: `.onAppear` never fires, so settle the M10 latch
        // through the existing seam; the Reduce-Motion seam is #1065's.
        .environment(\.completionHeroSkipsReveal, true)
        .environment(\.completionReduceMotionOverride, reduceMotion)
        .background(Color.white)

        let host = NSHostingView(rootView: scaffold)
        host.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)

        // Bitmap rows run top-down; scale the point band to the backing pixels.
        let scale = Double(rep.pixelsHigh) / 874
        let rows = Int(640 * scale)..<Int(870 * scale)
        var total = 0.0
        var count = 0
        for row in rows.clamped(to: 0..<rep.pixelsHigh) {
            for col in stride(from: 0, to: rep.pixelsWide, by: 4) {
                guard let color = rep.colorAt(x: col, y: row) else { continue }
                total += Double(color.redComponent + color.greenComponent + color.blueComponent) / 3 * 255
                count += 1
            }
        }
        return count == 0 ? 0 : total / Double(count)
    }
    #endif
}
