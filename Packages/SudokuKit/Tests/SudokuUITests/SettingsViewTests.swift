// SettingsViewTests — behavior + full-page snapshots.
//
// Snapshot coverage added per #181: prior snapshot coverage was narrow
// (`SettingsIAPRowTests` only). Full-page Form chrome — including the
// Option A redesign (Purchases section, grouped-list capsules, leading
// SF Symbols) — needs `NavigationStack { ... }.formStyle(.grouped)` to
// match production styling (RouteFactory pushes SettingsView onto
// `NavigationStackHost`).

import Foundation
import SwiftUI
import Testing
@testable import SudokuUI

import MonetizationCore
import MonetizationTesting
import Persistence
import SudokuEngine
import SudokuKitTesting

#if canImport(AppKit)
import SnapshotTesting
#endif

@MainActor
@Suite("SettingsView — behavior")
struct SettingsViewTests {

    @Test func generatorVersionRow_displaysV1() {
        let viewModel = SettingsViewModel(
            generatorVersion: .v1,
            persistence: FakePersistence()
        )
        // Asserts the value passed into the SettingsView label matches the
        // current GeneratorVersion.v1.rawValue. The View renders this via
        // `LabeledContent("Generator", value: viewModel.generatorVersion.rawValue)`.
        #expect(viewModel.generatorVersion.rawValue == "v1")
    }

    @Test func clearCache_deletesResumeCandidateAndSetsConfirmation() async {
        let candidate = SavedGameSummary(
            recordName: "saved-easy",
            puzzleId: "2026-05-19-easy",
            mode: .daily,
            difficulty: .easy,
            lastModifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            elapsedSeconds: 120,
            status: "inProgress",
            generatorVersion: 1
        )
        let fake = FakePersistence()
        await fake.setResumeCandidate(candidate)
        let viewModel = SettingsViewModel(persistence: fake)
        await viewModel.bootstrap()
        #expect(viewModel.resumeCandidate?.recordName == "saved-easy")

        await viewModel.clearCache()

        let ops = await fake.operations
        #expect(ops.contains(.deleteAbandoned(recordName: "saved-easy")))
        #expect(viewModel.resumeCandidate == nil)
        #expect(viewModel.clearCacheConfirmation == "Cache cleared")
    }

    @Test func clearCache_withNoCandidate_stillSetsConfirmation() async {
        let viewModel = SettingsViewModel(persistence: FakePersistence())
        await viewModel.bootstrap()
        await viewModel.clearCache()
        #expect(viewModel.clearCacheConfirmation == "Cache cleared")
    }

    // MARK: - Full-page snapshots (closes #181 test-coverage half)
    //
    // Wraps the SettingsView in `NavigationStack { ... }.formStyle(.grouped)`
    // so the snapshot chrome matches production (`RouteFactory` pushes
    // SettingsView onto `NavigationStackHost`). Pre-#181 component-level
    // snapshots in SettingsIAPRowTests render as plain-list — they miss
    // the Option A grouped-capsule visual delta.

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
        purchased: Bool,
        controller: MonetizationStateController,
        size: CGSize,
        colorScheme: ColorScheme,
        sizeClass: UserInterfaceSizeClass
    ) -> NSView {
        let viewModel = SettingsViewModel(persistence: FakePersistence())
        let view = NavigationStack {
            SettingsView(viewModel: viewModel, monetizationController: controller)
        }
        .formStyle(.grouped)
        return hostingView(view, size: size, colorScheme: colorScheme, sizeClass: sizeClass)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshot_iPhone_light_unpurchased() async {
        let controller = await makeMonetizationController(purchased: false)
        let host = makeSettingsHost(
            purchased: false,
            controller: controller,
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "SettingsView-fullpage-iPhone-light-unpurchased")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshot_iPhone_light_purchased() async {
        let controller = await makeMonetizationController(purchased: true)
        let host = makeSettingsHost(
            purchased: true,
            controller: controller,
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "SettingsView-fullpage-iPhone-light-purchased")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshot_iPhone_dark_unpurchased() async {
        let controller = await makeMonetizationController(purchased: false)
        let host = makeSettingsHost(
            purchased: false,
            controller: controller,
            size: SnapshotLayouts.iPhone,
            colorScheme: .dark,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "SettingsView-fullpage-iPhone-dark-unpurchased")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshot_iPhone_dark_purchased() async {
        let controller = await makeMonetizationController(purchased: true)
        let host = makeSettingsHost(
            purchased: true,
            controller: controller,
            size: SnapshotLayouts.iPhone,
            colorScheme: .dark,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "SettingsView-fullpage-iPhone-dark-purchased")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshot_mac_light_unpurchased() async {
        let controller = await makeMonetizationController(purchased: false)
        let host = makeSettingsHost(
            purchased: false,
            controller: controller,
            size: SnapshotLayouts.mac,
            colorScheme: .light,
            sizeClass: .regular
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "SettingsView-fullpage-mac-light-unpurchased")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshot_mac_light_purchased() async {
        let controller = await makeMonetizationController(purchased: true)
        let host = makeSettingsHost(
            purchased: true,
            controller: controller,
            size: SnapshotLayouts.mac,
            colorScheme: .light,
            sizeClass: .regular
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "SettingsView-fullpage-mac-light-purchased")
        }
    }
    #endif
}
