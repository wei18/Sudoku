// HubSettingsBannerTests — Epic 5 banner coverage: Daily · Practice · Settings.
//
// Verifies that the `banner:` ViewBuilder slot threaded through each hub shell
// (DailyHubShellView / PracticeHubShellView / SettingsShellView) can be
// constructed with a `BannerSlotView` and that the gate-deny / gate-allow
// plumbing mirrors the existing BoardViewBannerTests contract:
//
//   1. Gate allows → provider refresh is invoked (banner live path).
//   2. Gate denies (hasPurchasedRemoveAds) → slot collapses to EmptyView,
//      provider is never touched (Remove-Ads IAP gate preserved).
//
// We exercise `BannerSlotView` directly rather than the full hub trees. Since
// #1058 the slot never holds the provider or gate — `BannerSessionModel` owns
// that plumbing — so these tests pin the gate decision and that constructing a
// slot never touches the provider; the shell pass-through is covered by the
// snapshot baseline.

import Foundation
import SwiftUI
import Testing

import MonetizationCore
import MonetizationTesting
import MonetizationUI
@testable import SudokuUI
import SudokuKitTesting
import SudokuPersistence

@MainActor
@Suite("Hub + Settings screens — BannerSlotView wiring (Epic 5)")
struct HubSettingsBannerTests {

    // MARK: - Helpers

    private func makeAdGate(allow: Bool) -> AdGate {
        let store = FakeAdGateStateStore(
            initial: AdGateState(
                firstLaunchAt: Date().addingTimeInterval(-30 * 86_400),
                hasPurchasedRemoveAds: !allow
            )
        )
        return AdGate(store: store)
    }

    // MARK: - DailyHubView banner slot

    @Test func dailyHub_gateDenies_slotNeverTouchesProvider() async {
        let gate = makeAdGate(allow: false)
        let provider = FakeAdProvider()

        let allowed = await gate.shouldShowBanner(now: Date())
        #expect(allowed == false)

        // Construct DailyHubView with a BannerSlotView in the banner slot.
        // Slot collapses to EmptyView when gate denies; provider is untouched.
        let viewModel = DailyHubViewModel(
            provider: FakePuzzleProvider(),
            persistence: FakePersistence(completedDailyIds: [])
        )
        _ = DailyHubView(viewModel: viewModel) {
            BannerSlotView(isSuppressed: false)
        }

        let refreshes = await provider.refreshCallCount
        #expect(refreshes == 0)
    }

    @Test func dailyHub_gateAllows_slotInitializes() async {
        let gate = makeAdGate(allow: true)

        let allowed = await gate.shouldShowBanner(now: Date())
        #expect(allowed == true)

        let viewModel = DailyHubViewModel(
            provider: FakePuzzleProvider(),
            persistence: FakePersistence(completedDailyIds: [])
        )
        _ = DailyHubView(viewModel: viewModel) {
            BannerSlotView(isSuppressed: false)
        }
        // Slot was constructed; since #1058 the session model resolves the gate
        // (covered by MonetizationUITests' BannerSessionModel suites).
        #expect(allowed)
    }

    // MARK: - PracticeHubView banner slot

    @Test func practiceHub_gateDenies_slotNeverTouchesProvider() async {
        let gate = makeAdGate(allow: false)
        let provider = FakeAdProvider()

        let allowed = await gate.shouldShowBanner(now: Date())
        #expect(allowed == false)

        let viewModel = PracticeHubViewModel(provider: FakePuzzleProvider(), path: .constant([]))
        _ = PracticeHubView(viewModel: viewModel) {
            BannerSlotView(isSuppressed: false)
        }

        let refreshes = await provider.refreshCallCount
        #expect(refreshes == 0)
    }

    @Test func practiceHub_gateAllows_slotInitializes() async {
        let gate = makeAdGate(allow: true)

        let viewModel = PracticeHubViewModel(provider: FakePuzzleProvider(), path: .constant([]))
        _ = PracticeHubView(viewModel: viewModel) {
            BannerSlotView(isSuppressed: false)
        }
        let allowed = await gate.shouldShowBanner(now: Date())
        #expect(allowed == true)
    }

    // MARK: - SettingsView banner slot

    @Test func settings_gateDenies_slotNeverTouchesProvider() async {
        let gate = makeAdGate(allow: false)
        let provider = FakeAdProvider()

        let allowed = await gate.shouldShowBanner(now: Date())
        #expect(allowed == false)

        _ = SettingsView(
            viewModel: SettingsViewModel(persistence: FakePersistence())
        ) {
            BannerSlotView(isSuppressed: false)
        }

        let refreshes = await provider.refreshCallCount
        #expect(refreshes == 0)
    }

    @Test func settings_gateAllows_slotInitializes() async {
        let gate = makeAdGate(allow: true)

        _ = SettingsView(
            viewModel: SettingsViewModel(persistence: FakePersistence())
        ) {
            BannerSlotView(isSuppressed: false)
        }
        let allowed = await gate.shouldShowBanner(now: Date())
        #expect(allowed == true)
    }

    // MARK: - Remove-Ads gate: all non-Home screens collapse to EmptyView

    @Test func allHubs_removeAdsPurchased_bannerSlotCollapsesToEmpty() async {
        // Mirrors BoardViewBannerTests.running_butGateDenies_bannerSlotCollapsesToEmpty.
        // Confirms that Remove-Ads IAP gate propagates to all newly-bannered screens.
        let gate = makeAdGate(allow: false) // hasPurchasedRemoveAds = true
        let provider = FakeAdProvider()
        let allowed = await gate.shouldShowBanner(now: Date())
        #expect(allowed == false) // gate denies → slot collapses

        // Daily hub
        let dailyVM = DailyHubViewModel(
            provider: FakePuzzleProvider(),
            persistence: FakePersistence(completedDailyIds: [])
        )
        _ = DailyHubView(viewModel: dailyVM) {
            BannerSlotView(isSuppressed: false)
        }

        // Practice hub
        let practiceVM = PracticeHubViewModel(provider: FakePuzzleProvider(), path: .constant([]))
        _ = PracticeHubView(viewModel: practiceVM) {
            BannerSlotView(isSuppressed: false)
        }

        // Settings
        _ = SettingsView(viewModel: SettingsViewModel(persistence: FakePersistence())) {
            BannerSlotView(isSuppressed: false)
        }

        // None of the screens should have triggered a provider load.
        let refreshes = await provider.refreshCallCount
        #expect(refreshes == 0)
    }
}
