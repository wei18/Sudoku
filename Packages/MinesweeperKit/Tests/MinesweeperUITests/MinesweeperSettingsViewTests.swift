// MinesweeperSettingsViewTests — sentinel coverage for the MS SettingsView.
//
// 2026-06-03 (MS monetization wire Phase 3): SettingsView renders Purchases
// rows when a `MonetizationStateController` is injected. These tests confirm
// both code paths construct without crashing.
//
// #277: SettingsView now also mounts the shared
// `GameShellUI.SettingsAboutVersionRow` / `SettingsStorageSection` (the
// "Coming soon" stub is gone). Construction stays the same via defaults.
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
        // No monetization controller → Purchases section omitted; About +
        // Storage shared sections still render (defaults: version "1.0.0",
        // no-op clearCache).
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
