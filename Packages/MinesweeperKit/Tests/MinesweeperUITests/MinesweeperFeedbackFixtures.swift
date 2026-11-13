// MinesweeperFeedbackFixtures (#1018) — real-engine boards with a KNOWN flood
// shape, shared by the view-model and rendered reveal-wave tests.
//
// Every board is a real `MinesweeperSession` built through the public
// `fixedMineIndices:` seam (the daily-retry seam, #841), so a tap goes through
// the real session and engine; nothing here hand-builds a reveal event.

import Foundation
import GameShellUI
import MinesweeperEngine
import MinesweeperGameState
import Testing
@testable import MinesweeperUI

/// Releases held sleepers by hand; a watchdog frees it so a regression (e.g.
/// `reveal` awaiting expiry) fails an assertion instead of hanging the run.
/// The watchdog is WALL-clock, and in a full-suite run the main actor is busy
/// for seconds with other suites (measured: the V3 test took 7.0 s there vs
/// 0.01 s alone, so a 5 s watchdog fired before its assertions ran). 30 s is
/// still a hard bound but clears that contention.
actor FeedbackGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var isReleased = false

    func wait() async {
        if isReleased { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        isReleased = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

func makeFeedbackGate(watchdog: Duration = .seconds(30)) -> FeedbackGate {
    let gate = FeedbackGate()
    Task {
        try? await Task.sleep(for: watchdog)
        await gate.release()
    }
    return gate
}

enum FeedbackBoard {
    /// 16x16, 40 mines: a full mine wall down column 8 splits the board into a
    /// left and a right flood region, a mine row along the bottom, and a safe
    /// pocket at (5,3) walled in by 8 mines so it never floods (the game
    /// cannot be won by the two floods). Taps: (0,0) floods the left region,
    /// (0,15) the right one.
    case twoRegions
    /// 9x9, 10 mines: a pocket at (6,6) walled in by 8 mines plus (8,0) and
    /// (8,8). A tap at (0,0) floods nearly the whole board (rings 0...8) and
    /// leaves the game running.
    case oneBigRegion
    /// 16x30 Expert, 99 mines: every cell of the last six columns plus three
    /// in column 23. A tap at (0,0) floods a region more than 20 rings deep.
    case expertWide

    var difficulty: Difficulty {
        switch self {
        case .twoRegions: .intermediate
        case .oneBigRegion: .beginner
        case .expertWide: .expert
        }
    }

    var mineIndices: Set<Int> {
        let columns = difficulty.columns
        func index(_ row: Int, _ col: Int) -> Int { row * columns + col }
        var mines = Set<Int>()
        switch self {
        case .twoRegions:
            for row in 0..<16 { mines.insert(index(row, 8)) }
            for col in 0..<16 { mines.insert(index(15, col)) }
            for row in 4...6 {
                for col in 2...4 where !(row == 5 && col == 3) { mines.insert(index(row, col)) }
            }
            mines.insert(index(13, 13))
        case .oneBigRegion:
            for row in 5...7 {
                for col in 5...7 where !(row == 6 && col == 6) { mines.insert(index(row, col)) }
            }
            mines.insert(index(8, 0))
            mines.insert(index(8, 8))
        case .expertWide:
            for row in 0..<16 {
                for col in 24..<30 { mines.insert(index(row, col)) }
            }
            for row in 0..<3 { mines.insert(index(row, 23)) }
        }
        return mines
    }

    /// A live (not seeded) view model over a real fixed-layout session.
    @MainActor
    func viewModel(gate: FeedbackGate) throws -> MinesweeperGameViewModel {
        let session = try MinesweeperSession(difficulty: difficulty, seed: 0, fixedMineIndices: mineIndices)
        return MinesweeperGameViewModel(session: session, cellFeedbackSleeper: { _ in await gate.wait() })
    }
}

/// Chebyshev distance — the ring of a cell around the tapped origin.
func chebyshevRing(index: Int, columns: Int, originRow: Int, originCol: Int) -> Int {
    max(abs(index / columns - originRow), abs(index % columns - originCol))
}
