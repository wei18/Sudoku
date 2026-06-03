// MinesweeperSettingsViewTests — sentinel coverage for the MS SettingsView.
//
// 2026-06-03 (MS monetization wire Phase 3): SettingsView is no longer the
// "Coming soon" placeholder — it renders Purchases rows when a
// `MonetizationStateController` is injected. These tests confirm both code
// paths construct without crashing.
//
// No snapshot infra this round (defer per Track A precedent).

import SwiftUI
import Testing
@testable import MinesweeperAppComposition
import MinesweeperUI
import MonetizationUI

@MainActor
@Suite struct MinesweeperSettingsViewTests {

    @Test func settingsViewConstructsWithoutController() {
        // No monetization controller → "Coming soon" placeholder branch.
        let view = SettingsView()
        _ = view.body
    }

    @Test func settingsViewConstructsWithPreviewBagController() {
        // Controller from `.preview()` is wired against
        // `minesweeperRemoveAdsProductId` and FakeIAPClient.
        let bag = MinesweeperAppComposition.preview()
        let view = SettingsView(monetizationController: bag.monetizationController)
        _ = view.body
    }
}
