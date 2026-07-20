// MinesweeperDailyHubViewModelWeekStripTests — #774 week-strip
// fetch/degrade/refresh integration + the pure streak matrix, mirroring
// Sudoku's `DailyHubViewModelWeekStripTests` / `DailyStripLogicTests`.
//
// The integration half drives `MinesweeperDailyHubViewModel` against a
// `FakePrivateCKGateway`-backed `MinesweeperSavedGameStore` (the #816
// store-level fetch path — MS's completed-ids read never goes through the
// Sudoku-shaped `PersistenceProtocol` query).

import Foundation
import Testing
import MinesweeperEngine
import MinesweeperGameState
import MinesweeperPersistence
import Persistence
import PersistenceTesting
@testable import MinesweeperUI

@MainActor
@Suite("MinesweeperDailyHubViewModel — week strip (#774)")
struct MinesweeperDailyHubViewModelWeekStripTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    private func dailyRecordPayload(
        recordName: String,
        status: String,
        mode: String = "daily",
        difficulty: String = "beginner"
    ) -> RecordPayload {
        RecordPayload(
            recordType: PrivateCKConstants.savedGameRecordType,
            recordName: recordName,
            fields: [
                "difficulty": .string(difficulty),
                "seed": .int(0),
                "mode": .string(mode),
                "elapsedSeconds": .int(30),
                "status": .string(status),
                "lastModifiedAt": .date(Self.fixedDate),
                "schemaVersion": .int(1),
                "stateBlob": .data(Data()),
            ]
        )
    }

    private func makeViewModel(gateway: FakePrivateCKGateway) -> MinesweeperDailyHubViewModel {
        MinesweeperDailyHubViewModel(
            path: .constant([]),
            savedGameStore: MinesweeperSavedGameStore(gateway: gateway, clock: { Self.fixedDate }),
            dateProvider: { Self.fixedDate }
        )
    }

    @Test func weekStripStartsUnknown() async {
        let viewModel = makeViewModel(gateway: FakePrivateCKGateway())
        #expect(viewModel.weekStrip == .unknown)
    }

    @Test func bootstrapPopulatesSevenDaysWithTodayLast() async {
        let viewModel = makeViewModel(gateway: FakePrivateCKGateway())

        await viewModel.bootstrap()

        #expect(viewModel.weekStrip.days.count == 7)
        #expect(viewModel.weekStrip.days.last?.isToday == true)
        #expect(viewModel.weekStrip.days.first?.offsetFromToday == 6)
    }

    /// Rule 1 (owner adjudication 2026-07-15): ANY one difficulty completed
    /// on a past day lights that day's dot.
    @Test func pastDayCompletionLightsThatDaysDot() async {
        let gateway = FakePrivateCKGateway()
        let yesterday = Self.fixedDate.addingTimeInterval(-86_400)
        let yesterdayId = MinesweeperDaily.puzzleId(date: yesterday, difficulty: .expert)
        await gateway.seed(dailyRecordPayload(recordName: yesterdayId, status: "completed", difficulty: "expert"))
        let viewModel = makeViewModel(gateway: gateway)

        await viewModel.bootstrap()

        let yesterdaySlot = viewModel.weekStrip.days.first { $0.offsetFromToday == 1 }
        #expect(yesterdaySlot?.isCompleted == true)
        #expect(viewModel.weekStrip.days.last?.isCompleted == false)
    }

    /// Rule 2 (owner adjudication 2026-07-15): a mine-hit loss does NOT
    /// count as completion — a "failed" record must not light the dot nor
    /// extend the streak (and equally must not "break" anything beyond the
    /// day simply staying incomplete).
    @Test func failedRecordDoesNotLightDotOrExtendStreak() async {
        let gateway = FakePrivateCKGateway()
        let yesterday = Self.fixedDate.addingTimeInterval(-86_400)
        let twoDaysAgo = Self.fixedDate.addingTimeInterval(-2 * 86_400)
        await gateway.seed(dailyRecordPayload(
            recordName: MinesweeperDaily.puzzleId(date: yesterday, difficulty: .beginner),
            status: "failed"
        ))
        await gateway.seed(dailyRecordPayload(
            recordName: MinesweeperDaily.puzzleId(date: twoDaysAgo, difficulty: .beginner),
            status: "completed"
        ))
        let viewModel = makeViewModel(gateway: gateway)

        await viewModel.bootstrap()

        let yesterdaySlot = viewModel.weekStrip.days.first { $0.offsetFromToday == 1 }
        let twoDaysAgoSlot = viewModel.weekStrip.days.first { $0.offsetFromToday == 2 }
        #expect(yesterdaySlot?.isCompleted == false)
        #expect(twoDaysAgoSlot?.isCompleted == true)
        // The loss yesterday leaves that day incomplete, so the chain ending
        // two days ago is already broken by the time today is evaluated —
        // streak walks back from today/yesterday only (nil == 0-day streak,
        // never captioned as "0").
        #expect(viewModel.weekStrip.streak == nil)
    }

    /// Chain ending yesterday with today incomplete: yesterday + the day
    /// before completed → 2-day streak (today's incompleteness must not
    /// zero it).
    @Test func chainEndingYesterdaySurvivesTodayIncomplete() async {
        let gateway = FakePrivateCKGateway()
        for offset in [1, 2] {
            let day = Self.fixedDate.addingTimeInterval(-Double(offset) * 86_400)
            await gateway.seed(dailyRecordPayload(
                recordName: MinesweeperDaily.puzzleId(date: day, difficulty: .beginner),
                status: "completed"
            ))
        }
        let viewModel = makeViewModel(gateway: gateway)

        await viewModel.bootstrap()

        #expect(viewModel.weekStrip.streak == 2)
    }

    /// No `savedGameStore` injected (preview/test callsites) → the strip
    /// degrades to `.unknown`, mirroring the CK-failure degrade.
    @Test func missingStoreDegradesStripToUnknown() async {
        let viewModel = MinesweeperDailyHubViewModel(
            path: .constant([]),
            dateProvider: { Self.fixedDate }
        )

        await viewModel.bootstrap()

        #expect(viewModel.weekStrip == .unknown)
        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(cards.count == 3)
    }

    /// #915: the week-strip window used to issue 7 byte-identical CK
    /// `query()` calls (one per day, each filtered client-side to a single
    /// day) — `fetchWeekWindow` now backs all 7 slots from ONE
    /// `fetchCompletedDailyIdsByDay()` call. `bootstrap()` also fires
    /// `fetchFailedIds` (its own independent `query()` lane), so the total
    /// after bootstrap is 2 — not the pre-fix 8.
    @Test func bootstrapIssuesExactlyTwoQueriesNotOnePerWindowDay() async {
        let gateway = FakePrivateCKGateway()
        let viewModel = makeViewModel(gateway: gateway)

        await viewModel.bootstrap()

        let queryCount = await gateway.operations.filter { $0 == .query }.count
        #expect(queryCount == 2)
    }

    /// `refresh()` re-runs the window fetch and picks up a newly-completed
    /// today without a full hub remount (#761 contract, extended to the strip).
    @Test func refreshUpdatesWeekStripWhenTodayBecomesCompleted() async {
        let gateway = FakePrivateCKGateway()
        let viewModel = makeViewModel(gateway: gateway)

        await viewModel.bootstrap()
        #expect(viewModel.weekStrip.days.last?.isCompleted == false)

        await gateway.seed(dailyRecordPayload(
            recordName: MinesweeperDaily.puzzleId(date: Self.fixedDate, difficulty: .beginner),
            status: "completed"
        ))
        await viewModel.refresh()

        #expect(viewModel.weekStrip.days.last?.isCompleted == true)
        #expect(viewModel.weekStrip.streak == 1)
    }

    // MARK: - Pure streak matrix (MinesweeperDailyStripLogic)

    private func days(completed: [Bool]) -> [MinesweeperDailyStripDay] {
        precondition(completed.count == 7)
        return completed.enumerated().map { index, isCompleted in
            let offset = 6 - index
            let date = Self.fixedDate.addingTimeInterval(-Double(offset) * 86_400)
            return MinesweeperDailyStripDay(offsetFromToday: offset, date: date, isCompleted: isCompleted)
        }
    }

    @Test func streakMatrix() {
        #expect(MinesweeperDailyStripLogic.computeStreak(days: []) == 0)
        #expect(MinesweeperDailyStripLogic.computeStreak(
            days: days(completed: [false, false, false, false, false, false, false])) == 0)
        #expect(MinesweeperDailyStripLogic.computeStreak(
            days: days(completed: [false, false, false, false, false, false, true])) == 1)
        #expect(MinesweeperDailyStripLogic.computeStreak(
            days: days(completed: [false, false, false, false, true, true, false])) == 2)
        #expect(MinesweeperDailyStripLogic.computeStreak(
            days: days(completed: [true, true, true, true, false, true, true])) == 2)
        #expect(MinesweeperDailyStripLogic.computeStreak(
            days: days(completed: [true, true, true, true, true, true, true])) == 7)
    }
}
