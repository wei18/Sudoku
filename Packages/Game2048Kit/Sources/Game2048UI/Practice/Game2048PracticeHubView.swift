// Game2048PracticeHubView — Tiles2048 practice hub.
//
// 2048 has a single practice mode (no difficulty tiers — the game is always
// 4×4 with the same rules). The hub shows a single "New Game" card.
//
// The banner slot is injected by LiveRouteFactory (Epic 5 pattern).

public import SwiftUI
internal import MonetizationCore
internal import MonetizationUI
internal import GameShellUI

public struct Game2048PracticeHubView<Banner: View>: View {
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
                practiceCard
                banner
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .navigationTitle("Classic")
        .background(theme.surface.background.resolved)
    }

    private var practiceCard: some View {
        Button {
            let seed = UInt64(abs(Date.now.timeIntervalSince1970))
            path.append(.board(seed: seed, mode: .practice))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "gamecontroller")
                        .font(.title2)
                        .foregroundStyle(theme.accent.primary.resolved)
                    Text("New Game")
                        .font(.headline)
                        .foregroundStyle(theme.text.primary.resolved)
                    Spacer()
                }
                Text("Unlimited classic play, any time")
                    .font(.subheadline)
                    .foregroundStyle(theme.text.secondary.resolved)
            }
            .padding(16)
            .background(theme.surface.primary.resolved)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tiles2048.practiceHub.newGameCard")
    }
}

#Preview("Practice Hub") {
    @Previewable @State var path: [AppRoute] = []
    NavigationStack(path: $path) {
        Game2048PracticeHubView(path: $path)
            .environment(\.theme, Game2048Theme())
    }
}
