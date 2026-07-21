// SavedGameCompletedDailyIdsByDayTests — SavedGameStore.fetchCompletedDailyIdsByDay
// (#921), mirroring MinesweeperSavedGameStoreCompletedDailyIdsTests'
// `fetchCompletedDailyIdsByDayIssuesOneQueryAndBucketsRecordsByTheirOwnDay`
// (#915).
//
// #921: `DailyHubViewModel.fetchWeekWindow` used to call
// `fetchCompletedDailyIds(for:)` once per window day — 7 genuinely distinct
// `puzzleId BEGINSWITH`-filtered CK queries (unlike MS, where the 7 calls
// were byte-identical). `fetchCompletedDailyIdsByDay()` collapses that into
// ONE `.dailyCompletedAll` query (`mode == "daily" AND status == "completed"`,
// no `puzzleId` prefix clause) and buckets every returned puzzleId by its own
// UTC day client-side.

import Foundation
import Testing
import SudokuGameState
import SudokuEngine
import Telemetry
import PersistenceTesting
import TelemetryTesting
@testable import Persistence

@Suite("Persistence — SavedGameStore.fetchCompletedDailyIdsByDay (#921)")
struct SavedGameCompletedDailyIdsByDayTests {

    private static let fixedDate = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeStore(gateway: FakePrivateCKGateway) -> SavedGameStore {
        let sink = RecordingSink()
        let telemetry = Telemetry(sinks: [sink])
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        return SavedGameStore(
            gateway: gateway,
            telemetry: telemetry,
            puzzleLoader: { _ in puzzle },
            clock: { Self.fixedDate }
        )
    }

    private func markAsCompleted(
        puzzleId: String,
        store: SavedGameStore
    ) async throws {
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let session = GameSession(puzzle: puzzle)
        let snapshot = await session.snapshot()
        try await store.save(snapshot, puzzleId: puzzleId, mode: .daily, difficulty: .easy)
        try await store.markCompleted(SavedGameSummary(
            recordName: SavedGameStore.recordName(for: puzzleId, mode: .daily),
            puzzleId: puzzleId,
            mode: .daily,
            difficulty: .easy,
            lastModifiedAt: Self.fixedDate,
            elapsedSeconds: 0,
            status: "inProgress",
            generatorVersion: 1
        ))
    }

    /// #921: the week-strip window used to call `fetchCompletedDailyIds(for:)`
    /// once per day. `fetchCompletedDailyIdsByDay()` runs the underlying
    /// query exactly ONCE and buckets every daily-completed record by its own
    /// UTC day, so a record for one day lands ONLY in that day's bucket,
    /// never leaking into a sibling day's set.
    @Test
    func fetchCompletedDailyIdsByDayIssuesOneQueryAndBucketsRecordsByTheirOwnDay() async throws {
        let gateway = FakePrivateCKGateway()
        let store = makeStore(gateway: gateway)
        let today = UTCDay.string(from: Self.fixedDate)
        let todayPuzzleId = "\(today)-easy"
        try await markAsCompleted(puzzleId: todayPuzzleId, store: store)

        // A second completed daily on a different day — must land in ITS OWN
        // bucket, not today's.
        let otherDay = "2000-01-01"
        let otherPuzzleId = "\(otherDay)-easy"
        try await markAsCompleted(puzzleId: otherPuzzleId, store: store)

        let byDay = try await store.fetchCompletedDailyIdsByDay()

        #expect(byDay[today] == [todayPuzzleId])
        #expect(byDay[otherDay] == [otherPuzzleId])
        #expect(byDay.count == 2)

        // `save` + `markCompleted` issue `.fetch`/`.save` ops, never `.query`
        // — so every `.query` op recorded belongs to the single
        // `fetchCompletedDailyIdsByDay()` call above.
        let queryCount = await gateway.operations.filter { $0 == .query }.count
        #expect(queryCount == 1)
    }

    /// A day with no completions is simply absent from the map — callers
    /// (`fetchWeekWindow`) treat a missing key as an empty set.
    @Test
    func emptyStoreReturnsEmptyMap() async throws {
        let gateway = FakePrivateCKGateway()
        let store = makeStore(gateway: gateway)

        let byDay = try await store.fetchCompletedDailyIdsByDay()

        #expect(byDay.isEmpty)
    }
}
