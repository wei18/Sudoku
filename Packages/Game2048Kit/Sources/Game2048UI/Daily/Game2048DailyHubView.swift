// Game2048DailyHubView — Tiles2048 daily hub.
//
// 2048 has a single daily board per UTC day (one seed, no difficulty tiers),
// so the hub is simpler than Minesweeper's 3-board hub. The hub shows a
// single card that routes to the board.
//
// The banner slot is injected by LiveRouteFactory (Epic 5 pattern).

public import SwiftUI
internal import MonetizationCore
internal import MonetizationUI
internal import GameShellUI
internal import Game2048Engine

public struct Game2048DailyHubView<Banner: View>: View {
    @Binding private var path: [AppRoute]
    private let banner: Banner
    @Environment(\.theme) private var theme

    public init(
        path: Binding<[AppRoute]>,
        @ViewBuilder banner: () -> Banner = { EmptyView() }
    ) {
        self._path = path
        self.banner = banner()
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                dailyCard
                banner
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .navigationTitle("Daily")
        .background(theme.surface.background.resolved)
    }

    private var dailyCard: some View {
        Button {
            let seed = Game2048Daily.seed(forDate: .now)
            path.append(.board(seed: seed, mode: .daily))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "calendar")
                        .font(.title2)
                        .foregroundStyle(theme.accent.primary.resolved)
                    Text("Today's Board")
                        .font(.headline)
                        .foregroundStyle(theme.text.primary.resolved)
                    Spacer()
                }
                Text("One shared board for everyone today")
                    .font(.subheadline)
                    .foregroundStyle(theme.text.secondary.resolved)
            }
            .padding(16)
            .background(theme.surface.primary.resolved)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tiles2048.dailyHub.todayCard")
    }
}

#Preview("Daily Hub") {
    @Previewable @State var path: [AppRoute] = []
    NavigationStack(path: $path) {
        Game2048DailyHubView(path: $path)
            .environment(\.theme, Game2048Theme())
    }
}
