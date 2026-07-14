// ScaledSpacing — prerequisite gate (#762 PR1 spec item B-1).
//
// `ScaledSpacing` composes `@Environment(\.dynamicTypeSize)` + `@Environment
// (\.theme)` as a custom `DynamicProperty`. Apple's documented contract for
// nested `DynamicProperty` composition ("types that conform to
// DynamicProperty can contain further properties of a type conforming to
// DynamicProperty ... SwiftUI updates all dynamic properties of a view
// before recomputing its body") is what makes both axes — Dynamic Type AND
// theme — re-resolve live. This suite renders a probe view through a real
// `NSHostingView` (the same AppKit-hosted path production/snapshot code
// runs through) and asserts the resolved value actually changes on each
// axis. Per the #762 issue adjudication, if either assertion goes red,
// PR1 halts here rather than working around it.
//
// PIVOT (2026-07-13): the original mechanism used `@ScaledMetric`, which
// this same gate caught NOT responding to `\.dynamicTypeSize` overrides in
// this repo's headless AppKit-hosted `swift test` environment (see
// `rawDynamicTypeSizeEnvironmentReachesProbe` below — the canary that
// isolated the fault to `@ScaledMetric` itself, not the harness). See
// `ScaledSpacing.swift`'s PIVOT note for the full root-cause trail.
import SwiftUI
import Testing
@testable import GameShellUI

#if canImport(AppKit)
import AppKit

@MainActor
@Suite("GameShellUI — ScaledSpacing (prerequisite gate)")
struct ScaledSpacingTests {
    @MainActor
    private final class ResolvedBox {
        var value: CGFloat?
    }

    private struct ProbeView: View {
        @ScaledSpacing(.medium) private var spacing
        let box: ResolvedBox

        var body: some View {
            box.value = spacing
            return Color.clear.frame(width: 1, height: 1)
        }
    }

    /// A `Theme` whose spacing is caller-supplied and everything else is
    /// borrowed from `NeutralTheme`, so the theme-swap test doesn't have to
    /// hand-build every other token bundle.
    private struct SpacingOverrideTheme: Theme {
        private let base = NeutralTheme()
        let spacing: SpacingTokens

        var surface: SurfaceTokens { base.surface }
        var text: TextTokens { base.text }
        var accent: AccentTokens { base.accent }
        var status: StatusTokens { base.status }
        var difficulty: DifficultyTokens { base.difficulty }
    }

    private func resolve(theme: any Theme, dynamicTypeSize: DynamicTypeSize? = nil) -> CGFloat? {
        let box = ResolvedBox()
        var view = AnyView(ProbeView(box: box).environment(\.theme, theme))
        if let dynamicTypeSize {
            view = AnyView(view.environment(\.dynamicTypeSize, dynamicTypeSize))
        }
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        host.layoutSubtreeIfNeeded()
        return box.value
    }

    @Test func defaultTypeSizeEqualsRawToken() {
        let theme = NeutralTheme()
        #expect(resolve(theme: theme) == theme.spacing.medium)
    }

    @Test func accessibility5ScalesAboveRawToken() {
        let theme = NeutralTheme()
        let resolved = resolve(theme: theme, dynamicTypeSize: .accessibility5)
        #expect(resolved != nil)
        if let resolved {
            #expect(resolved > theme.spacing.medium)
        }
    }

    @Test func themeSwapChangesResolvedValue() {
        let themeA = SpacingOverrideTheme(spacing: SpacingTokens(medium: 16))
        let themeB = SpacingOverrideTheme(spacing: SpacingTokens(medium: 100))
        #expect(resolve(theme: themeA) == 16)
        #expect(resolve(theme: themeB) == 100)
    }

    // MARK: - Canary (2026-07-13, team-lead directed): does the raw
    // `\.dynamicTypeSize` environment value itself reach a probe in this
    // SAME bare-NSHostingView harness, independent of `@ScaledMetric`? If
    // this reads `.accessibility5` but `ScaledSpacing` still doesn't scale,
    // the fault is `@ScaledMetric`-specific, not the harness. Kept as a
    // permanent regression guard rather than deleted after the experiment —
    // it's cheap and pins down which half of the pipeline is trustworthy.

    @MainActor
    private final class DTSBox {
        var value: DynamicTypeSize?
    }

    private struct RawDynamicTypeSizeProbe: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let box: DTSBox

        var body: some View {
            box.value = dynamicTypeSize
            return Color.clear.frame(width: 1, height: 1)
        }
    }

    @Test func rawDynamicTypeSizeEnvironmentReachesProbe() {
        let box = DTSBox()
        let view = RawDynamicTypeSizeProbe(box: box).environment(\.dynamicTypeSize, .accessibility5)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        host.layoutSubtreeIfNeeded()
        #expect(box.value == .accessibility5)
    }

    // MARK: - Multiplier table monotonicity (owner adjudication, 2026-07-13)

    @Test func multiplierTableIsMonotonicNonDecreasing() {
        let ordered = DynamicTypeSize.allCases.sorted()
        for (previous, current) in zip(ordered, ordered.dropFirst()) {
            #expect(
                current.scaledSpacingMultiplier >= previous.scaledSpacingMultiplier,
                "\(current) (\(current.scaledSpacingMultiplier)) < \(previous) (\(previous.scaledSpacingMultiplier))"
            )
        }
    }

    @Test func multiplierTableIsOneAtAndBelowDefaultSize() {
        #expect(DynamicTypeSize.large.scaledSpacingMultiplier == 1.0)
        #expect(DynamicTypeSize.xSmall.scaledSpacingMultiplier == 1.0)
    }

    @Test func multiplierTableCapsWellBelowBodyTextGrowth() {
        // The ~3× figure is the PIVOT note's cited body-text growth at AX5;
        // this pins the spacing cap to stay well under it (currently 1.65).
        #expect(DynamicTypeSize.accessibility5.scaledSpacingMultiplier < 2.0)
    }
}
#endif
