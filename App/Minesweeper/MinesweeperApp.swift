import SwiftUI
import MinesweeperAppComposition

// Standard navigation wire — `MinesweeperAppComposition.live()` uses
// `makeGameApp` (GameAppKit) to build the shared GameRoot + GameHomeView +
// ResumePill + ATT sheet + GC alert. LiveRouteFactory handles board /
// settings destinations. Persistence, monetization, Daily and Practice
// are all wired live (shipped, v2.6). (#572 SDD-005 Pillar C)

@main
struct MinesweeperApp: App {
    private let composition = MinesweeperAppComposition.live()

    var body: some Scene {
        WindowGroup {
            composition.rootView
        }
    }
}
