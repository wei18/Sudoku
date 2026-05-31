public import SwiftUI
public import MinesweeperUI

// MARK: - MinesweeperAppComposition (skeleton)
//
// Composition root for the Minesweeper app target. PR D placeholder —
// `bootRootView()` returns the hello-world `MinesweeperRootView`. Real
// dependency wiring (PersistenceProtocol with `PrivateCKConfig.minesweeper`,
// MonetizationCore with Minesweeper IAP / Ad unit IDs, Telemetry, etc.)
// lands in follow-up PRs mirroring SudokuKit's `AppComposition.Live`.

public enum MinesweeperAppComposition {
    @MainActor
    public static func bootRootView() -> some View {
        MinesweeperRootView()
    }
}
