// GameViewModelLateCompletionTests — issue #228 option B.
//
// Pins the `isLateCompletion` flag that drives BoardView's "won't score"
// header marker. The flag must be:
//   - true  for a daily puzzle with a UTC day prefix earlier than `clock()`'s today
//   - false for today's daily, future-dated dailies (shouldn't occur but be safe), and any practice puzzle

import Foundation
import Testing
import SudokuEngine
@testable import SudokuUI
import PuzzleStore

@MainActor
@Suite("GameViewModel — isLateCompletion (#228 B)")
struct GameViewModelLateCompletionTests {

    /// 2026-06-01 00:00:00 UTC.
    nonisolated(unsafe) private static let fixedToday = Date(timeIntervalSince1970: 1_780_272_000)

    private func makeViewModel(puzzleId: String, kind: Mode) throws -> GameViewModel {
        let board = try Board(clues: String(repeating: ".", count: 81))
        let today = Self.fixedToday
        return GameViewModel(
            identity: PuzzleIdentity(puzzleId: puzzleId, kind: kind, difficulty: .easy),
            board: board,
            clock: { today }
        )
    }

    @Test func dailyFromYesterday_isLate() throws {
        let vm = try makeViewModel(puzzleId: "2026-05-31-easy", kind: .daily)
        #expect(vm.isLateCompletion == true)
    }

    @Test func dailyFromToday_isNotLate() throws {
        let vm = try makeViewModel(puzzleId: "2026-06-01-easy", kind: .daily)
        #expect(vm.isLateCompletion == false)
    }

    @Test func dailyFromFuture_isNotLate() throws {
        // Defensive: should never happen, but a future-dated id must not
        // trip the "won't score" marker.
        let vm = try makeViewModel(puzzleId: "2099-01-01-easy", kind: .daily)
        #expect(vm.isLateCompletion == false)
    }

    @Test func practice_isNeverLate() throws {
        let vm = try makeViewModel(puzzleId: "practice-ABC-easy", kind: .practice)
        #expect(vm.isLateCompletion == false)
    }
}
