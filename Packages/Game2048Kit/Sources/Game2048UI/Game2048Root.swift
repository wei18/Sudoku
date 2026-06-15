// Game2048Root — top-level navigation root for the Tiles2048 app (M2 stub).
//
// Wraps GameShellKit's `RootShellView`, which provides:
//   - iPhone: NavigationStack with `HomeScreen` as the root
//   - iPad/Mac: NavigationSplitView (sidebar + detail)
//
// Milestone 3 will add:
//   - `GameRootViewModel<AppRoute>` (via GameAppKit) for auth + resume
//   - `.navigationDestination(for: AppRoute.self)` wired to LiveRouteFactory
//   - Banner slot + toast overlay (AppMonetizationKit / MonetizationUI)
//   - Theme injection (Game2048Theme, mirrors MinesweeperTheme)

public import SwiftUI
internal import GameShellUI

@MainActor
public struct Game2048Root: View {
    // M3: replace with `GameRootViewModel<AppRoute>` from GameAppKit (#448 pattern).
    // Holds the navigation path and launch-bootstrap logic (GC auth, resume poll).

    public init() {}

    public var body: some View {
        // M3: thread routeFactory + viewModel into RootShellView; wire
        // `.navigationDestination(for: AppRoute.self)` via the factory.
        NavigationStack {
            Game2048HomeView(
                onDailyTap: { /* M3: push .daily */ },
                onPracticeTap: { /* M3: push .practice */ },
                onSettingsTap: { /* M3: push .settings */ }
            )
        }
    }
}
