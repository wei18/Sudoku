// Game2048SavedGameStoreTests — mirrors MinesweeperPersistenceTests.
// Runs against `FakePrivateCKGateway` — zero live CloudKit.

import Foundation
import Testing
@testable import Game2048Persistence
import Game2048Engine
import Game2048GameState
import Persistence
import PersistenceTesting

@Suite("Game2048SavedGameStore")
struct Game2048SavedGameStoreTests {

    private func makeStore(clock: Date = Date(timeIntervalSince1970: 1_000_000)) -> (
        store: Game2048SavedGameStore,
        gateway: FakePrivateCKGateway
    ) {
        let gateway = FakePrivateCKGateway()
        let store = Game2048SavedGameStore(
            gateway: gateway,
            clock: { clock }
        )
        return (store, gateway)
    }

    private func practiceSnapshot(score: Int = 100, moveCount: Int = 10) -> Game2048SessionSnapshot {
        Game2048SessionSnapshot(
            seed: 42,
            board: Board(),
            score: score,
            moveCount: moveCount,
            status: .playing,
            elapsedSeconds: 60,
            reachedTarget: false
        )
    }

    // MARK: - save / latestInProgress round-trip

    @Test func saveAndLatestInProgress() async throws {
        let (store, _) = makeStore()
        let snap = practiceSnapshot()
        try await store.save(snap, modeRaw: Game2048GameModeRaw.practice, recordName: Game2048SavedGameStore.practiceRecordName)
        let summary = try await store.latestInProgress()
        #expect(summary?.recordName == Game2048SavedGameStore.practiceRecordName)
        #expect(summary?.score == 100)
        #expect(summary?.seed == 42)
    }

    @Test func latestInProgressReturnsNilWhenEmpty() async throws {
        let (store, _) = makeStore()
        let result = try await store.latestInProgress()
        #expect(result == nil)
    }

    // MARK: - markCompleted

    @Test func markCompletedHidesFromLatestInProgress() async throws {
        let (store, _) = makeStore()
        let snap = practiceSnapshot()
        try await store.save(snap, modeRaw: Game2048GameModeRaw.practice, recordName: Game2048SavedGameStore.practiceRecordName)
        try await store.markCompleted(recordName: Game2048SavedGameStore.practiceRecordName)
        let result = try await store.latestInProgress()
        #expect(result == nil)
    }

    // MARK: - loadInProgress

    @Test func loadInProgressRoundTrips() async throws {
        let (store, _) = makeStore()
        let snap = practiceSnapshot(score: 512, moveCount: 25)
        try await store.save(snap, modeRaw: Game2048GameModeRaw.practice, recordName: Game2048SavedGameStore.practiceRecordName)
        let loaded = try await store.loadInProgress(recordName: Game2048SavedGameStore.practiceRecordName)
        #expect(loaded?.score == 512)
        #expect(loaded?.moveCount == 25)
        #expect(loaded?.seed == 42)
    }

    @Test func loadInProgressReturnsNilForAbsentRecord() async throws {
        let (store, _) = makeStore()
        let result = try await store.loadInProgress(recordName: "nonexistent")
        #expect(result == nil)
    }

    // MARK: - wireStatus

    @Test func stuckMapsToCompleted() {
        #expect(Game2048SavedGameStore.wireStatus(for: .stuck) == "completed")
    }

    @Test func playingMapsToInProgress() {
        #expect(Game2048SavedGameStore.wireStatus(for: .playing) == "inProgress")
    }

    @Test func pausedMapsToInProgress() {
        #expect(Game2048SavedGameStore.wireStatus(for: .paused) == "inProgress")
    }

    // MARK: - dailyDay record-name parsing

    @Test func dailyDayExtractsDate() {
        #expect(Game2048SavedGameStore.dailyDay(fromRecordName: "daily-2026-06-15") == "2026-06-15")
    }

    @Test func dailyDayReturnsNilForPractice() {
        #expect(Game2048SavedGameStore.dailyDay(fromRecordName: "practice") == nil)
    }

    // MARK: - stale-daily filter

    @Test func staleDaily_filteredOut() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_749_945_600) // 2025-06-15 UTC
        let (store, _) = makeStore(clock: fixedNow)
        let yesterday = Game2048SavedGameStore.recordName(modeRaw: Game2048GameModeRaw.daily, now: Date(timeIntervalSince1970: 1_749_945_600 - 86400))
        let snap = practiceSnapshot()
        try await store.save(snap, modeRaw: Game2048GameModeRaw.daily, recordName: yesterday)
        // The day prefix in the record name is yesterday — should be filtered.
        let result = try await store.latestInProgress()
        // "daily-2025-06-14" < "2025-06-15" — stale, filtered
        #expect(result == nil || result?.modeRaw != Game2048GameModeRaw.daily)
    }
}
