// RegularBoardContainerTests — MS-specific `fittedAlignment` mapping.
//
// The platform-default / un-injected-EnvironmentValues pins moved to
// GameShellKit's `RegularBoardContainerTests` (#1105) alongside the
// `RegularBoardContainer` type itself; only the MS-specific mapping below
// stays here.

import GameShellUI
import SwiftUI
import Testing
@testable import MinesweeperUI

@Suite("MinesweeperBoardView.fittedAlignment — per container (#1101)")
struct RegularBoardContainerTests {

    // #1101 round 2: `.fitted` boards top-align under `.fillsColumn` (iPad,
    // so leftover column space lands below the board, not split above/below
    // it) and stay centered under `.cappedDetailPane` (Mac, unchanged).
    @Test("fittedAlignment maps fillsColumn to top and cappedDetailPane to center")
    func fittedAlignmentMapsPerContainer() {
        #expect(MinesweeperBoardView.fittedAlignment(for: .fillsColumn) == .top)
        #expect(MinesweeperBoardView.fittedAlignment(for: .cappedDetailPane) == .center)
    }
}
