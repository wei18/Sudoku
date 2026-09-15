// PracticeHubShellView — generic Practice hub chrome + difficulty/CTA slots.
//
// Owns the parts of a "pick a difficulty, draw a puzzle" hub that don't
// change across games:
//   - a `ScrollView` wrapping the `VStack(alignment: .leading, spacing: 24)`
//     with `.padding(16)` (#1021 Phase G: was a fixed, non-scrolling VStack —
//     see the body's doc comment for why that overlapped the navigation
//     title at accessibility Dynamic Type sizes)
//   - the chrome triple (`.background(Color)` + `.navigationTitle`)
//   - the inline section header `Text` for the filter slot, with caller-
//     supplied foreground color (`headerForeground`)
//
// Caller supplies:
//   - `title` and `filterHeader` (both `LocalizedStringKey`)
//   - resolved theme colors as init params: `backgroundColor` for the chrome
//     background, `headerForeground` for the section header
//   - the `filter` slot (the game's segmented Picker, including its tint /
//     glassEffect / padding decoration — none of which the shell touches)
//   - the `cta` slot (the game's draw/start affordance — Sudoku's `drawCard`
//     with its shimmer + glassEffect, or Minesweeper's simpler Start button)
//
// #1080: the `banner` slot (Epic 5) was removed — its only two
// forwarders (`PracticeHubView`, `MinesweeperPracticeHubView`) dropped their
// own `banner:` params in the same PR, so nothing fed this one any more.
// The shared `tabViewBottomAccessory` (design.md §2.4) covers Practice's
// banner today.
//
// Loading state (Sudoku's `PracticeHubLoadingState`) deliberately stays in
// the caller's CTA — the shell carries no state machine. Lets Minesweeper
// opt out cleanly (no async generator, no shimmer threshold today).

public import SwiftUI

public struct PracticeHubShellView<Filter, CTA>: View
where Filter: View, CTA: View {
    private let title: LocalizedStringKey
    private let backgroundColor: Color
    private let filterHeader: LocalizedStringKey
    private let headerForeground: Color
    private let filter: () -> Filter
    private let cta: () -> CTA

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
        @ViewBuilder cta: @escaping () -> CTA
    ) {
        self.title = title
        self.backgroundColor = backgroundColor
        self.filterHeader = filterHeader
        self.headerForeground = headerForeground
        self.filter = filter
        self.cta = cta
    }

    public var body: some View {
        // #1021 Phase G: the filter/CTA content flows in a `ScrollView`
        // below the navigation title instead of a fixed, screen-filling
        // `VStack`. A bare `VStack` under a large title only reserves a
        // single-line title's worth of top space; at an accessibility
        // Dynamic Type size the title wraps to 2+ lines and the fixed
        // content overlapped it (the "Difficulty" label drawn under
        // "Practice"'s second line). A `ScrollView` lets the system
        // report the title's actual (multi-line) height as a top
        // safe-area inset the content flows below, with no magic offset,
        // and also satisfies G3 (content stays reachable if it ever
        // grows taller than the screen at large text sizes).
        ScrollView {
            VStack(alignment: .leading, spacing: contentGap) {
                Text(filterHeader)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(headerForeground)

                filter()

                cta()
            }
            .padding(screenEdgeInset)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(backgroundColor)
        .navigationTitle(title)
    }
}
