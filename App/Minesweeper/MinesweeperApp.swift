import SwiftUI
import MinesweeperAppComposition

// Standard navigation wire (2026-06-02 Track c.1) — `MinesweeperAppComposition.live()`
// constructs the LiveRouteFactory + top-level `MinesweeperRoot` view (sidebar
// + Home mode-card root + board / settings destinations). Persistence,
// monetization, Daily / Practice are deferred (see follow-up issues).

@main
struct MinesweeperApp: App {
    private let composition = MinesweeperAppComposition.live()

    var body: some Scene {
        WindowGroup {
            composition.rootView
        }
    }
}
