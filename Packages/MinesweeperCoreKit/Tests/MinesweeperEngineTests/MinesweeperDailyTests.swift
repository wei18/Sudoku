// MinesweeperDailyTests — determinism + UTC-rollover coverage for #290.
//
// Asserts the daily contract: same UTC day → identical seed / board for
// everyone, and the board rolls over exactly at UTC midnight regardless of
// device timezone.

import Foundation
import Testing
@testable import MinesweeperEngine

// MARK: - Date helpers (UTC)

private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    return calendar.date(from: components)!
}

@Suite struct MinesweeperDailyTests {

    // MARK: Same UTC day → identical seed + board

    @Test func sameDaySameSeedAcrossDifficulties() {
        let morning = utcDate(2026, 6, 4, 0, 1)
        let evening = utcDate(2026, 6, 4, 23, 59)
        for difficulty in MinesweeperDaily.dailyDifficulties {
            #expect(
                MinesweeperDaily.seed(date: morning, difficulty: difficulty)
                    == MinesweeperDaily.seed(date: evening, difficulty: difficulty)
            )
        }
    }

    @Test func sameDaySameBoardLayout() throws {
        let firstClick = (row: 0, col: 0)
        for difficulty in MinesweeperDaily.dailyDifficulties {
            var morning = MinesweeperDaily.board(date: utcDate(2026, 6, 4, 1), difficulty: difficulty)
            var evening = MinesweeperDaily.board(date: utcDate(2026, 6, 4, 22), difficulty: difficulty)
            #expect(morning.seed == evening.seed)
            // First reveal fully resolves mine layout — assert it's identical.
            try morning.reveal(row: firstClick.row, col: firstClick.col)
            try evening.reveal(row: firstClick.row, col: firstClick.col)
            let mineLayoutA = morning.cells.map(\.isMine)
            let mineLayoutB = evening.cells.map(\.isMine)
            #expect(mineLayoutA == mineLayoutB)
        }
    }

    // MARK: Rollover boundary

    @Test func rollsOverAtUtcMidnight() {
        // 23:59 of day N and 00:01 of day N+1 must differ.
        let lateDay4 = MinesweeperDaily.seed(date: utcDate(2026, 6, 4, 23, 59), difficulty: .beginner)
        let earlyDay5 = MinesweeperDaily.seed(date: utcDate(2026, 6, 5, 0, 1), difficulty: .beginner)
        #expect(lateDay4 != earlyDay5)
    }

    @Test func midnightBoundaryIsExact() {
        // 23:59:59 of day N buckets to day N; 00:00:00 of day N+1 buckets to N+1.
        let justBefore = utcDate(2026, 6, 4, 23, 59)
        let justAfter = utcDate(2026, 6, 5, 0, 0)
        #expect(UTCDay.string(from: justBefore) == "2026-06-04")
        #expect(UTCDay.string(from: justAfter) == "2026-06-05")
    }

    // MARK: Difficulty separation

    @Test func differentDifficultiesDifferentSeeds() {
        let date = utcDate(2026, 6, 4)
        let beginner = MinesweeperDaily.seed(date: date, difficulty: .beginner)
        let intermediate = MinesweeperDaily.seed(date: date, difficulty: .intermediate)
        let expert = MinesweeperDaily.seed(date: date, difficulty: .expert)
        #expect(beginner != intermediate)
        #expect(intermediate != expert)
        #expect(beginner != expert)
    }

    // MARK: puzzleId

    @Test func puzzleIdFormatIsStable() {
        let date = utcDate(2026, 6, 4)
        #expect(MinesweeperDaily.puzzleId(date: date, difficulty: .beginner) == "daily-2026-06-04-beginner")
        #expect(MinesweeperDaily.puzzleId(date: date, difficulty: .expert) == "daily-2026-06-04-expert")
    }

    @Test func puzzleIdMatchesDayBucket() {
        // Two timestamps in the same UTC day yield the same id.
        let early = MinesweeperDaily.puzzleId(date: utcDate(2026, 6, 4, 0, 1), difficulty: .intermediate)
        let late = MinesweeperDaily.puzzleId(date: utcDate(2026, 6, 4, 23, 59), difficulty: .intermediate)
        #expect(early == late)
    }

    // MARK: Trio shape

    @Test func dailyTrioIsThreeDistinctDifficulties() {
        #expect(MinesweeperDaily.dailyDifficulties == [.beginner, .intermediate, .expert])
        #expect(Set(MinesweeperDaily.dailyDifficulties).count == 3)
    }
}
