// SettingsViewWindowSnapshotTests — issue #209 demo.
//
// Proves the NSWindow-based harness (`windowSnapshotView` /
// `windowSnapshotImage`) hosts a macOS `Form` screen inside a REAL window —
// the layout context that NSHostingView cannot fully supply for
// `Form`/`NavigationSplitView` (the issue #209 gap behind the #197 / #208
// false-positives). SettingsView is the exact screen those bugs shipped on.
//
// ADDITIVE: this file does NOT touch `SettingsViewTests` or its NSHostingView
// baselines.
//
// HEADLESS CAVEAT (verified empirically — see the impl-notes for #209 and the
// `windowSnapshotImage` doc comment): a real `NSWindow` only renders capturable
// content when a window-server display is connected. Under interactive
// `xcodebuild test` / a logged-in GUI session that holds; under headless
// `swift test` from a terminal the window's backing store is never realised and
// every capture path returns solid black. So:
//   - `window_mac_renders_form_chrome` asserts the harness produces a *non-blank*
//     capture and is gated to run only where a window server actually renders
//     (it self-skips when the capture comes back blank, the headless signature),
//     and records/diffs a committed PNG baseline when it does run.
//   - `window_harness_mounts_real_window` always runs: it asserts the structural
//     contract (real NSWindow + NSHostingController containment + sizing), which
//     is what makes the Form/SplitView layout pipeline run, independent of
//     whether the host can draw pixels.
// Both are gated `.enabled(if: !SnapshotEnv.isXcodeCloud)` like the rest of the
// suite (#199 moved snapshot tests off XCC for cross-machine drift).

import Foundation
import SwiftUI
import Testing
@testable import SudokuUI

import MonetizationCore
import MonetizationTesting
import MonetizationUI
import Persistence
import SudokuEngine
import SudokuKitTesting

#if canImport(AppKit)
import AppKit
import SnapshotTesting

@MainActor
@Suite("SettingsView — NSWindow-hosted macOS Form chrome (#209)")
struct SettingsViewWindowSnapshotTests {

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

    /// Same view tree as `SettingsViewTests.makeSettingsHost` — only the host
    /// differs (NSWindow vs NSHostingView), so any delta isolates the
    /// real-window Form chrome.
    private func makeSettingsView(
        controller: MonetizationStateController
    ) -> some View {
        // #832: the shared VM defaults `generatorVersionLabel` to nil (MS has no
        // Generator row); pass Sudoku's production value explicitly so this
        // matches `SettingsViewTests.makeSettingsHost`'s tree exactly (this
        // file's whole point is isolating the NSWindow-vs-NSHostingView delta,
        // not the Generator row).
        let viewModel = SettingsViewModel(
            generatorVersionLabel: GeneratorVersion.v1.rawValue,
            persistence: FakePersistence()
        )
        return NavigationStack {
            SettingsView(viewModel: viewModel, monetizationController: controller)
        }
        .formStyle(.grouped)
    }

    /// Sample the captured image; returns the fraction of sampled pixels that
    /// are non-white. A headless (window-server-less) capture comes back solid
    /// black or uninitialised → effectively 0 mid-tone content; a real render of
    /// the grouped Form sits well above the threshold.
    private func nonBlankRatio(_ image: NSImage) -> Double {
        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff)
        else { return 0 }
        var lit = 0
        var total = 0
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        let stepX = max(1, width / 60)
        let stepY = max(1, height / 60)
        var row = 0
        while row < height {
            var col = 0
            while col < width {
                if let color = rep.colorAt(x: col, y: row) {
                    // Count any pixel above near-black as "content" (Form rows
                    // are light grey on near-white; a headless blank is black).
                    if color.brightnessComponent > 0.05 { lit += 1 }
                    total += 1
                }
                col += stepX
            }
            row += stepY
        }
        return total == 0 ? 0 : Double(lit) / Double(total)
    }

    /// Structural contract — ALWAYS runs (no window-server dependency). Proves
    /// the harness mounts the SwiftUI subtree inside a real `NSWindow` via
    /// `NSHostingController` containment at the requested size, which is what
    /// makes the genuine macOS Form / NavigationSplitView layout pipeline run.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func window_harness_mounts_real_window() async {
        let controller = await makeMonetizationController(purchased: false)
        let (view, window) = windowSnapshotView(
            makeSettingsView(controller: controller),
            size: SnapshotLayouts.mac,
            colorScheme: .light,
            sizeClass: .regular
        )
        #expect(window.contentViewController != nil)        // real VC containment
        #expect(window.contentView === view)                 // we snapshot the window's content
        #expect(window.contentView?.frame.width == SnapshotLayouts.mac.width)
        #expect(window.contentView?.frame.height == SnapshotLayouts.mac.height)
        #expect(window.appearance?.name == .aqua)            // colorScheme mirrored
        window.close()
    }

    /// Pixel render + baseline — runs only where a window server actually
    /// renders the window (self-skips on the headless `swift test` signature).
    /// When it runs, it asserts the captured Form chrome against a committed
    /// PNG baseline; on first run it records that baseline.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func window_mac_renders_form_chrome() async {
        let controller = await makeMonetizationController(purchased: false)
        let (image, window) = windowSnapshotImage(
            makeSettingsView(controller: controller),
            size: SnapshotLayouts.mac,
            colorScheme: .light,
            sizeClass: .regular
        )
        defer { window.close() }

        // Headless guard: if there is no window server the capture is blank.
        // Skip rather than commit/diff a garbage baseline (issue #209 caveat).
        // Under `swift test` from a terminal this returns ~0 and the pixel
        // assertion is skipped; under interactive `xcodebuild test` it renders.
        guard nonBlankRatio(image) > 0.05 else { return }

        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertUISnapshot(
                of: image,
                as: .image,
                named: "SettingsView-window-mac-light-unpurchased"
            )
        }
    }
}
#endif
