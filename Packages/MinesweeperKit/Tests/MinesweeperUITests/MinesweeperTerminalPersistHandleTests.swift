// MinesweeperTerminalPersistHandleTests — pins the #823 round-2 CR gap:
// `pendingTerminalPersistTask` must be non-nil before the FIRST post-flip
// suspension in `reveal()`'s terminal chain.
//
// The round-1 shape assigned the handle only around the persist step — AFTER
// `submitWinIfWon()` / `evaluateAchievementsIfWon()`, both real suspending
// network I/O on the standard win path (the personal-record write runs for
// daily AND practice since #705). The `snapshot` terminal flip makes the
// completion overlay tappable at the next scheduler slot, so a fast Close
// during those awaits read a nil handle → `TerminalPersistJoin.register(nil)`
// → `awaitPending()` no-oped → the original #823 race reproduced.
//
// This test gates the win chain's first suspension (the personal-record
// gateway) and asserts the handle is already published while that gate is
// still closed — deterministically red on the round-1 shape, green on the
// "whole chain in one synchronously-assigned Task" shape.

import Foundation
import Testing
@testable import MinesweeperUI
import MinesweeperEngine
import MinesweeperGameState
import Persistence
import PersistenceTesting
import Telemetry
@testable import MinesweeperPersistence

// MARK: - Gate (continuation-based, deterministic)

/// Same primitive as GameAppKit's `TerminalPersistJoinTests.Gate`: signaled,
/// not timed, so "still blocked" assertions can never pass spuriously.
private actor Gate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

// MARK: - Gated gateway

/// Wraps a `FakePrivateCKGateway`; every call first awaits the gate. Injected
/// under the personal-record store so `submitWinIfWon()` — the first
/// suspension after the terminal flip — hangs until the test opens the gate.
private final class GatedPrivateCKGateway: PrivateCKGateway {
    private let gate: Gate
    private let inner: FakePrivateCKGateway

    init(gate: Gate, inner: FakePrivateCKGateway) {
        self.gate = gate
        self.inner = inner
    }

    func provisionZone() async throws {
        await gate.wait()
        try await inner.provisionZone()
    }

    func installSubscriptionIfNeeded() async throws {
        await gate.wait()
        try await inner.installSubscriptionIfNeeded()
    }

    func fetch(recordName: String) async throws -> RecordPayload? {
        await gate.wait()
        return try await inner.fetch(recordName: recordName)
    }

    func save(_ payload: RecordPayload, policy: RecordSavePolicy) async throws {
        await gate.wait()
        try await inner.save(payload, policy: policy)
    }

    func delete(recordName: String) async throws {
        await gate.wait()
        try await inner.delete(recordName: recordName)
    }

    func query(_ predicate: RecordPredicate) async throws -> [RecordPayload] {
        await gate.wait()
        return try await inner.query(predicate)
    }
}

// MARK: - Tests

@MainActor
@Suite("MinesweeperGameViewModel — terminal-persist handle invariant (#823)")
struct MinesweeperTerminalPersistHandleTests {

    // nonisolated: referenced from the store's @Sendable clock closure.
    private nonisolated static let fixedDate = Date(timeIntervalSince1970: 1_750_000_000)

    /// Drive the view model to a win by revealing every non-mine cell
    /// (mirrors `MinesweeperGameCenterSubmitTests.driveToWin`).
    private func driveToWin(_ viewModel: MinesweeperGameViewModel) async {
        await viewModel.reveal(row: 0, col: 0)
        var progressed = true
        while viewModel.status == .playing && progressed {
            progressed = false
            for row in 0..<viewModel.rows {
                for col in 0..<viewModel.columns {
                    let cell = viewModel.cell(row: row, col: col)
                    if !cell.isMine && cell.state != .revealed {
                        await viewModel.reveal(row: row, col: col)
                        progressed = true
                        if viewModel.status != .playing { return }
                    }
                }
            }
        }
    }

    @Test func handleIsPublishedBeforeFirstPostFlipSuspension() async throws {
        let gate = Gate()
        // Two gateways: the GATED one under the personal-record store (the
        // win chain's first suspension); a plain one under the saved-game
        // store so the final persist step is observable once the gate opens.
        let gatedGateway = GatedPrivateCKGateway(gate: gate, inner: FakePrivateCKGateway())
        let saveGateway = FakePrivateCKGateway()
        let recordName = "practice-beginner"
        let viewModel = MinesweeperGameViewModel(
            difficulty: .beginner,
            seed: 42,
            mode: .practice,
            store: MinesweeperSavedGameStore(gateway: saveGateway, clock: { Self.fixedDate }),
            recordName: recordName,
            personalRecordStore: MinesweeperPersonalRecordStore(gateway: gatedGateway)
        )

        #expect(viewModel.pendingTerminalPersistTask == nil)

        // The winning reveal blocks inside reveal() on the gated
        // personal-record write, so drive in a background Task and poll for
        // the terminal flip (published synchronously before any post-flip
        // suspension).
        let drive = Task { await driveToWin(viewModel) }
        var iterations = 0
        while viewModel.status != .won && iterations < 10_000 {
            await Task.yield()
            iterations += 1
        }
        #expect(viewModel.status == .won)

        // THE INVARIANT: the gate is still closed — the win chain is parked
        // on its first suspension — yet the handle must already be
        // registered, because this is exactly the window in which a fast
        // Close tap reads it (round-1 CR: it was nil here).
        #expect(viewModel.pendingTerminalPersistTask != nil)
        // And the terminal persist has NOT landed yet (MS has no mid-play
        // autosave, so the record must not exist at all while gated).
        #expect(try await saveGateway.fetch(recordName: recordName) == nil)

        // Open the gate: the chain must run to completion and the persist
        // must land with the terminal wire status.
        await gate.open()
        await drive.value
        await viewModel.pendingTerminalPersistTask?.value

        let payload = try #require(await saveGateway.fetch(recordName: recordName))
        #expect(payload.fields["status"] == .string("completed"))
    }
}
