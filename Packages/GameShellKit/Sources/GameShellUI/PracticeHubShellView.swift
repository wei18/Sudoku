// PracticeHubShellView — generic Practice hub chrome + difficulty/CTA slots.
//
// Owns the parts of a "pick a difficulty, draw a puzzle" hub that don't
// change across games:
//   - the outer `VStack(alignment: .leading, spacing: 24)` with
//     `.padding(16)` + `.frame(maxWidth/Height: .infinity, alignment: .top)`
//   - the chrome triple (`.background(Color)` + `.navigationTitle`)
//   - the inline section header `Text` for the filter slot, with caller-
//     supplied foreground color (`headerForeground`)
//   - the optional `banner` slot pinned below the scrollable content (Epic 5).
//     GameShellKit is zero-dep: the actual `BannerSlotView` is injected by
//     each app at the RouteFactory level; the default is EmptyView.
//
// Caller supplies:
//   - `title` and `filterHeader` (both `LocalizedStringKey`)
//   - resolved theme colors as init params: `backgroundColor` for the chrome
//     background, `headerForeground` for the section header
//   - the `filter` slot (the game's segmented Picker, including its tint /
//     glassEffect / padding decoration — none of which the shell touches)
//   - the `cta` slot (the game's draw/start affordance — Sudoku's `drawCard`
//     with its shimmer + glassEffect, or Minesweeper's simpler Start button)
//   - the `banner` slot (injected by each app; EmptyView default for
//     previews/tests; the actual BannerSlotView is never imported here)
//
// Loading state (Sudoku's `PracticeHubLoadingState`) deliberately stays in
// the caller's CTA — the shell carries no state machine. Lets Minesweeper
// opt out cleanly (no async generator, no shimmer threshold today).

public import SwiftUI

public struct PracticeHubShellView<Filter, CTA, Banner>: View
where Filter: View, CTA: View, Banner: View {
    private let title: LocalizedStringKey
    private let backgroundColor: Color
    private let filterHeader: LocalizedStringKey
    private let headerForeground: Color
    private let filter: () -> Filter
    private let cta: () -> CTA
    private let banner: Banner

    // Structural screen-edge inset (#762 PR1 two-tier spacing contract).
    // This shell deliberately does not read `@Environment(\.theme)` for
    // colors (DI via init, mirrors SettingsShellView) — `SpacingTokens()`'s
    // defaults are theme-invariant (every concrete `Theme` uses the same
    // values), so reading the type directly keeps that value routed through
    // the token type without adding a live environment dependency.
    private let screenEdgeInset = SpacingTokens().medium
    // Content spacing (label / filter / CTA stack) — scales with Dynamic Type.
    @ScaledSpacing(.large) private var contentGap

    public init(
        title: LocalizedStringKey,
        backgroundColor: Color,
        filterHeader: LocalizedStringKey,
        headerForeground: Color,
        @ViewBuilder filter: @escaping () -> Filter,
        @ViewBuilder cta: @escaping () -> CTA,
        @ViewBuilder banner: () -> Banner = { EmptyView() }
    ) {
        self.title = title
        self.backgroundColor = backgroundColor
        self.filterHeader = filterHeader
        self.headerForeground = headerForeground
        self.filter = filter
        self.cta = cta
        self.banner = banner()
    }

    public var body: some View {
        // spacing-exempt: zero-gap chrome seam between the scrollable content
        // and the banner slot — not a spacing decision.
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: contentGap) {
                Text(filterHeader)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(headerForeground)

                filter()

                cta()

                Spacer()
            }
            .padding(screenEdgeInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            banner
        }
        .background(backgroundColor)
        .navigationTitle(title)
    }
}
