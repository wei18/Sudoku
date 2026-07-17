// DailyHubShellView — generic Daily hub chrome + responsive card grid.
//
// Owns the parts of a "today's puzzles" hub that don't change across games:
//   - chrome triple (`.frame.infinity` + `.background(Color)` + `.navigationTitle`)
//   - the 1-or-3-column `LazyVGrid` inside a `ScrollView` with `.padding(16)`
//   - the state switch over `HubLoadState<Item>` (idle / loading / loaded /
//     empty / failed)
//   - the `Button { onItemTap } label: { card }`.buttonStyle(.plain) wrapper
//   - the optional `banner` slot below the scroll region (Epic 5 — Banner
//     Coverage Expansion). GameShellKit is zero-dep: the actual `BannerSlotView`
//     is injected by each app at the RouteFactory level; the default is EmptyView.
//
// The caller supplies:
//   - the title (as `LocalizedStringKey`)
//   - the resolved theme background `Color` (DI via init — shells do not
//     read `@Environment(\.theme)`; mirrors PR X4 SettingsShellView)
//   - the load state (lifted from the caller's view-model state machine
//     via a value-level map; see `SudokuUI.DailyHubView` for an example)
//   - the per-item card builder (`@ViewBuilder card`)
//   - the failure overlay builder (`@ViewBuilder failure`); kept caller-
//     provided so each game owns its own warning copy + tinting tokens
//   - the empty-state overlay builder (`@ViewBuilder empty`), defaulting to
//     `Color.clear` so existing callers (Minesweeper) compile unchanged.
//     #768: Sudoku now supplies an inline icon+message+action block here
//     instead of layering a system `.alert` on top of a blank shell.
//   - the per-item tap action
//   - the `header` slot (#840): rendered ABOVE the content in every state —
//     idle/loading/loaded/empty/failed — mirroring `HomeScreen.header`'s
//     injected-slot shape. Defaults to `EmptyView` so existing callers
//     compile unchanged. Sudoku/MS inject their `DailyStripView` /
//     `MinesweeperDailyStripView` week strip here so it SCROLLS WITH the
//     card grid in `.loaded` (it now lives inside the same `ScrollView`,
//     ahead of the `LazyVGrid`) instead of being pinned above a fixed
//     shell (#840 — owner-reported: the trio scrolled UNDER a fixed strip).
//     For the non-scrolling states (idle/loading/empty/failed) there is no
//     scroll container to join, so the header still renders, just above
//     the centered content, preserving the #774 "never disappears" property.
//   - the `banner` slot (injected by each app; EmptyView default for
//     previews/tests; the actual BannerSlotView is never imported here)
//
// `.task { bootstrap() }` is NOT owned by the shell — same precedent as X4
// (SettingsShellView owns no side-effect modifiers). The caller applies
// that on top of the shell.

public import SwiftUI

public struct DailyHubShellView<Item, Card, Failure, Empty, Header, Banner>: View
where Item: Hashable & Sendable & Identifiable, Card: View, Failure: View, Empty: View, Header: View, Banner: View {
    private let title: LocalizedStringKey
    private let backgroundColor: Color
    private let state: HubLoadState<Item>
    private let card: (Item) -> Card
    private let failure: (String) -> Failure
    private let empty: () -> Empty
    private let onItemTap: (Item) -> Void
    private let header: Header
    private let banner: Banner

    // Structural spacing (#762 PR1 two-tier spacing contract). This shell
    // deliberately does not read `@Environment(\.theme)` for colors (DI via
    // init, mirrors SettingsShellView) — `SpacingTokens()`'s defaults are
    // theme-invariant, so reading the type directly keeps `screenEdgeInset`
    // routed through the token type without a live environment dependency.
    // `cardGridGap` (12pt) predates the 5-tier scale and has no matching
    // field, so it's a plain named constant instead.
    private let screenEdgeInset = SpacingTokens().medium
    private let cardGridGap: CGFloat = 12

    public init(
        title: LocalizedStringKey,
        backgroundColor: Color,
        state: HubLoadState<Item>,
        @ViewBuilder card: @escaping (Item) -> Card,
        @ViewBuilder failure: @escaping (String) -> Failure,
        @ViewBuilder empty: @escaping () -> Empty = { Color.clear },
        onItemTap: @escaping (Item) -> Void,
        @ViewBuilder header: () -> Header = { EmptyView() },
        @ViewBuilder banner: () -> Banner = { EmptyView() }
    ) {
        self.title = title
        self.backgroundColor = backgroundColor
        self.state = state
        self.card = card
        self.failure = failure
        self.empty = empty
        self.onItemTap = onItemTap
        self.header = header()
        self.banner = banner()
    }

    public var body: some View {
        // spacing-exempt: zero-gap chrome seam between scroll content and
        // the banner slot — not a spacing decision.
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            banner
        }
        .background(backgroundColor)
        .navigationTitle(title)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            // #840: `header` joins every non-scrolling state too (no
            // ScrollView to ride here — see `cardList` for the `.loaded`
            // case, where it scrolls WITH the grid instead).
            VStack(spacing: 0) {
                header
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .loaded(let items):
            cardList(items)
        case .empty:
            // #768: caller-provided inline block (defaults to `Color.clear`
            // for callers with no reachable `.empty` state, e.g. Minesweeper).
            VStack(spacing: 0) {
                header
                empty()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .failed(let reason):
            VStack(spacing: 0) {
                header
                failure(reason)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func cardList(_ items: [Item]) -> some View {
        // #840: `header` sits ahead of the grid INSIDE the same `ScrollView`
        // so it scrolls with the trio instead of staying pinned above a
        // fixed shell (owner-reported regression from #774's original
        // "sibling above the shell" placement).
        ScrollView {
            VStack(spacing: 0) {
                header
                LazyVGrid(columns: columns, spacing: cardGridGap) {
                    ForEach(items) { item in
                        Button {
                            onItemTap(item)
                        } label: {
                            card(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(screenEdgeInset)
            }
        }
    }

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var columns: [GridItem] {
        if sizeClass == .regular {
            return [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ]
        }
        return [GridItem(.flexible())]
    }
}
