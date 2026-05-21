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
                routeFactory: composition.routeFactory
            )
        }
    }
}
