// swiftlint:disable identifier_name
//
// MinesweeperPersonalRecordSubmitTests — #699: submit-on-win wiring for the
// MS-specific personal-record store, sitting right beside the Game Center
// submit in `MinesweeperGameViewModel.submitDailyTimeIfWon()`.
//
// Drives `MinesweeperGameViewModel` to a real `.won` state (mirrors
// `MinesweeperGameCenterSubmitTests.driveToWin`) with an injected
// `MinesweeperPersonalRecordStore` over `FakePrivateCKGateway`, and asserts
// the personal best is recorded exactly once, only for daily-mode wins, and
// that a failed write never breaks the win.

import Foundation
import Testing
@testable import MinesweeperUI
import MinesweeperEngine
import MinesweeperGameState
import Persistence
import PersistenceTesting
import Telemetry
@testable import MinesweeperPersistence

@MainActor
@Suite("MinesweeperGameViewModel — personal-record submit-on-win (#699)")
struct MinesweeperPersonalRecordSubmitTests {

    /// Drive `vm` to a win by revealing every non-mine cell (identical
    /// helper to `MinesweeperGameCenterSubmitTests.driveToWin`).
    private func driveToWin(_ vm: MinesweeperGameViewModel) async {
        await vm.reveal(row: 0, col: 0)
        var progressed = true
        while vm.status == .playing && progressed {
            progressed = false
            for r in 0..<vm.rows {
                for c in 0..<vm.columns {
                    let cell = vm.cell(row: r, col: c)
                    if !cell.isMine && cell.state != .revealed {
                        await vm.reveal(row: r, col: c)
                        progressed = true
                        if vm.status != .playing { return }
                    }
                }
            }
        }
    }

    private func makeStore() -> (MinesweeperPersonalRecordStore, FakePrivateCKGateway) {
        let gateway = FakePrivateCKGateway()
        let store = MinesweeperPersonalRecordStore(gateway: gateway)
        return (store, gateway)
    }

    @Test func dailyWinRecordsPersonalBestExactlyOnce() async throws {
        let (store, _) = makeStore()
        let recordName = MinesweeperSavedGameStore.recordName(mode: .daily, difficulty: .beginner)
        let vm = MinesweeperGameViewModel(
            difficulty: .beginner,
            seed: 42,
            mode: .daily,
            recordName: recordName,
            personalRecordStore: store
        )

        await driveToWin(vm)
        #expect(vm.status == .won)

        let record = try await store.fetch(modeRaw: "daily", difficulty: .beginner)
        #expect(record.completedCount == 1)
        #expect(record.bestTimeSeconds == vm.elapsedSeconds)
        #expect(record.completedPuzzleIds == [recordName])
    }

    @Test func practiceWinNeverRecordsPersonalBest() async throws {
        // #329-style gate: mirrors the GC daily-only gate — a Practice solve
        // must not write the personal-best record either.
        let (store, _) = makeStore()
        let vm = MinesweeperGameViewModel(
            difficulty: .beginner,
            seed: 42,
            mode: .practice,
            personalRecordStore: store
        )

        await driveToWin(vm)
        #expect(vm.status == .won)

        let record = try await store.fetch(modeRaw: "practice", difficulty: .beginner)
        #expect(record.completedCount == 0)
    }

    @Test func losingNeverRecordsPersonalBest() async throws {
        let (store, _) = makeStore()
        let vm = MinesweeperGameViewModel(
            difficulty: .beginner,
            seed: 13,
            mode: .daily,
            personalRecordStore: store
        )
        await vm.reveal(row: 0, col: 0)
        var mine: (Int, Int)?
        outer: for r in 0..<vm.rows {
            for c in 0..<vm.columns where vm.cell(row: r, col: c).isMine {
                mine = (r, c)
                break outer
            }
        }
        if let (mr, mc) = mine {
            await vm.reveal(row: mr, col: mc)
        }
        #expect(vm.status == .lost)

        let record = try await store.fetch(modeRaw: "daily", difficulty: .beginner)
        #expect(record.completedCount == 0)
    }

    @Test func nilPersonalRecordStoreSubmitsNothing() async throws {
        // MVP / preview / non-#699 callsite: nil store → no-op, win still
        // completes normally (mirrors `noGameCenterClientSubmitsNothing`).
        let vm = MinesweeperGameViewModel(difficulty: .beginner, seed: 42, mode: .daily)
        await driveToWin(vm)
        #expect(vm.status == .won)
    }

    @Test func writeFailureIsSwallowedAndDoesNotBreakWin() async throws {
        let vm = MinesweeperGameViewModel(
            difficulty: .beginner,
            seed: 42,
            mode: .daily,
            errorReporter: NoopErrorReporter(),
            personalRecordStore: MinesweeperPersonalRecordStore(gateway: AlwaysThrowingGateway())
        )

        await driveToWin(vm)

        // Gameplay is unaffected by the swallowed write error.
        #expect(vm.status == .won)
    }
}

// MARK: - Fakes

/// Gateway that throws on every op — used to prove a failed personal-record
/// write funnels through `errorReporter` without ever interrupting the win.
private actor AlwaysThrowingGateway: PrivateCKGateway {
    func provisionZone() async throws {}
    func installSubscriptionIfNeeded() async throws {}
    func fetch(recordName: String) async throws -> RecordPayload? {
        throw PersistenceError.underlying(domain: "Test", code: 1, description: "always throws")
    }
    func save(_ payload: RecordPayload, policy: RecordSavePolicy) async throws {
        throw PersistenceError.underlying(domain: "Test", code: 1, description: "always throws")
    }
    func delete(recordName: String) async throws {}
    func query(_ predicate: RecordPredicate) async throws -> [RecordPayload] { [] }
}

// swiftlint:enable identifier_name
