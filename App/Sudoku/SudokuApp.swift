import SwiftUI
import SudokuAppComposition

// Standard navigation wire — `SudokuAppComposition.live()` uses
// `makeGameApp` (GameAppKit) to build the shared GameRoot + the #1020 3-tab
// `sidebarAdaptable` shell (Today/Practice/Progress) + ResumePill + ATT sheet
// + GC alert. LiveRouteFactory handles board / settings destinations.
// Persistence, monetization, Daily and Practice are all wired live (shipped,
// v2.6). (#557 SDD-005 convergence)

@main
struct SudokuApp: App {
    private let composition: SudokuAppComposition = SudokuAppComposition.live()

    var body: some Scene {
        WindowGroup {
            composition.rootView
        }
    }
}
