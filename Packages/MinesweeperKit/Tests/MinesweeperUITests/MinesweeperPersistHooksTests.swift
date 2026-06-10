// MinesweeperGameViewModel persistence hooks (#455 step 4) — pause / terminal
// save points + the idle guard, against the fake gateway. The view-lifecycle
// triggers (scenePhase / onDisappear) call the same `persistCurrentState()`.

import Foundation
import Testing
import MinesweeperEngine
import MinesweeperGameState
import MinesweeperPersistence
import Persistence
import PersistenceTesting
@testable import MinesweeperUI

@MainActor
@Suite("MinesweeperGameViewModel — persistence hooks (#455)")
struct MinesweeperPersistHooksTests {

    // nonisolated: referenced from the store's @Sendable clock closure.
    private nonisolated static let fixedDate = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeVM(
        gateway: FakePrivateCKGateway,
        recordName: String = "practice-beginner"
    ) -> MinesweeperGameViewModel {
        MinesweeperGameViewModel(
            difficulty: .beginner,
            seed: 7,
            mode: .practice,
            store: MinesweeperSavedGameStore(gateway: gateway, clock: { Self.fixedDate }),
            recordName: recordName
        )
    }

    @Test
    func pausePersistsInProgressSave() async throws {
        let gateway = FakePrivateCKGateway()
        let vm = makeVM(gateway: gateway)
        await vm.reveal(row: 4, col: 4)
        await vm.pause()

        let payload = try #require(await gateway.fetch(recordName: "practice-beginner"))
        #expect(payload.fields["status"] == .string("inProgress"))
        #expect(payload.fields["mode"] == .string("practice"))
    }

    @Test
    func idleBoardNeverPersists() async {
        let gateway = FakePrivateCKGateway()
        let vm = makeVM(gateway: gateway)
        // No reveal — the board is still .idle; a save here would occupy the
        // resume pill with a zero-information record.
        await vm.persistCurrentState()
        #expect(await gateway.recordCount() == 0)
    }

    @Test
    func terminalRevealPersistsCompleted() async throws {
        let gateway = FakePrivateCKGateway()
        let vm = makeVM(gateway: gateway)
        await vm.reveal(row: 4, col: 4)

        // Reveal a known mine → .lost → the terminal hook saves "completed",
        // which removes the record from the resume-candidate set.
        outer: for row in 0..<vm.rows {
            for col in 0..<vm.columns {
                let cell = vm.cell(row: row, col: col)
                if cell.isMine, cell.state == .hidden {
                    await vm.reveal(row: row, col: col)
                    break outer
                }
            }
        }
        #expect(vm.status == .lost)

        let payload = try #require(await gateway.fetch(recordName: "practice-beginner"))
        #expect(payload.fields["status"] == .string("completed"))
        let store = MinesweeperSavedGameStore(gateway: gateway, clock: { Self.fixedDate })
        #expect(try await store.latestInProgress() == nil)
    }

    @Test
    func recordNameDerivationMatchesSchemes() {
        #expect(
            MinesweeperSavedGameStore.recordName(
                mode: .daily, difficulty: .beginner, now: Self.fixedDate
            ) == "daily-\(UTCDay.string(from: Self.fixedDate))-beginner"
        )
        #expect(
            MinesweeperSavedGameStore.recordName(mode: .practice, difficulty: .expert)
                == "practice-expert"
        )
    }
}
