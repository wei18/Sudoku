// swiftlint:disable identifier_name
//
// MinesweeperGameCenterSubmitTests — submit-on-win wiring (#291).
//
// Drives `MinesweeperGameViewModel` to a real `.won` state (reveal every
// non-mine cell on a small board) with an injected `FakeGameCenterClient`,
// and asserts the best-time leaderboard submit fires exactly once with the
// difficulty's leaderboard ID + the frozen elapsed seconds. Also covers the
// non-blocking error path (a thrown submit error must not crash gameplay and
// must leave the won snapshot intact).

import Foundation
import Testing
@testable import MinesweeperUI
import MinesweeperEngine
import MinesweeperGameState
import GameCenterClient
import GameCenterTesting

@MainActor
@Suite("MinesweeperGameViewModel — Game Center submit-on-win")
struct MinesweeperGameCenterSubmitTests {

    /// Drive `vm` to a win by revealing every non-mine cell. Mines are placed
    /// on the first reveal (deferred placement), so we reveal a corner first,
    /// read the mine layout, then sweep the rest. Returns once `.won`.
    private func driveToWin(_ vm: MinesweeperGameViewModel) async {
        // First reveal seeds mine placement; corner keeps the flood small.
        await vm.reveal(row: 0, col: 0)
        // Sweep every non-mine, non-revealed cell. Each reveal may flood-fill
        // additional cells, so we re-scan until the board is won or stable.
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

    @Test func winSubmitsBestTimeOnceWithDifficultyLeaderboardId() async {
        let fake = FakeGameCenterClient()
        let vm = MinesweeperGameViewModel(
            difficulty: .beginner,
            seed: 42,
            gameCenter: fake
        )

        await driveToWin(vm)
        #expect(vm.status == .won)

        let ops = await fake.operations
        let submits = ops.compactMap { op -> (String, Int)? in
            if case let .submitRawScore(id, secs) = op { return (id, secs) }
            return nil
        }
        #expect(submits.count == 1)
        #expect(submits.first?.0 == MinesweeperLeaderboardID.easyDaily)
        // Score is the won snapshot's elapsed seconds (frozen at win).
        #expect(submits.first?.1 == vm.elapsedSeconds)
    }

    @Test func intermediateWinSubmitsToIntermediateLeaderboard() async {
        let fake = FakeGameCenterClient()
        let vm = MinesweeperGameViewModel(
            difficulty: .intermediate,
            seed: 7,
            gameCenter: fake
        )

        await driveToWin(vm)
        #expect(vm.status == .won)

        let ops = await fake.operations
        let ids = ops.compactMap { op -> String? in
            if case let .submitRawScore(id, _) = op { return id }
            return nil
        }
        #expect(ids == [MinesweeperLeaderboardID.mediumDaily])
    }

    @Test func noGameCenterClientSubmitsNothing() async {
        // MVP / preview callsite: nil client → submit-on-win is a no-op and
        // the win still completes normally.
        let vm = MinesweeperGameViewModel(difficulty: .beginner, seed: 42)
        await driveToWin(vm)
        #expect(vm.status == .won)
        // No client to assert against — the test passes by not crashing and
        // reaching `.won`.
    }

    @Test func submitErrorIsSwallowedAndDoesNotBreakWin() async {
        let fake = FakeGameCenterClient()
        await fake.setSubmitScoreError(.scoreSubmitFailed(reason: "network down"))
        let vm = MinesweeperGameViewModel(
            difficulty: .beginner,
            seed: 42,
            gameCenter: fake
        )

        await driveToWin(vm)

        // Gameplay is unaffected by the swallowed submit error.
        #expect(vm.status == .won)
        let ops = await fake.operations
        // The submit was still attempted exactly once (the error is thrown
        // *after* the op is recorded in the fake).
        let submitCount = ops.filter {
            if case .submitRawScore = $0 { return true }
            return false
        }.count
        #expect(submitCount == 1)
    }

    @Test func losingNeverSubmits() async {
        let fake = FakeGameCenterClient()
        let vm = MinesweeperGameViewModel(
            difficulty: .beginner,
            seed: 13,
            gameCenter: fake
        )
        // Reveal a corner to seed mines, then detonate the first mine found.
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
        let ops = await fake.operations
        let submitted = ops.contains {
            if case .submitRawScore = $0 { return true }
            return false
        }
        #expect(submitted == false)
    }

    @Test func leaderboardIdSchemeMirrorsSudokuDaily() {
        // Recurring-daily shape, `.v1`-suffixed, easy/medium/hard segments —
        // byte-equal to ASCRegister Config.leaderboards(for: .minesweeper).
        #expect(MinesweeperLeaderboardID.easyDaily
                == "com.wei18.minesweeper.leaderboard.easy.daily.v1")
        #expect(MinesweeperLeaderboardID.mediumDaily
                == "com.wei18.minesweeper.leaderboard.medium.daily.v1")
        #expect(MinesweeperLeaderboardID.hardDaily
                == "com.wei18.minesweeper.leaderboard.hard.daily.v1")
        #expect(MinesweeperLeaderboardID.allDaily.count == 3)
    }

    @Test func difficultyMapsToSudokuMirroringSegment() {
        // MS engine difficulty (beginner/intermediate/expert) → Sudoku id
        // segment (easy/medium/hard).
        #expect(MinesweeperLeaderboardID.daily(for: .beginner)
                == MinesweeperLeaderboardID.easyDaily)
        #expect(MinesweeperLeaderboardID.daily(for: .intermediate)
                == MinesweeperLeaderboardID.mediumDaily)
        #expect(MinesweeperLeaderboardID.daily(for: .expert)
                == MinesweeperLeaderboardID.hardDaily)
    }
}

// swiftlint:enable identifier_name
