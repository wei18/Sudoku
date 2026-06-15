import SwiftUI
import Game2048AppComposition

// SDD-004 Milestone 2: shell app entry point. Mirrors MinesweeperApp.swift —
// `Game2048AppComposition.live()` constructs the composition root (LiveRouteFactory
// + top-level `Game2048Root` view). Gameplay UI (board / hubs / settings
// destinations) and full platform wiring land in Milestones 3–4.

@main
struct Tiles2048App: App {
    private let composition = Game2048AppComposition.live()

    var body: some Scene {
        WindowGroup {
            composition.rootView
        }
    }
}
