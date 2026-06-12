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
//   - the per-item tap action
//   - the `banner` slot (injected by each app; EmptyView default for
//     previews/tests; the actual BannerSlotView is never imported here)
//
// `.task { bootstrap() }` and the empty-state `.alert(...)` are NOT owned
// by the shell — same precedent as X4 (SettingsShellView owns no side-
// effect modifiers). The caller applies those on top of the shell.

public import SwiftUI

public struct DailyHubShellView<Item, Card, Failure, Banner>: View
where Item: Hashable & Sendable & Identifiable, Card: View, Failure: View, Banner: View {
    private let title: LocalizedStringKey
    private let backgroundColor: Color
    private let state: HubLoadState<Item>
    private let card: (Item) -> Card
    private let failure: (String) -> Failure
    private let onItemTap: (Item) -> Void
    private let banner: Banner

    public init(
        title: LocalizedStringKey,
        backgroundColor: Color,
        state: HubLoadState<Item>,
        @ViewBuilder card: @escaping (Item) -> Card,
        @ViewBuilder failure: @escaping (String) -> Failure,
        onItemTap: @escaping (Item) -> Void,
        @ViewBuilder banner: () -> Banner = { EmptyView() }
    ) {
        self.title = title
        self.backgroundColor = backgroundColor
        self.state = state
        self.card = card
        self.failure = failure
        self.onItemTap = onItemTap
        self.banner = banner()
    }

    public var body: some View {
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
            ProgressView().controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let items):
            cardList(items)
        case .empty:
            // Mirrors Sudoku's `.exhausted` precedent (caller surfaces the
            // empty case via `.alert` on top of the shell). Shell shows an
            // empty backdrop so the alert reads as the primary surface.
            Color.clear
        case .failed(let reason):
            failure(reason)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func cardList(_ items: [Item]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { item in
                    Button {
                        onItemTap(item)
                    } label: {
                        card(item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
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
