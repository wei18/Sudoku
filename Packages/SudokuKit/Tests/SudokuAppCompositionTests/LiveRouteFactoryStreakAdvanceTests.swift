// LiveRouteFactoryStreakAdvanceTests — `LiveRouteFactory.makeFetchStreakAdvance`
// (#1023 Phase B): the pre→post streak-ritual provider wired into the live
// Daily-solve completion overlay. Mirrors `makeFetchDailyProgress`'s
// injection shape and, like it, reads `Date()` internally rather than taking
// an injected clock — tests anchor on a `Date()` read at setup time and
// day-bucket via `UTCDay`, which is safe except across an exact UTC-midnight
// race (accepted; the sibling `fetchWeekWindow`/`makeFetchDailyProgress`
// factories carry the same non-injected-clock shape).

import Foundation
import Testing
import SudokuEngine
import SudokuPersistence
import SudokuKitTesting
@testable import SudokuAppComposition

@MainActor
@Suite("LiveRouteFactory — makeFetchStreakAdvance (#1023 Phase B)")
struct LiveRouteFactoryStreakAdvanceTests {

    private static func puzzleId(daysAgo: Int, from reference: Date, difficulty: String = "easy") -> String {
        let date = reference.addingTimeInterval(-Double(daysAgo) * 86_400)
        return "\(UTCDay.string(from: date))-\(difficulty)"
    }

    /// A 3-day run ending YESTERDAY (today not yet completed by any other
    /// difficulty) — solving today's puzzle should extend the streak 3 → 4
    /// and light today's (last) pip.
    @Test func computesPreAndPostAcrossAThreeDayRun() async {
        let reference = Date()
        let persistence = FakePersistence()
        for daysAgo in 1...3 {
            await persistence.setCompletedDailyIds(
                [Self.puzzleId(daysAgo: daysAgo, from: reference)],
                for: reference.addingTimeInterval(-Double(daysAgo) * 86_400)
            )
        }
        let todayPuzzleId = Self.puzzleId(daysAgo: 0, from: reference)

        let fetch = LiveRouteFactory.makeFetchStreakAdvance(currentPuzzleId: todayPuzzleId, persistence: persistence)
        let advance = await fetch()

        #expect(advance?.preCount == 3)
        #expect(advance?.postCount == 4)
        #expect(advance?.todayAdvanced == true)
        #expect(advance?.pipStates.last == true)
    }

    /// A different difficulty already completed today BEFORE this solve —
    /// today's pip was already lit, so pre == post and nothing advances.
    @Test func noAdvanceWhenAnotherDifficultyAlreadyCompletedToday() async {
        let reference = Date()
        let persistence = FakePersistence()
        let otherDifficultyToday = Self.puzzleId(daysAgo: 0, from: reference, difficulty: "medium")
        await persistence.setCompletedDailyIds([otherDifficultyToday], for: reference)
        let todayPuzzleId = Self.puzzleId(daysAgo: 0, from: reference, difficulty: "easy")

        let fetch = LiveRouteFactory.makeFetchStreakAdvance(currentPuzzleId: todayPuzzleId, persistence: persistence)
        let advance = await fetch()

        #expect(advance?.preCount == advance?.postCount)
        #expect(advance?.todayAdvanced == false)
    }

    /// A gap 2 days ago breaks the run — only YESTERDAY carries into today's
    /// streak (preCount == 1), extending to 2 on this solve.
    @Test func gapBreaksTheRunBeforeYesterday() async {
        let reference = Date()
        let persistence = FakePersistence()
        await persistence.setCompletedDailyIds(
            [Self.puzzleId(daysAgo: 1, from: reference)],
            for: reference.addingTimeInterval(-86_400)
        )
        // 2 days ago: nothing completed (gap) — day 3 being completed must
        // not extend the streak past the gap.
        await persistence.setCompletedDailyIds(
            [Self.puzzleId(daysAgo: 3, from: reference)],
            for: reference.addingTimeInterval(-3 * 86_400)
        )
        let todayPuzzleId = Self.puzzleId(daysAgo: 0, from: reference)

        let fetch = LiveRouteFactory.makeFetchStreakAdvance(currentPuzzleId: todayPuzzleId, persistence: persistence)
        let advance = await fetch()

        #expect(advance?.preCount == 1)
        #expect(advance?.postCount == 2)
    }

    /// All-or-nothing degrade (mirrors `fetchWeekWindow`): a fetch failure
    /// returns `nil`, never a partial/zeroed streak.
    @Test func returnsNilOnFetchFailure() async {
        let persistence = FakePersistence()
        await persistence.setFetchCompletedDailyIdsError(.underlying(domain: "test", code: 1, description: "boom"))

        let fetch = LiveRouteFactory.makeFetchStreakAdvance(currentPuzzleId: "2026-01-01-easy", persistence: persistence)
        let advance = await fetch()

        #expect(advance == nil)
    }
}
