// LiveRouteFactoryStreakAdvanceTests — `LiveRouteFactory.makeFetchStreakAdvance`
// (#1023 Phase B): the pre→post streak-ritual provider wired into the live
// Daily-WIN completion overlay (`MinesweeperDailyOpenGuardView`'s
// `.resolved(.playable)` branch). Mirrors `makeFetchDailyProgress`'s
// injection shape and, like it, reads `Date()` internally rather than taking
// an injected clock — tests anchor on a `Date()` read at setup time and
// day-bucket via `UTCDay`, which is safe except across an exact UTC-midnight
// race (accepted; same non-injected-clock shape the sibling factory has).
//
// Fixture pattern mirrors `MinesweeperDailyHubViewModelWeekStripTests`: a
// `FakePrivateCKGateway`-backed `MinesweeperSavedGameStore`, seeded with raw
// `RecordPayload`s via `gateway.seed(_:)`.

import Foundation
import Testing
import MinesweeperEngine
import MinesweeperGameState
import MinesweeperPersistence
import Persistence
import PersistenceTesting
@testable import MinesweeperAppComposition

@MainActor
@Suite("LiveRouteFactory — makeFetchStreakAdvance (#1023 Phase B)")
struct LiveRouteFactoryStreakAdvanceTests {

    private func dailyRecordPayload(recordName: String, status: String = "completed", difficulty: String = "beginner") -> RecordPayload {
        RecordPayload(
            recordType: PrivateCKConstants.savedGameRecordType,
            recordName: recordName,
            fields: [
                "difficulty": .string(difficulty),
                "seed": .int(0),
                "mode": .string("daily"),
                "elapsedSeconds": .int(30),
                "status": .string(status),
                "lastModifiedAt": .date(Date()),
                "schemaVersion": .int(1),
                "stateBlob": .data(Data()),
            ]
        )
    }

    /// A 3-day run ending YESTERDAY (today not yet completed) — winning
    /// today's puzzle should extend the streak 3 → 4 and light today's
    /// (last) pip.
    @Test func computesPreAndPostAcrossAThreeDayRun() async {
        let reference = Date()
        let gateway = FakePrivateCKGateway()
        for daysAgo in 1...3 {
            let date = reference.addingTimeInterval(-Double(daysAgo) * 86_400)
            await gateway.seed(dailyRecordPayload(recordName: MinesweeperDaily.puzzleId(date: date, difficulty: .beginner)))
        }
        let store = MinesweeperSavedGameStore(gateway: gateway, clock: { reference })
        let todayPuzzleId = MinesweeperDaily.puzzleId(date: reference, difficulty: .beginner)

        let fetch = LiveRouteFactory.makeFetchStreakAdvance(currentPuzzleId: todayPuzzleId, savedGameStore: store)
        let advance = await fetch()

        #expect(advance?.preCount == 3)
        #expect(advance?.postCount == 4)
        #expect(advance?.todayAdvanced == true)
        #expect(advance?.pipStates.last == true)
    }

    /// A different difficulty already WON today BEFORE this solve — today's
    /// pip was already lit, so pre == post and nothing advances.
    @Test func noAdvanceWhenAnotherDifficultyAlreadyWonToday() async {
        let reference = Date()
        let gateway = FakePrivateCKGateway()
        await gateway.seed(dailyRecordPayload(
            recordName: MinesweeperDaily.puzzleId(date: reference, difficulty: .intermediate),
            difficulty: "intermediate"
        ))
        let store = MinesweeperSavedGameStore(gateway: gateway, clock: { reference })
        let todayPuzzleId = MinesweeperDaily.puzzleId(date: reference, difficulty: .beginner)

        let fetch = LiveRouteFactory.makeFetchStreakAdvance(currentPuzzleId: todayPuzzleId, savedGameStore: store)
        let advance = await fetch()

        #expect(advance?.preCount == advance?.postCount)
        #expect(advance?.todayAdvanced == false)
    }

    /// A mine-hit loss does NOT count as completion (#774 Rule 2) — a
    /// "failed" record for today must not pre-light today's pip.
    @Test func lossRecordTodayDoesNotCountAsPreCompleted() async {
        let reference = Date()
        let gateway = FakePrivateCKGateway()
        await gateway.seed(dailyRecordPayload(
            recordName: MinesweeperDaily.puzzleId(date: reference, difficulty: .intermediate),
            status: "failed",
            difficulty: "intermediate"
        ))
        let store = MinesweeperSavedGameStore(gateway: gateway, clock: { reference })
        let todayPuzzleId = MinesweeperDaily.puzzleId(date: reference, difficulty: .beginner)

        let fetch = LiveRouteFactory.makeFetchStreakAdvance(currentPuzzleId: todayPuzzleId, savedGameStore: store)
        let advance = await fetch()

        #expect(advance?.preCount == 0)
        #expect(advance?.postCount == 1)
        #expect(advance?.todayAdvanced == true)
    }

    /// No store wired (preview/test call site without `savedGameStore`) —
    /// no streak section renders, mirroring `makeFetchDailyProgress`'s own
    /// `.allDone` no-store default.
    @Test func returnsNilWhenNoStoreWired() async {
        let fetch = LiveRouteFactory.makeFetchStreakAdvance(currentPuzzleId: "daily-2026-01-01-beginner", savedGameStore: nil)
        let advance = await fetch()
        #expect(advance == nil)
    }
}
