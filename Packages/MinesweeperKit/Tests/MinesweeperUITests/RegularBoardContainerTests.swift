// RegularBoardContainerTests — #1101: pins the platform default and the
// un-injected `EnvironmentValues` default so a future edit to either can't
// silently drift them apart.

import SwiftUI
import Testing
@testable import MinesweeperUI

@Suite("RegularBoardContainer — platform default (#1101)")
struct RegularBoardContainerTests {

    @Test("platformDefault matches the current platform's board-viewport rule")
    func platformDefaultMatchesPlatform() {
        #if os(iOS)
        #expect(RegularBoardContainer.platformDefault == .fillsColumn)
        #else
        #expect(RegularBoardContainer.platformDefault == .cappedDetailPane)
        #endif
    }

    @Test("un-injected EnvironmentValues defaults to platformDefault")
    func environmentDefaultsToPlatformDefault() {
        #expect(EnvironmentValues().regularBoardContainer == RegularBoardContainer.platformDefault)
    }

    // #1101 round 2: `.fitted` boards top-align under `.fillsColumn` (iPad,
    // so leftover column space lands below the board, not split above/below
    // it) and stay centered under `.cappedDetailPane` (Mac, unchanged).
    @Test("fittedAlignment maps fillsColumn to top and cappedDetailPane to center")
    func fittedAlignmentMapsPerContainer() {
        #expect(MinesweeperBoardView.fittedAlignment(for: .fillsColumn) == .top)
        #expect(MinesweeperBoardView.fittedAlignment(for: .cappedDetailPane) == .center)
    }
}
