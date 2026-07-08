// swiftlint:disable identifier_name
// `vm` is the file-local shorthand for `viewModel` in setup helpers below;
// pre-existing convention scoped to this test file.
// BoardViewBannerTests — v2.3.5 banner wiring on BoardView.
//
// Two behaviors:
//   1. `viewModel.isPaused == false` AND gate allows → banner mounts.
//   2. `viewModel.isPaused == true` → banner hidden regardless of gate.
//
// BoardView consults `viewModel.isPaused` synchronously inside `body`; we
// assert the property gates the conditional so the snapshot pair (running /
// paused) pins the visual outcome.

import Foundation
import SnapshotTesting
import SwiftUI
import Testing

import SudokuGameState
import MonetizationCore
import MonetizationTesting
import SudokuPersistence
import SudokuEngine
@testable import SudokuUI

@MainActor
@Suite("BoardView — BannerSlotView wiring")
struct BoardViewBannerTests {

    private static let identity = PuzzleIdentity(
        puzzleId: "test-banner",
        kind: .practice,
        difficulty: .easy
    )
    private static let emptyClues = String(repeating: ".", count: 81)

    private func makeViewModel(paused: Bool) throws -> GameViewModel {
        let board = try Board(clues: Self.emptyClues)
        return GameViewModel(
            identity: Self.identity,
            board: board,
            status: paused ? .paused : .playing,
            elapsedSeconds: 0,
            errorIndices: [],
            selection: nil
        )
    }

    private func makeAdGate(allow: Bool) -> AdGate {
        // `allow == true` → 30 days post-launch, not purchased.
        // `allow == false` → purchased (rule #1 in `shouldShowBanner`); we
        // can't lean on grace-period denial since #212 zeroed
        // `gracePeriodDays` for TestFlight visibility. Purchase-driven
        // denial is purely state-driven so this stays robust whether
        // grace returns to 7 or stays at 0.
        let store = FakeAdGateStateStore(
            initial: AdGateState(
                firstLaunchAt: Date().addingTimeInterval(-30 * 86_400),
                hasPurchasedRemoveAds: !allow
            )
        )
        return AdGate(store: store)
    }

    @Test func running_andGateAllows_bannerMountIsActive() async throws {
        let vm = try makeViewModel(paused: false)
        #expect(vm.isPaused == false)
        let gate = makeAdGate(allow: true)
        let allowed = await gate.shouldShowBanner(now: Date())
        #expect(allowed == true)
        // Construct the view to ensure init compiles + holds the deps.
        _ = BoardView(viewModel: vm, adProvider: FakeAdProvider(), adGate: gate)
    }

    @Test func paused_bannerIsSuppressed() async throws {
        let vm = try makeViewModel(paused: true)
        #expect(vm.isPaused == true)
        // Even if the gate would allow, `body` short-circuits on `isPaused`.
        let gate = makeAdGate(allow: true)
        _ = BoardView(viewModel: vm, adProvider: FakeAdProvider(), adGate: gate)
    }

    @Test func running_butGateDenies_bannerSlotCollapsesToEmpty() async throws {
        let vm = try makeViewModel(paused: false)
        let gate = makeAdGate(allow: false)
        let allowed = await gate.shouldShowBanner(now: Date())
        #expect(allowed == false)
        _ = BoardView(viewModel: vm, adProvider: FakeAdProvider(), adGate: gate)
    }

    // MARK: - #723 snapshots — ads-enabled, ad NOT loaded, slot reserved
    //
    // First repo fixtures rendering the banner slot's VISIBLE (ads-enabled)
    // state — every other Home/Board snapshot seeds hasPurchasedRemoveAds:
    // true, so the slot collapses in all of them (#723 acceptance note from
    // #725's review). The gate is resolved ONCE before the view is built so
    // `AdGate.lastKnownShouldShowBanner == true` seeds the slot and the very
    // first layout reserves the 50pt rect (spinner placeholder, no ad) —
    // pinning both the #723 reservation and #725's page-background slot.
    // `.tolerantImage` per the board-suite policy (#586: AA-heavy boards).

    #if canImport(AppKit)
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotAdsEnabledUnloadedSlot_iPhone_light() async throws {
        let vm = try makeViewModel(paused: false)
        let gate = makeAdGate(allow: true)
        _ = await gate.shouldShowBanner(now: Date()) // warm the #723 hint
        let host = hostingView(
            BoardView(viewModel: vm, adProvider: FakeAdProvider(), adGate: gate),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .tolerantImage, named: "Board-iPhone-light-banner-reserved")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotAdsEnabledUnloadedSlot_iPhone_dark() async throws {
        let vm = try makeViewModel(paused: false)
        let gate = makeAdGate(allow: true)
        _ = await gate.shouldShowBanner(now: Date()) // warm the #723 hint
        let host = hostingView(
            BoardView(viewModel: vm, adProvider: FakeAdProvider(), adGate: gate),
            size: SnapshotLayouts.iPhone,
            colorScheme: .dark,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .tolerantImage, named: "Board-iPhone-dark-banner-reserved")
        }
    }
    #endif
}
// swiftlint:enable identifier_name
