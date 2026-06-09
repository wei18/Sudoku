// swiftlint:disable identifier_name
//
// MinesweeperRootViewModelTests — launch-time Game Center auth handshake (#313).
//
// Mirrors Sudoku's RootViewModel auth block (`SudokuUI.RootViewModel.bootstrap`
// → `gameCenter.authenticate()`). Asserts:
//   - success: `bootstrap()` stores the authenticated state.
//   - failure: a thrown auth error degrades to `.unauthenticated` (never
//     crashes / blocks), AND funnels through `ErrorReporter` as
//     `.gameCenterUnauthenticated`.
//   - idempotency: a second `bootstrap()` does not re-invoke GameKit auth.

import Foundation
import Testing
@testable import MinesweeperUI
import GameCenterClient
import GameCenterTesting
import PersistenceTesting
import Telemetry

@MainActor
@Suite("MinesweeperRootViewModel — launch GC auth handshake (#313)")
struct MinesweeperRootViewModelTests {

    @Test func bootstrapAuthenticatesAndStoresState() async {
        let fake = FakeGameCenterClient()
        let player = PlayerSummary(teamPlayerId: "P0001", displayName: "Sweeper")
        await fake.setAuthResult(.success(.authenticated(player)))

        let vm = MinesweeperRootViewModel(gameCenter: fake, persistence: FakePersistence())
        await vm.bootstrap()

        #expect(vm.authState == .authenticated(player))
        let ops = await fake.operations
        #expect(ops == [.authenticate])
    }

    @Test func authFailureDegradesToUnauthenticatedAndFunnels() async {
        let fake = FakeGameCenterClient()
        await fake.setAuthResult(.failure(.notAuthenticated))
        let reporter = FakeErrorReporter()

        let vm = MinesweeperRootViewModel(gameCenter: fake, persistence: FakePersistence(), errorReporter: reporter)
        // Must not crash / throw — GC is optional and never blocks launch.
        await vm.bootstrap()

        #expect(vm.authState == .unauthenticated)
        let received = await reporter.received
        #expect(received.count == 1)
        #expect(received.first?.error == .gameCenterUnauthenticated)
        #expect(received.first?.source == "MinesweeperRootViewModel.bootstrap.authenticate")
    }

    @Test func bootstrapIsIdempotent() async {
        let fake = FakeGameCenterClient()
        let vm = MinesweeperRootViewModel(gameCenter: fake, persistence: FakePersistence())

        await vm.bootstrap()
        await vm.bootstrap()

        let ops = await fake.operations
        // Auth runs exactly once despite two bootstrap calls — a `.task`
        // re-entry must not re-trigger GameKit auth.
        #expect(ops.filter { $0 == .authenticate }.count == 1)
        #expect(vm.hasBootstrapped == true)
    }
}

// swiftlint:enable identifier_name
