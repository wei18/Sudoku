// Game2048BoardSnapshotTests — visual baselines for the 4×4 board.
//
// Mirrors MinesweeperBoardSnapshotTests + MinesweeperBoardRevealedSnapshotTests.
// Uses `Game2048GameViewModel(seeded:)` + `suppressTickerForSnapshot: true` so
// the fixture snapshot survives NSHostingView capture without the in-body task
// overwriting it.
//
// States covered:
//   1. initial — fresh 2-tile board from seed 42 (status: .playing)
//      Exercises: tile palette for 2/4, empty cells, score/move headers.
//   2. midGame — a board with several merged tiles across the value palette
//      Exercises: tile palette 8/16/32/64/128/256, score 1024, 12 moves.
//   3. stuck — the final stuck board with a high score and reachedTarget true
//      Exercises: stuck overlay (inline "Game Over" banner), no swipe feedback.
//
// Light + dark modes for each state = 6 baselines total.
// Recorded fresh on first run (SnapshotMode.recordMode = .missing).

#if canImport(AppKit)
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import Game2048UI
import Game2048Engine
import Game2048GameState

@MainActor
@Suite("Game2048BoardView — themed snapshots")
struct Game2048BoardSnapshotTests {

    // MARK: - Fixtures

    /// Build a seeded board view from an explicit tile layout.
    private func seededBoard(
        tiles: [Int?],
        score: Int = 0,
        moveCount: Int = 0,
        status: Game2048SessionStatus = .playing,
        elapsedSeconds: Int = 30,
        reachedTarget: Bool = false,
        seed: UInt64 = 42
    ) -> Game2048BoardView {
        let board = Board(tiles: tiles)
        let snap = Game2048SessionSnapshot(
            seed: seed,
            board: board,
            score: score,
            moveCount: moveCount,
            status: status,
            elapsedSeconds: elapsedSeconds,
            reachedTarget: reachedTarget
        )
        return Game2048BoardView(
            viewModel: Game2048GameViewModel(seeded: snap),
            suppressTickerForSnapshot: true
        )
    }

    /// Initial board: two tiles (2 and 4 by convention), rest empty.
    /// Represents the very first frame a player sees.
    private func initialTiles() -> [Int?] {
        var tiles: [Int?] = Array(repeating: nil, count: 16)
        tiles[0] = 2
        tiles[5] = 4
        return tiles
    }

    /// Mid-game board: exercising the warm tile palette (8 → 256).
    /// Score 1024, 12 moves.
    private func midGameTiles() -> [Int?] {
        [
            256, 128, 64, 32,
            16, 8, nil, 2,
            nil, 4, nil, nil,
            nil, nil, nil, 2,
        ]
    }

    /// Stuck board: fully packed with no legal move, high score.
    /// reachedTarget = true (2048 was reached earlier in the run).
    private func stuckTiles() -> [Int?] {
        // Alternating pattern that has no legal merge in any direction.
        [
            2, 4, 2, 4,
            4, 2, 4, 2,
            2, 4, 2, 4,
            4, 2, 4, 2,
        ]
    }

    // MARK: - Initial board

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotInitial_iPhone_light() {
        let view = seededBoard(tiles: initialTiles())
        assertUISnapshot(
            of: hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .light),
            as: .tolerantImage,
            named: "Board-iPhone-light-initial",
            record: SnapshotMode.recordMode
        )
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotInitial_iPhone_dark() {
        let view = seededBoard(tiles: initialTiles())
        assertUISnapshot(
            of: hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .dark),
            as: .tolerantImage,
            named: "Board-iPhone-dark-initial",
            record: SnapshotMode.recordMode
        )
    }

    // MARK: - Mid-game board

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotMidGame_iPhone_light() {
        let view = seededBoard(tiles: midGameTiles(), score: 1024, moveCount: 12)
        assertUISnapshot(
            of: hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .light),
            as: .tolerantImage,
            named: "Board-iPhone-light-midGame",
            record: SnapshotMode.recordMode
        )
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotMidGame_iPhone_dark() {
        let view = seededBoard(tiles: midGameTiles(), score: 1024, moveCount: 12)
        assertUISnapshot(
            of: hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .dark),
            as: .tolerantImage,
            named: "Board-iPhone-dark-midGame",
            record: SnapshotMode.recordMode
        )
    }

    // MARK: - Stuck board (terminal state)

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotStuck_iPhone_light() {
        let view = seededBoard(
            tiles: stuckTiles(),
            score: 4096,
            moveCount: 200,
            status: .stuck,
            elapsedSeconds: 600,
            reachedTarget: true
        )
        assertUISnapshot(
            of: hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .light),
            as: .tolerantImage,
            named: "Board-iPhone-light-stuck",
            record: SnapshotMode.recordMode
        )
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotStuck_iPhone_dark() {
        let view = seededBoard(
            tiles: stuckTiles(),
            score: 4096,
            moveCount: 200,
            status: .stuck,
            elapsedSeconds: 600,
            reachedTarget: true
        )
        assertUISnapshot(
            of: hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .dark),
            as: .tolerantImage,
            named: "Board-iPhone-dark-stuck",
            record: SnapshotMode.recordMode
        )
    }
}
#endif
