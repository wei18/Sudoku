// ScaledSpacing — Dynamic-Type-aware spacing token resolution.
//
// design-system.md §Spacing scale (two-tier contract, #762 PR1, owner
// adjudication 2026-07-13): CONTENT spacing (padding / stack gaps adjacent
// to text or icons) scales with Dynamic Type; STRUCTURAL spacing (screen
// margins, card outer gaps, hit-target minimums, board-cell geometry) stays
// fixed but still routes through `theme.spacing.*` (or a named constant),
// with `// spacing-exempt: <reason>` for intentional one-offs.
//
// `ScaledSpacing` is the CONTENT-tier mechanism: a custom `DynamicProperty`
// that composes `@Environment(\.dynamicTypeSize)` with `@Environment
// (\.theme)` (resolves the base token for the active theme). SwiftUI
// recurses into nested `DynamicProperty`-conforming stored properties and
// re-resolves each one before recomputing a view's `body`, so `wrappedValue`
// stays live across both the Dynamic Type AND the theme axis without the
// call site doing anything beyond declaring the property (verified by
// `ScaledSpacingTests`, the PR1 prerequisite gate).
//
// PIVOT (2026-07-13, canary-confirmed, owner adjudication on issue #762):
// the first cut of this mechanism used `@ScaledMetric(relativeTo: .body)`.
// Gate test B-1 caught it red — `@ScaledMetric` does not respond to
// `\.dynamicTypeSize` / `\.sizeCategory` environment overrides in this
// repo's AppKit-hosted headless `swift test` environment. A canary probe
// (`ScaledSpacingTests.rawDynamicTypeSizeEnvironmentReachesProbe`) proved
// the environment value itself DOES reach a plain `@Environment
// (\.dynamicTypeSize)` read in the same harness, and the theme-swap gate
// test proved the render pass re-evaluates on environment change —
// isolating the fault to `@ScaledMetric` specifically, not the harness or
// the `DynamicProperty` composition pattern. `ScaledSpacing` therefore reads
// `\.dynamicTypeSize` directly and applies its own multiplier table
// (`DynamicTypeSize.scaledSpacingMultiplier` below) instead of delegating to
// `@ScaledMetric`.
//
// At the default Dynamic Type size (and everything through `.large`), the
// multiplier is exactly `1.0`, so `wrappedValue` reduces to `theme.spacing.
// <tier>` unchanged — zero pixel change for any snapshot recorded at the
// default type size.
//
// Only the five tiers `SpacingTokens` exposes are supported. Call sites
// whose existing literal doesn't match one of the five (4 / 8 / 16 / 24 /
// 32) predate this contract and are `spacing-exempt` at the call site
// instead of being silently snapped to a neighboring tier — snapping would
// change the pixel value and break the "existing snapshots stay zero-diff"
// gate this PR is held to.

public import SwiftUI

@propertyWrapper
public struct ScaledSpacing: DynamicProperty {
    public enum Tier: Sendable {
        case extraSmall, small, medium, large, extraLarge
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.theme) private var theme
    private let tier: Tier

    public init(_ tier: Tier) {
        self.tier = tier
    }

    public var wrappedValue: CGFloat {
        baseValue(for: tier, in: theme.spacing) * dynamicTypeSize.scaledSpacingMultiplier
    }

    private func baseValue(for tier: Tier, in tokens: SpacingTokens) -> CGFloat {
        switch tier {
        case .extraSmall: tokens.extraSmall
        case .small: tokens.small
        case .medium: tokens.medium
        case .large: tokens.large
        case .extraLarge: tokens.extraLarge
        }
    }
}

// MARK: - Multiplier table

/// `ScaledSpacing`'s own Dynamic Type multiplier table (see the PIVOT note
/// above for why this exists instead of `@ScaledMetric`). Intentionally
/// internal (not `private`) so `ScaledSpacingTests` can assert monotonicity
/// directly via `@testable import`.
///
/// Steps `.xSmall...large` are `1.0` — the default size and everything
/// below it don't shrink spacing, preserving the "zero pixel change at
/// default size" guarantee for every snapshot recorded there. From `.xLarge`
/// up the multiplier climbs in small, monotonically increasing steps,
/// capped at `1.65` for `.accessibility5` — deliberately far below the ~3×
/// a body-text glyph grows at that size, echoing the restraint of this
/// repo's existing `dynamicTypeSize` clamp call sites (e.g.
/// `CompletionOverlayScaffold`'s `.dynamicTypeSize(...DynamicTypeSize.
/// accessibility2)` cap) — spacing should breathe, not balloon.
extension DynamicTypeSize {
    var scaledSpacingMultiplier: CGFloat {
        switch self {
        case .xSmall, .small, .medium, .large: 1.0
        case .xLarge: 1.05
        case .xxLarge: 1.10
        case .xxxLarge: 1.15
        case .accessibility1: 1.25
        case .accessibility2: 1.35
        case .accessibility3: 1.45
        case .accessibility4: 1.55
        case .accessibility5: 1.65
        @unknown default: 1.0
        }
    }
}
