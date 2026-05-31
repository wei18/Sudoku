import SwiftUI
import MinesweeperAppComposition

// PR D skeleton — wires the placeholder `MinesweeperRootView` into a
// `WindowGroup`. AdMob / IAP / Persistence boot lands in follow-up PRs
// (mirroring SudokuApp.swift's composition.bootMonetization() pattern).

@main
struct MinesweeperApp: App {
    var body: some Scene {
        WindowGroup {
            MinesweeperAppComposition.bootRootView()
        }
    }
}
