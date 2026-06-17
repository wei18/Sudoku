// LatestInProgressFilterTests — issue #228 option E.
//
// `SavedGameStore.latestInProgress()` must drop stale daily saves so the
// Resume pill never offers yesterday's daily (which would play but never
// score, per SubmitGuards). Practice saves are exempt — they never expire.

import Foundation
import Testing
import SudokuGameState
import SudokuEngine
import Telemetry
import PersistenceTesting
import TelemetryTesting
@testable import Persistence

@Suite("Persistence — latestInProgress filter (#228 E)")
struct LatestInProgressFilterTests {

    /// 2026-06-01 00:00:00 UTC. Tests pin a fixed "today".
    private static let fixedToday = Date(timeIntervalSince1970: 1_780_272_000)

    private func makeStore() async -> (SavedGameStore, FakePrivateCKGateway) {
        let gateway = FakePrivateCKGateway()
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let store = SavedGameStore(
            gateway: gateway,
            telemetry: Telemetry(sinks: [RecordingSink()]),
            puzzleLoader: { _ in puzzle },
            clock: { Self.fixedToday }
        )
        return (store, gateway)
    }

    /// Seed a SavedGame payload for the gateway. lastModifiedAt is the
    /// ordering key; mode + puzzleId drive the filter.
    private func seedSavedGame(
        gateway: FakePrivateCKGateway,
        puzzleId: String,
        mode: Mode,
        lastModifiedAt: Date
    ) async {
        let payload = RecordPayload(
            recordType: PrivateCKConstants.savedGameRecordType,
            recordName: "saved-\(puzzleId)",
            fields: [
                "puzzleId": .string(puzzleId),
                "mode": .string(mode.rawValue),
                "difficulty": .string(Difficulty.easy.rawValue),
                "boardState": .string(String(repeating: ".", count: 81)),
                "notesState": .string(""),
                "undoStack": .data(Data()),
                "startedAt": .date(lastModifiedAt.addingTimeInterval(-60)),
                "lastModifiedAt": .date(lastModifiedAt),
                "elapsedSeconds": .int(0),
                "status": .string("inProgress"),
                "generatorVersion": .int(1),
                "schemaVersion": .int(SavedGameStore.currentSchemaVersion)
            ]
        )
        await gateway.seed(payload)
    }

    @Test func todaysDailyIsEligible() async throws {
        let (store, gateway) = await makeStore()
        await seedSavedGame(
            gateway: gateway,
            puzzleId: "2026-06-01-easy",
            mode: .daily,
            lastModifiedAt: Self.fixedToday
        )
        let summary = try await store.latestInProgress()
        #expect(summary?.puzzleId == "2026-06-01-easy")
    }

    @Test func yesterdaysDailyIsFiltered() async throws {
        let (store, gateway) = await makeStore()
        await seedSavedGame(
            gateway: gateway,
            puzzleId: "2026-05-31-easy",
            mode: .daily,
            lastModifiedAt: Self.fixedToday.addingTimeInterval(-86_400)
        )
        let summary = try await store.latestInProgress()
        #expect(summary == nil)
    }

    @Test func staleDailyDoesNotMaskFreshPractice() async throws {
        let (store, gateway) = await makeStore()
        // Stale daily (yesterday) — modified more recently than the practice
        // save below. Without the filter, this stale record would win the
        // `lastModifiedAt` max and mask the practice candidate.
        await seedSavedGame(
            gateway: gateway,
            puzzleId: "2026-05-31-easy",
            mode: .daily,
            lastModifiedAt: Self.fixedToday.addingTimeInterval(-3_600)
        )
        await seedSavedGame(
            gateway: gateway,
            puzzleId: "practice-ABC-easy",
            mode: .practice,
            lastModifiedAt: Self.fixedToday.addingTimeInterval(-7_200)
        )
        let summary = try await store.latestInProgress()
        #expect(summary?.puzzleId == "practice-ABC-easy")
    }

    @Test func practiceSavesNeverExpire() async throws {
        let (store, gateway) = await makeStore()
        await seedSavedGame(
            gateway: gateway,
            puzzleId: "practice-ABC-easy",
            mode: .practice,
            // Even if the practice save is years old, it stays eligible.
            lastModifiedAt: Self.fixedToday.addingTimeInterval(-31_536_000)
        )
        let summary = try await store.latestInProgress()
        #expect(summary?.puzzleId == "practice-ABC-easy")
    }

    @Test func newestNonStaleWinsOverStaleAndOlderFresh() async throws {
        let (store, gateway) = await makeStore()
        // Stale daily — newest by lastModifiedAt — should be filtered.
        await seedSavedGame(
            gateway: gateway,
            puzzleId: "2026-05-31-easy",
            mode: .daily,
            lastModifiedAt: Self.fixedToday.addingTimeInterval(-3_600)
        )
        // Today's daily — fresher than the practice but older than the stale.
        await seedSavedGame(
            gateway: gateway,
            puzzleId: "2026-06-01-medium",
            mode: .daily,
            lastModifiedAt: Self.fixedToday.addingTimeInterval(-7_200)
        )
        // Practice — oldest among the non-stale set.
        await seedSavedGame(
            gateway: gateway,
            puzzleId: "practice-XYZ-hard",
            mode: .practice,
            lastModifiedAt: Self.fixedToday.addingTimeInterval(-10_800)
        )
        let summary = try await store.latestInProgress()
        #expect(summary?.puzzleId == "2026-06-01-medium")
    }
}
