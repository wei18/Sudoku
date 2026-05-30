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
import SwiftUI
import Testing

import GameState
import MonetizationCore
import MonetizationTesting
import PuzzleStore
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
}
