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
                routeFactory: composition.routeFactory,
                adProvider: composition.adProvider,
                adGate: composition.adGate,
                monetizationController: composition.monetizationController
            )
            .task {
                // v2.3.7: kick the UMP → ATT → AdMob boot sequence concurrent
                // with the first frame. `BannerSlotView` is honest about
                // deferred state (shows `.failed` if AdMob has not yet
                // initialized) so this never blocks UI rendering.
                await composition.bootMonetization()
            }
        }
    }
}
