import SwiftUI
import SudokuAppComposition

// Standard navigation wire — `SudokuAppComposition.live()` uses
// `makeGameApp` (GameAppKit) to build the shared GameRoot + GameHomeView +
// ResumePill + ATT sheet + GC alert. LiveRouteFactory handles board /
// settings destinations. Persistence, monetization, Daily and Practice
// are all wired live (shipped, v2.6). (#557 SDD-005 convergence)

@main
struct SudokuApp: App {
    private let composition: SudokuAppComposition = SudokuAppComposition.live()

    var body: some Scene {
        WindowGroup {
            // THROWAWAY spike hijack — issue #1019 (epic #1014, B-4). Never
            // merge past this branch: `-spike1019` swaps the real
            // composition root for a `sidebarAdaptable` TabView skeleton
            // with NO real screen content, to answer whether #763's
            // sidebar-interaction fix survives a `RootShellView` rewrite.
            if ProcessInfo.processInfo.arguments.contains("-spike1019") {
                Spike1019RootView()
            } else {
                composition.rootView
            }
        }
    }
}
