import SwiftUI
import SudokuAppComposition

@main
struct SudokuApp: App {
    private let composition: AppComposition = AppComposition.live()

    var body: some Scene {
        WindowGroup {
            composition.rootView
        }
    }
}
