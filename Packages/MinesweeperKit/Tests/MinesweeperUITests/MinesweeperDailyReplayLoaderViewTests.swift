// MinesweeperDailyReplayLoaderViewTests — #841 end-to-end coverage:
// "daily retry after loss generates a different board per first click —
// daily must be one fixed game".
//
// Drives `MinesweeperDailyReplayLoaderView.makeReplaySession(...)` directly
// (no SwiftUI host needed — it's the pure async recovery step) against a
// `FakePrivateCKGateway`, mirroring the persisted-record shape a real daily
// loss would write via `MinesweeperGameViewModel.persistCurrentState()`.

import Foundation
import Testing
@testable import MinesweeperUI
import MinesweeperEngine
import MinesweeperGameState
import MinesweeperPersistence
import Persistence
import PersistenceTesting
import Telemetry

@Suite("MinesweeperDailyReplayLoaderView — recover the daily's persisted layout (#841)")
struct MinesweeperDailyReplayLoaderViewTests {

    private static let fixedDate = Date(timeIntervalSince1970: 1_750_000_000)
    private static let recordName = "daily-2026-07-17-beginner"

    private func makeStore(_ gateway: FakePrivateCKGateway) -> MinesweeperSavedGameStore {
        MinesweeperSavedGameStore(gateway: gateway, clock: { Self.fixedDate })
    }

    /// Simulate the ORIGINAL first-ever daily attempt: reveal a cell,
    /// detonate a mine, and save the resulting "failed" snapshot under the
    /// daily's record name — exactly what `persistCurrentState()` does on a
    /// live loss.
    private func seedFailedDailyRecord(gateway: FakePrivateCKGateway, firstClickRow: Int, firstClickCol: Int) async throws {
        let store = makeStore(gateway)
        let session = MinesweeperSession(difficulty: .beginner, seed: 99)
        var snap = try await session.reveal(row: firstClickRow, col: firstClickCol)
        if let mine = snap.cells.enumerated().first(where: { $0.element.isMine && $0.element.state != .revealed }) {
            let row = mine.offset / snap.columns
            let col = mine.offset % snap.columns
            snap = try await session.reveal(row: row, col: col)
        }
        try #require(snap.status == .lost)
        try await store.save(snap, modeRaw: "daily", recordName: Self.recordName)
    }

    /// The core #841 acceptance criterion at the loader layer: two replay
    /// sessions recovered from the SAME persisted failed record, but
    /// revealed at DIFFERENT first cells, produce an IDENTICAL mine layout.
    @Test
    func replaySessionsFromSameRecordShareLayoutRegardlessOfFirstClick() async throws {
        let gateway = FakePrivateCKGateway()
        try await seedFailedDailyRecord(gateway: gateway, firstClickRow: 4, firstClickCol: 4)
        let store = makeStore(gateway)

        let sessionA = try await MinesweeperDailyReplayLoaderView.makeReplaySession(
            difficulty: .beginner, seed: 99, recordName: Self.recordName, store: store, errorReporter: nil
        )
        let sessionB = try await MinesweeperDailyReplayLoaderView.makeReplaySession(
            difficulty: .beginner, seed: 99, recordName: Self.recordName, store: store, errorReporter: nil
        )

        _ = try? await sessionA.reveal(row: 0, col: 0)
        _ = try? await sessionB.reveal(row: 8, col: 8)

        let snapA = await sessionA.snapshot()
        let snapB = await sessionB.snapshot()
        #expect(snapA.mineIndices == snapB.mineIndices)
    }

    /// The recovered layout must match what the ORIGINAL attempt actually
    /// played, not just be internally consistent across replays.
    @Test
    func replaySessionMatchesOriginalAttemptsLayout() async throws {
        let gateway = FakePrivateCKGateway()
        try await seedFailedDailyRecord(gateway: gateway, firstClickRow: 4, firstClickCol: 4)
        let store = makeStore(gateway)
        let originalSnapshot = try #require(try await store.loadSnapshot(recordName: Self.recordName))

        let replay = try await MinesweeperDailyReplayLoaderView.makeReplaySession(
            difficulty: .beginner, seed: 99, recordName: Self.recordName, store: store, errorReporter: nil
        )
        _ = try? await replay.reveal(row: 2, col: 6)
        let replaySnap = await replay.snapshot()

        #expect(replaySnap.mineIndices == originalSnapshot.mineIndices)
    }

    /// Second-attempt semantics: the recovered layout has no first-click
    /// safety baked in for THIS session — if the fixed layout has a mine
    /// under the replay's very first tap, it's a normal, uncushioned loss.
    @Test
    func replaySessionCanLoseOnItsOwnFirstClick() async throws {
        let gateway = FakePrivateCKGateway()
        try await seedFailedDailyRecord(gateway: gateway, firstClickRow: 4, firstClickCol: 4)
        let store = makeStore(gateway)
        let originalSnapshot = try #require(try await store.loadSnapshot(recordName: Self.recordName))
        let mineIndex = try #require(originalSnapshot.mineIndices.first)
        let mineRow = mineIndex / originalSnapshot.columns
        let mineCol = mineIndex % originalSnapshot.columns

        let replay = try await MinesweeperDailyReplayLoaderView.makeReplaySession(
            difficulty: .beginner, seed: 99, recordName: Self.recordName, store: store, errorReporter: nil
        )
        let snap = try await replay.reveal(row: mineRow, col: mineCol)
        #expect(snap.status == .lost)
    }

    /// Graceful degrade: when no persisted record exists (e.g. corrupt/
    /// missing blob), the loader falls back to the ordinary deferred,
    /// first-click-safe session — never blocks the replay.
    @Test
    func fallsBackToDeferredSessionWhenNoRecordExists() async throws {
        let store = makeStore(FakePrivateCKGateway())
        let session = try await MinesweeperDailyReplayLoaderView.makeReplaySession(
            difficulty: .beginner, seed: 99, recordName: "no-such-record", store: store, errorReporter: nil
        )
        // Deferred placement: mines aren't placed until the first reveal, and
        // that reveal is still first-click-safe (no persisted layout to override it).
        let idle = await session.snapshot()
        #expect(idle.mineIndices.isEmpty)
        let snap = try await session.reveal(row: 4, col: 4)
        let offsets = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 0), (0, 1), (1, -1), (1, 0), (1, 1)]
        for (rowOffset, colOffset) in offsets {
            let neighborRow = 4 + rowOffset, neighborCol = 4 + colOffset
            #expect(!snap.cells[neighborRow * snap.columns + neighborCol].isMine)
        }
    }

    // MARK: - Round 2 (adversarial CR): honest failure on fetch errors

    /// THE round-2 regression this suite guards against: a transient network
    /// error (existence unknown, NOT "confirmed absent") must NOT fall back
    /// to a freshly-derived board — that would silently reproduce the exact
    /// #841 bug behind a WiFi blip. `makeReplaySession` must propagate the
    /// error (→ `load()` lands the view in `.failed`), never swallow it into
    /// a `MinesweeperSession(difficulty:seed:)` fallback.
    @Test
    func networkFailureDuringFetchThrowsInsteadOfFallingBackToADifferentBoard() async throws {
        // CKError code 4 == .networkUnavailable → UserFacingError.classify
        // maps this to `.networkUnavailable`, exactly the class of error the
        // sibling `MinesweeperBoardLoaderView` also treats as a real failure
        // (not a "no save" degrade — that's reserved for `.iCloudSignedOut`).
        let gateway = ThrowingFetchGateway(
            fetchError: NSError(domain: "CKErrorDomain", code: 4)
        )
        let store = MinesweeperSavedGameStore(gateway: gateway, clock: { Self.fixedDate })

        await #expect(throws: (any Error).self) {
            _ = try await MinesweeperDailyReplayLoaderView.makeReplaySession(
                difficulty: .beginner, seed: 99, recordName: Self.recordName, store: store, errorReporter: nil
            )
        }
    }

    /// Same failure, asserted precisely: the thrown error classifies to
    /// `.networkUnavailable` — the exact bucket `load()`'s catch hands to
    /// `state = .failed(_)`.
    @Test
    func networkFailureClassifiesAsNetworkUnavailable() async throws {
        let gateway = ThrowingFetchGateway(
            fetchError: NSError(domain: "CKErrorDomain", code: 4)
        )
        let store = MinesweeperSavedGameStore(gateway: gateway, clock: { Self.fixedDate })

        do {
            _ = try await MinesweeperDailyReplayLoaderView.makeReplaySession(
                difficulty: .beginner, seed: 99, recordName: Self.recordName, store: store, errorReporter: nil
            )
            Issue.record("expected makeReplaySession to throw on a network failure")
        } catch {
            #expect(UserFacingError.classify(error) == .networkUnavailable)
        }
    }
}

/// Fetch-throwing gateway fake — mirrors `ThrowingQueryGateway` /
/// `ThrowingSnapshotGateway` used by the MinesweeperPersistenceTests suites
/// (kept local: those fakes are `private` / file-scoped).
private actor ThrowingFetchGateway: PrivateCKGateway {
    private let fetchError: (any Error & Sendable)?

    init(fetchError: (any Error & Sendable)? = nil) {
        self.fetchError = fetchError
    }

    func provisionZone() async throws {}
    func installSubscriptionIfNeeded() async throws {}

    func fetch(recordName: String) async throws -> RecordPayload? {
        if let error = fetchError { throw error }
        return nil
    }

    func save(_ payload: RecordPayload, policy: RecordSavePolicy) async throws {}
    func delete(recordName: String) async throws {}

    func query(_ predicate: RecordPredicate) async throws -> [RecordPayload] {
        []
    }
}
