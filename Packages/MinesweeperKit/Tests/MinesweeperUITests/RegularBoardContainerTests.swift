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
}
