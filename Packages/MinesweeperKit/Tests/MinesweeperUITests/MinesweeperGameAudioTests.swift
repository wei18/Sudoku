// MinesweeperGameAudioTests (#330 P2) — assert which `AudioEvent` (+ haptic) each
// gameplay action fires through the injected `SoundPlaying` seam.
//
// Uses the shared order-preserving `FakeSoundPlaying` from GameAudioTesting:
// `play(_:)` records synchronously in call order, so we can assert the exact
// event sequence. Boards are real `MinesweeperSession`s driven through the VM —
// the engine places mines on the first reveal (deferred), so each test does a
// known opening tap and then inspects the post-tap snapshot to pick its next
// move (a numbered cell for a single reveal, a mine for the explosion, etc.).

// swiftlint:disable identifier_name

import Foundation
import Testing
@testable import MinesweeperUI
import GameAudio
import GameAudioTesting
import MinesweeperEngine
import MinesweeperGameState

@MainActor
@Suite struct MinesweeperGameAudioTests {

    // MARK: - Flag

    @Test func flaggingFiresFlagEventWithNoHaptic() async {
        let fake = FakeSoundPlaying()
        let vm = MinesweeperGameViewModel(difficulty: .beginner, seed: 1, soundPlayer: fake)

        await vm.toggleFlag(row: 0, col: 0)

        #expect(fake.playedEvents == [.minesweeperFlag])
        #expect(fake.playedEvents.first?.haptic == nil)
    }

    @Test func unflaggingAlsoFiresFlagEvent() async {
        let fake = FakeSoundPlaying()
        let vm = MinesweeperGameViewModel(difficulty: .beginner, seed: 1, soundPlayer: fake)

        await vm.toggleFlag(row: 0, col: 0)
        await vm.toggleFlag(row: 0, col: 0) // unflag

        #expect(fake.playedEvents == [.minesweeperFlag, .minesweeperFlag])
    }

    // MARK: - Single reveal

    @Test func revealingSingleCellFiresRevealWithNoHaptic() async throws {
        let fake = FakeSoundPlaying()
        let vm = MinesweeperGameViewModel(difficulty: .beginner, seed: 42, soundPlayer: fake)

        // First reveal places mines + opens a region (its own event(s)).
        await vm.reveal(row: 4, col: 4)
        let countAfterFirst = fake.playedEvents.count

        // Find a still-hidden, non-mine NUMBERED cell — revealing it opens
        // exactly itself (the flood only expands through zero-cells), so it is a
        // single reveal, never a flood.
        var single: (Int, Int)?
        outer: for r in 0..<vm.rows {
            for c in 0..<vm.columns {
                let cell = vm.cell(row: r, col: c)
                if cell.state == .hidden, !cell.isMine, cell.neighborMineCount > 0 {
                    single = (r, c); break outer
                }
            }
        }
        let (sr, sc) = try #require(single)
        await vm.reveal(row: sr, col: sc)

        // The newest event is exactly one `.reveal`, with no haptic.
        let newEvents = Array(fake.playedEvents.dropFirst(countAfterFirst))
        #expect(newEvents == [.minesweeperReveal])
        #expect(newEvents.first?.haptic == nil)
    }

    // MARK: - Flood clear

    @Test func floodClearFiresFloodClearWithMediumHaptic() async throws {
        let fake = FakeSoundPlaying()
        let vm = MinesweeperGameViewModel(difficulty: .beginner, seed: 42, soundPlayer: fake)

        // The opening tap on a beginner board floods a zero-region (the first
        // click + neighbors are guaranteed mine-free), revealing many cells in one
        // action → a single `.floodClear`.
        await vm.reveal(row: 4, col: 4)

        let revealed = vm.cells.filter { $0.state == .revealed }.count
        try #require(revealed > 1, "opening tap on seed 42 should flood >1 cell")
        #expect(fake.playedEvents == [.minesweeperFloodClear])
        #expect(fake.playedEvents.first?.haptic == .medium)
    }

    // MARK: - Explosion (lose)

    @Test func hittingAMineFiresExplosionWithErrorHaptic() async throws {
        let fake = FakeSoundPlaying()
        let vm = MinesweeperGameViewModel(difficulty: .beginner, seed: 13, soundPlayer: fake)

        // Safe opening tap places mines.
        await vm.reveal(row: 4, col: 4)
        let countAfterFirst = fake.playedEvents.count

        // Find a mine and reveal it → loss.
        var minePos: (Int, Int)?
        outer: for r in 0..<vm.rows {
            for c in 0..<vm.columns where vm.cell(row: r, col: c).isMine {
                minePos = (r, c); break outer
            }
        }
        let (mr, mc) = try #require(minePos)
        await vm.reveal(row: mr, col: mc)

        #expect(vm.status == .lost)
        let newEvents = Array(fake.playedEvents.dropFirst(countAfterFirst))
        #expect(newEvents == [.minesweeperExplosion])
        #expect(newEvents.first?.haptic == .error)
    }

    // MARK: - Win

    @Test func winningFiresWinExactlyOnceWithSuccessHaptic() async throws {
        let fake = FakeSoundPlaying()
        let vm = MinesweeperGameViewModel(difficulty: .beginner, seed: 7, soundPlayer: fake)

        // Open the board, then reveal every remaining non-mine cell (skipping
        // mines so we never lose). The final reveal that clears the last safe cell
        // crosses into `.won` → exactly one `.win`.
        await vm.reveal(row: 4, col: 4)
        for r in 0..<vm.rows {
            for c in 0..<vm.columns {
                let cell = vm.cell(row: r, col: c)
                if cell.state == .hidden, !cell.isMine {
                    await vm.reveal(row: r, col: c)
                }
            }
        }

        #expect(vm.status == .won)
        let winEvents = fake.playedEvents.filter { $0 == .minesweeperWin }
        #expect(winEvents.count == 1)
        #expect(winEvents.first?.haptic == .success)
        // No explosion ever fired on the winning run.
        #expect(!fake.playedEvents.contains(.minesweeperExplosion))
    }
}

// swiftlint:enable identifier_name
