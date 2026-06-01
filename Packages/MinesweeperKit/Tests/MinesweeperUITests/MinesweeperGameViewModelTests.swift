// swiftlint:disable identifier_name

import Foundation
import Testing
@testable import MinesweeperUI
import MinesweeperEngine
import MinesweeperGameState

@MainActor
@Suite struct MinesweeperGameViewModelTests {

    @Test func initialSnapshotReflectsDifficulty() {
        let vm = MinesweeperGameViewModel(difficulty: .beginner, seed: 1)
        #expect(vm.rows == 9)
        #expect(vm.columns == 9)
        #expect(vm.mineCount == 10)
        #expect(vm.flagCount == 0)
        #expect(vm.remainingMineCount == 10)
        #expect(vm.status == .idle)
        #expect(vm.isTerminal == false)
    }

    @Test func revealUpdatesSnapshot() async {
        let vm = MinesweeperGameViewModel(difficulty: .beginner, seed: 42)
        await vm.reveal(row: 4, col: 4)
        #expect(vm.status == .playing)
        #expect(vm.cells.contains(where: { $0.state == .revealed }))
    }

    @Test func toggleFlagUpdatesFlagCount() async {
        let vm = MinesweeperGameViewModel(difficulty: .beginner, seed: 1)
        await vm.toggleFlag(row: 0, col: 0)
        #expect(vm.flagCount == 1)
        #expect(vm.remainingMineCount == 9)
        #expect(vm.cell(row: 0, col: 0).state == .flagged)
        await vm.toggleFlag(row: 0, col: 0)
        #expect(vm.flagCount == 0)
        #expect(vm.cell(row: 0, col: 0).state == .hidden)
    }

    @Test func revealingMineSetsTerminalStatus() async throws {
        let vm = MinesweeperGameViewModel(difficulty: .beginner, seed: 13)
        await vm.reveal(row: 4, col: 4)
        // Find a mine in the snapshot and reveal it.
        var minePos: (Int, Int)?
        for r in 0..<vm.rows {
            for c in 0..<vm.columns where vm.cell(row: r, col: c).isMine {
                minePos = (r, c); break
            }
            if minePos != nil { break }
        }
        let (mr, mc) = try #require(minePos)
        await vm.reveal(row: mr, col: mc)
        #expect(vm.status == .lost)
        #expect(vm.isTerminal == true)
    }

    @Test func sharedSessionRoundTrips() async {
        // ViewModel injected with an external session — used by previews /
        // composition. Snapshot must update via the same actor.
        let session = MinesweeperSession(difficulty: .beginner, seed: 7)
        let vm = MinesweeperGameViewModel(session: session)
        await vm.reveal(row: 4, col: 4)
        let direct = await session.snapshot()
        #expect(vm.cells == direct.cells)
        #expect(vm.status == direct.status)
    }
}

// swiftlint:enable identifier_name
