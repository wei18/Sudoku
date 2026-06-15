// Game2048Root — top-level navigation root for the Tiles2048 app.
//
// M3: wires NavigationStack + `.navigationDestination(for: AppRoute.self)`
// so tapping Daily / Classic on the home screen launches a real board.
//
// M3 navigation shape: plain NavigationStack push (no modal GameRoot).
// M4 will replace this with the shared `GameRoot` / `GameRootViewModel<AppRoute>`
// pattern (#474 modal flow) — the M3→M4 transition is additive:
//   1. Wrap this NavigationStack in GameRoot (modal).
//   2. Inject GameRootViewModel<AppRoute> (GC auth + resume poll).
//   3. Add theme injection (.environment(\.theme, Game2048Theme())).
//   4. Add banner slot + toast overlay (AppMonetizationKit / MonetizationUI).
//
// Seed derivation:
//   Daily    → Game2048Daily.seed(forDate: .now) at navigation time.
//   Practice → seconds since epoch cast to UInt64 (varied, no CSPRNG dependency).

public import SwiftUI
internal import Game2048Engine
internal import GameShellUI

@MainActor
public struct Game2048Root: View {

    @State private var navigationPath = NavigationPath()

    public init() {}

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            Game2048HomeView(
                onDailyTap: { pushDaily() },
                onPracticeTap: { pushPractice() },
                onSettingsTap: { navigationPath.append(AppRoute.settings) }
            )
            .navigationDestination(for: AppRoute.self) { route in
                routeDestination(route)
            }
        }
    }

    // MARK: - Route destinations

    @ViewBuilder
    private func routeDestination(_ route: AppRoute) -> some View {
        switch route {
        case .board(let seed, let mode):
            Game2048BoardView(seed: seed, mode: mode)
                .navigationTitle(mode == .daily ? "Daily" : "Classic")
        case .settings:
            // M4: wire Game2048SettingsView (mirrors MinesweeperSettingsView).
            Text("Settings — coming in M4")
                .navigationTitle("Settings")
        }
    }

    // MARK: - Navigation helpers

    private func pushDaily() {
        let seed = Game2048Daily.seed(forDate: .now)
        navigationPath.append(AppRoute.board(seed: seed, mode: .daily))
    }

    private func pushPractice() {
        // Varied seed: seconds-since-epoch gives a new board each tap without
        // a true CSPRNG dependency at this layer (M4 may use SystemRandomNumberGenerator).
        let seed = UInt64(abs(Date.now.timeIntervalSince1970))
        navigationPath.append(AppRoute.board(seed: seed, mode: .practice))
    }
}
