// swiftlint:disable identifier_name
//
// MinesweeperPersonalRecordSubmitTests — #699/#705: submit-on-win wiring for
// the MS-specific personal-record store, sitting right beside the Game
// Center submit in `MinesweeperGameViewModel.submitWinIfWon()`.
//
// Drives `MinesweeperGameViewModel` to a real `.won` state (mirrors
// `MinesweeperGameCenterSubmitTests.driveToWin`) with an injected
// `MinesweeperPersonalRecordStore` over `FakePrivateCKGateway`, and asserts
// the personal best is recorded exactly once for BOTH daily- and
// practice-mode wins (#705 widened the #699 daily-only launch scope), using
// the mode-appropriate puzzleId, and that a failed write never breaks the win.

import Foundation
import Testing
@testable import MinesweeperUI
import MinesweeperEngine
import MinesweeperGameState
import GameCenterClient
import GameCenterTesting
import Persistence
import PersistenceTesting
import Telemetry
@testable import MinesweeperPersistence

@MainActor
@Suite("MinesweeperGameViewModel — personal-record submit-on-win (#699/#705)")
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

    @Test func practiceWinRecordsPersonalBestWithSeedDerivedPuzzleId() async throws {
        // #705: widened from the #699 daily-only launch scope. The dedup
        // puzzleId is derived from the board's own generation seed (NOT the
        // singleton `practice-{difficulty}` recordName, which would collapse
        // every practice win into one entry) — see MinesweeperPracticeIdentity.
        let (store, _) = makeStore()
        let seed: UInt64 = 42
        let vm = MinesweeperGameViewModel(
            difficulty: .beginner,
            seed: seed,
            mode: .practice,
            personalRecordStore: store
        )

        await driveToWin(vm)
        #expect(vm.status == .won)

        let record = try await store.fetch(modeRaw: "practice", difficulty: .beginner)
        #expect(record.completedCount == 1)
        #expect(record.bestTimeSeconds == vm.elapsedSeconds)
        let expectedPuzzleId = MinesweeperPracticeIdentity.puzzleId(seed: seed, difficulty: .beginner)
        #expect(record.completedPuzzleIds == [expectedPuzzleId])
    }

    @Test func distinctPracticeGamesOfSameDifficultyBothCount() async throws {
        // Two DIFFERENT practice games (different seeds) at the same
        // difficulty must both count — proves the dedup key is per-game, not
        // per-difficulty (which is what the old singleton recordName would
        // have collapsed to).
        let (store, _) = makeStore()
        let vm1 = MinesweeperGameViewModel(
            difficulty: .beginner, seed: 1, mode: .practice, personalRecordStore: store
        )
        await driveToWin(vm1)
        #expect(vm1.status == .won)

        let vm2 = MinesweeperGameViewModel(
            difficulty: .beginner, seed: 2, mode: .practice, personalRecordStore: store
        )
        await driveToWin(vm2)
        #expect(vm2.status == .won)

        let record = try await store.fetch(modeRaw: "practice", difficulty: .beginner)
        #expect(record.completedCount == 2)
    }

    @Test func resumedPracticeGameReusesSameIdAndDedups() async throws {
        // #705: "resume + win must dedup as the SAME game." A resumed board
        // reconstructs from the same persisted `seed`
        // (`MinesweeperSession.restore(from:)`), so a second VM instance over
        // the identical seed (simulating a relaunch-and-resume) must derive
        // the identical puzzleId and dedup against the earlier win instead of
        // double-counting.
        let (store, _) = makeStore()
        let seed: UInt64 = 7

        let vm1 = MinesweeperGameViewModel(
            difficulty: .beginner, seed: seed, mode: .practice, personalRecordStore: store
        )
        await driveToWin(vm1)
        #expect(vm1.status == .won)

        let vm2 = MinesweeperGameViewModel(
            difficulty: .beginner, seed: seed, mode: .practice, personalRecordStore: store
        )
        await driveToWin(vm2)
        #expect(vm2.status == .won)

        let record = try await store.fetch(modeRaw: "practice", difficulty: .beginner)
        #expect(record.completedCount == 1)
    }

    @Test func practiceWinRecordsPersonalBestButStillNeverSubmitsToGameCenter() async throws {
        // #705: widening the personal-record write to practice must NOT touch
        // the #329 Game Center gate — GC submit stays STRICTLY daily-only even
        // when a `gameCenter` client IS threaded alongside the now-eligible
        // personalRecordStore.
        let (store, _) = makeStore()
        let fake = FakeGameCenterClient()
        let vm = MinesweeperGameViewModel(
            difficulty: .beginner,
            seed: 42,
            mode: .practice,
            gameCenter: fake,
            personalRecordStore: store
        )

        await driveToWin(vm)
        #expect(vm.status == .won)

        let record = try await store.fetch(modeRaw: "practice", difficulty: .beginner)
        #expect(record.completedCount == 1, "the personal-record write must still fire")

        let ops = await fake.operations
        let submitted = ops.contains {
            if case .submitRawScore = $0 { return true }
            return false
        }
        #expect(submitted == false, "Game Center submit must stay daily-only")
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
