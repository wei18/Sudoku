import SwiftUI
import SudokuAppComposition

@main
struct SudokuApp: App {
    private let composition: SudokuAppComposition = SudokuAppComposition.live()

    var body: some Scene {
        WindowGroup {
            composition.rootView
        }
    }
}
