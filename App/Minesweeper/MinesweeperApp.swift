import SwiftUI
import MinesweeperAppComposition

// Standard navigation wire (2026-06-02 Track c.1) — `MinesweeperAppComposition.live()`
// constructs the LiveRouteFactory + top-level `MinesweeperRoot` view (sidebar
// + Home mode-card root + board / settings destinations). Persistence,
// monetization, Daily and Practice are all wired live (shipped, v2.6).

@main
struct MinesweeperApp: App {
    private let composition = MinesweeperAppComposition.live()

    var body: some Scene {
        WindowGroup {
            composition.rootView
        }
    }
}
