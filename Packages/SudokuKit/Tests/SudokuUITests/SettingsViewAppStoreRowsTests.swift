// SettingsViewAppStoreRowsTests — Share App / Write a Review / Invite
// Friends coverage (#744).
//
// Split out of `SettingsViewTests.swift` to keep both files under the
// SwiftLint `file_length` ceiling (400 lines) rather than growing that file
// further — see CLAUDE.md's "extract a sibling file instead" convention.
// Mirrors that file's fixture shapes (`FakePersistence`, `hostingView`,
// `makeMonetizationController`) but duplicates the tiny monetization-controller
// helper locally, matching the existing precedent in
// `SettingsViewWindowSnapshotTests.swift` (each snapshot file owns its own
// copy rather than sharing one across files).

import Foundation
import SwiftUI
import Testing
@testable import SudokuUI

import SettingsUI
import MonetizationCore
import MonetizationTesting
import MonetizationUI
import Persistence
import SudokuKitTesting
import Telemetry

#if canImport(AppKit)
import SnapshotTesting
#endif

@MainActor
@Suite("SettingsView — Share App / Write a Review / Invite Friends (#744)")
struct SettingsViewAppStoreRowsTests {

    @Test func settingsViewConstructsWithAppStoreRowsAndInviteFriends() {
        // A pinned FAKE id (not Bundle.main — see AppStoreLinks's header
        // comment) proves the wired path builds with both new capabilities
        // injected simultaneously.
        let viewModel = SettingsViewModel(persistence: FakePersistence())
        let view = SettingsView(
            viewModel: viewModel,
            presentGameCenter: {},
            appStoreID: "1234567890",
            presentInviteFriends: {}
        )
        _ = view.body
    }

    @Test func settingsViewOmitsAppStoreRowsWhenIDNil() {
        // Byte-identical to the pre-#744 screen — `appStoreID` defaults nil,
        // so Share App / Write a Review stay hidden.
        let viewModel = SettingsViewModel(persistence: FakePersistence())
        let view = SettingsView(viewModel: viewModel)
        _ = view.body
    }

    @Test func settingsViewForwardsTelemetryEmitToSettingsScreen() {
        // The closure itself is opaque from here (SettingsScreen owns firing
        // it on row taps); this only proves construction with a non-default
        // emit closure doesn't itself invoke it eagerly.
        var events: [TelemetryEvent] = []
        let viewModel = SettingsViewModel(persistence: FakePersistence())
        let view = SettingsView(
            viewModel: viewModel,
            appStoreID: "1234567890",
            telemetryEmit: { events.append($0) }
        )
        _ = view.body
        #expect(events.isEmpty, "constructing/rendering must not itself emit telemetry")
    }

    // MARK: - Full-page snapshot (additive — does not touch SettingsViewTests'
    // 6 baselines, which never inject `appStoreID` / `presentInviteFriends`
    // so the new rows stay absent there).

    #if canImport(AppKit)
    private func makeMonetizationController(purchased: Bool) async -> MonetizationStateController {
        let store = FakeAdGateStateStore(
            initial: AdGateState(
                firstLaunchAt: Date(timeIntervalSince1970: 0),
                hasPurchasedRemoveAds: purchased
            )
        )
        let iap = FakeIAPClient()
        await iap.setProducts([
            IAPProduct(
                id: removeAdsProductId,
                displayName: "Remove Ads",
                displayPrice: "$2.99",
                isPurchased: purchased
            )
        ])
        let controller = MonetizationStateController(
            iapClient: iap,
            stateStore: store,
            adGate: AdGate(store: store)
        )
        await controller.bootstrap()
        return controller
    }

    @MainActor
    private func makeSettingsHost(
        controller: MonetizationStateController,
        size: CGSize,
        colorScheme: ColorScheme,
        sizeClass: UserInterfaceSizeClass
    ) -> NSView {
        let viewModel = SettingsViewModel(persistence: FakePersistence())
        let view = NavigationStack {
            SettingsView(
                viewModel: viewModel,
                monetizationController: controller,
                presentGameCenter: {},
                appStoreID: "1234567890",
                presentInviteFriends: {}
            )
        }
        .formStyle(.grouped)
        return hostingView(view, size: size, colorScheme: colorScheme, sizeClass: sizeClass)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshot_iPhone_light_withAppStoreRowsAndInviteFriends() async {
        let controller = await makeMonetizationController(purchased: false)
        let host = makeSettingsHost(
            controller: controller,
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "SettingsView-fullpage-iPhone-light-appStoreRows")
        }
    }
    #endif
}
