import SwiftUI
import AppComposition
import SudokuUI

@main
struct SudokuApp: App {
    private let composition: AppComposition = AppComposition.live()

    var body: some Scene {
        WindowGroup {
            RootView(
                viewModel: composition.rootViewModel,
                puzzleProvider: composition.puzzleProvider,
                persistence: composition.persistence,
                gameCenter: composition.gameCenter,
                telemetry: composition.telemetry
            )
        }
    }
}
