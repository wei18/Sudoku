import SwiftUI
import Game2048AppComposition

// SDD-004 / SDD-005 Pillar C (#479): shell app entry point. Mirrors MinesweeperApp.swift —
// `Game2048AppComposition.live()` constructs the composition root via
// `GameConfig`/`makeGameApp` (shared backbone). Gameplay UI (board / hubs /
// settings destinations) and the shared GameHomeView are mounted via `composition.rootView`.

@main
struct Tiles2048App: App {
    private let composition = Game2048AppComposition.live()

    var body: some Scene {
        WindowGroup {
            composition.rootView
        }
    }
}
