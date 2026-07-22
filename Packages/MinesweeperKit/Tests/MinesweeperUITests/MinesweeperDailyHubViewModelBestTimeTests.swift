// MinesweeperDailyHubViewModelBestTimeTests — #886 per-difficulty
// best-DAILY-time overlay. Mirrors SudokuKit's
// `DailyHubViewModelBestTimeTests`.
//
// Pins `MinesweeperDailyHubViewModel.fetchBestTimes`'s contract: rides the
// existing phase-2 `fillCompletionAndFailureOverlay` window, reads
// `personalRecordStore.fetch(modeRaw: "daily", difficulty:)` — the same seam
// `MinesweeperStatsViewModel.fetchTiles` already uses — and degrades PER
// DIFFICULTY independently (unlike the week-strip's all-or-nothing degrade):
// one difficulty's fetch failing must not blank out the other two. Uses the
// real `MinesweeperPersonalRecordStore` over an in-memory
// `FakePrivateCKGateway` (the store's established test seam — see
// `MinesweeperStatsTests.swift`), with the #886 per-recordName error
// injection added to the gateway for the degrade test.
//
// #941: also pins the concurrency fix itself — the 3 per-difficulty fetches
// now run in a `TaskGroup` instead of a serial `for` loop (see
// `bestTimeFetchesRunConcurrentlyAndAssembleOrderIndependently` below).

import Foundation
import Testing
import MinesweeperEngine
import MinesweeperPersistence
import Persistence
import PersistenceTesting
import Telemetry
@testable import MinesweeperUI

@MainActor
@Suite("MinesweeperDailyHubViewModel — best-time overlay (#886)")
struct MinesweeperDailyHubViewModelBestTimeTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    private func makeViewModel(gateway: FakePrivateCKGateway) -> MinesweeperDailyHubViewModel {
        MinesweeperDailyHubViewModel(
            path: .constant([]),
            personalRecordStore: MinesweeperPersonalRecordStore(gateway: gateway, clock: { Self.fixedDate }),
            dateProvider: { Self.fixedDate }
        )
    }

    /// Happy path: every difficulty's `fetch` succeeds with a real best time
    /// (seeded via real `recordCompletion` calls — the store's own test
    /// seam) — all three cards carry it after bootstrap.
    @Test func bootstrapMergesBestTimePerDifficulty() async throws {
        let gateway = FakePrivateCKGateway()
        let store = MinesweeperPersonalRecordStore(gateway: gateway, clock: { Self.fixedDate })
        try await store.recordCompletion(puzzleId: "d-b-1", modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 55)
        try await store.recordCompletion(puzzleId: "d-i-1", modeRaw: "daily", difficulty: .intermediate, elapsedSeconds: 240)
        try await store.recordCompletion(puzzleId: "d-e-1", modeRaw: "daily", difficulty: .expert, elapsedSeconds: 610)
        let viewModel = makeViewModel(gateway: gateway)

        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(cards.first { $0.difficulty == .beginner }?.bestTimeSeconds == 55)
        #expect(cards.first { $0.difficulty == .intermediate }?.bestTimeSeconds == 240)
        #expect(cards.first { $0.difficulty == .expert }?.bestTimeSeconds == 610)
    }

    /// Never-completed difficulty: no `recordCompletion` seeded — the store
    /// returns `MinesweeperPersonalRecord.empty(...)`, `bestTimeSeconds ==
    /// nil` — renders "—", same as a fetch failure (per the #886 spec's
    /// deliberate collapse).
    @Test func neverCompletedDifficultyRendersNilBestTime() async {
        let viewModel = makeViewModel(gateway: FakePrivateCKGateway())

        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(cards.allSatisfy { $0.bestTimeSeconds == nil })
    }

    /// No `personalRecordStore` injected at all (preview / legacy test
    /// callsites) — every card's `bestTimeSeconds` stays `nil`, never blocks.
    @Test func nilStoreRendersNilBestTimes() async {
        let viewModel = MinesweeperDailyHubViewModel(path: .constant([]), dateProvider: { Self.fixedDate })

        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(cards.allSatisfy { $0.bestTimeSeconds == nil })
    }

    /// #886's central contract: a fetch failure on ONE difficulty's
    /// `PersonalRecord` (scoped via the #886 per-recordName gateway error)
    /// must not blank the others — per-difficulty independent try/catch
    /// (`fetchBestTimes`), unlike `fetchWeekWindow`'s all-or-nothing degrade.
    @Test func perDifficultyFetchFailureDegradesOnlyThatDifficulty() async throws {
        let gateway = FakePrivateCKGateway()
        let store = MinesweeperPersonalRecordStore(gateway: gateway, clock: { Self.fixedDate })
        try await store.recordCompletion(puzzleId: "d-b-1", modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 40)
        try await store.recordCompletion(puzzleId: "d-e-1", modeRaw: "daily", difficulty: .expert, elapsedSeconds: 500)
        // Intermediate's PersonalRecord fetch fails; beginner/expert's
        // `save`-established records are stored under their own recordNames
        // and unaffected.
        await gateway.setFetchError(PersistenceError.iCloudNotSignedIn, forRecordName: "daily-intermediate")
        let reporter = FakeErrorReporter()
        let viewModel = MinesweeperDailyHubViewModel(
            path: .constant([]),
            personalRecordStore: store,
            errorReporter: reporter,
            dateProvider: { Self.fixedDate }
        )

        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(cards.first { $0.difficulty == .beginner }?.bestTimeSeconds == 40)
        #expect(cards.first { $0.difficulty == .intermediate }?.bestTimeSeconds == nil)
        #expect(cards.first { $0.difficulty == .expert }?.bestTimeSeconds == 500)
        #expect(await reporter.received.count == 1)
    }

    /// A week-window degrade (no `savedGameStore` injected) must not
    /// suppress best times — they are an independent read with no
    /// false-claim risk (see `fillCompletionAndFailureOverlay`'s doc comment).
    @Test func weekWindowDegradeStillMergesBestTimes() async throws {
        let gateway = FakePrivateCKGateway()
        let store = MinesweeperPersonalRecordStore(gateway: gateway, clock: { Self.fixedDate })
        try await store.recordCompletion(puzzleId: "d-b-1", modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 33)
        let viewModel = makeViewModel(gateway: gateway) // no savedGameStore → week window always nil

        await viewModel.bootstrap()

        #expect(viewModel.weekStrip == .unknown)
        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(cards.first { $0.difficulty == .beginner }?.bestTimeSeconds == 33)
        #expect(cards.allSatisfy { !$0.isCompleted && !$0.isFailed })
    }

    /// #941: proves `fetchBestTimes`'s 3 per-difficulty fetches are actually
    /// concurrent (not merely non-blocking) AND that the final merge is
    /// order-independent — releasing them in a different order than they
    /// arrived must not cross-assign a value to the wrong difficulty. Seeds
    /// real records via `recordCompletion` on a plain gateway first (the
    /// store's own test seam), then wraps that same gateway's `fetch` in a
    /// per-recordName gate so the VM's actual fetch calls are the ones
    /// delayed/released — not the seeding calls.
    @Test func bestTimeFetchesRunConcurrentlyAndAssembleOrderIndependently() async throws {
        let underlying = FakePrivateCKGateway()
        let seedStore = MinesweeperPersonalRecordStore(gateway: underlying, clock: { Self.fixedDate })
        try await seedStore.recordCompletion(puzzleId: "d-b-1", modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 42)
        try await seedStore.recordCompletion(puzzleId: "d-i-1", modeRaw: "daily", difficulty: .intermediate, elapsedSeconds: 900)
        try await seedStore.recordCompletion(puzzleId: "d-e-1", modeRaw: "daily", difficulty: .expert, elapsedSeconds: 500)

        let gated = GatedFetchGateway(delegate: underlying)
        let store = MinesweeperPersonalRecordStore(gateway: gated, clock: { Self.fixedDate })
        let viewModel = MinesweeperDailyHubViewModel(
            path: .constant([]),
            personalRecordStore: store,
            dateProvider: { Self.fixedDate }
        )

        let bootstrapTask = Task { await viewModel.bootstrap() }

        // Wait until all THREE per-difficulty fetches have reached the gate —
        // a serial loop would only ever have ONE in flight at a time, so this
        // would hang forever under the pre-#941 implementation.
        while await gated.arrivedRecordNames.count < 3 {
            await Task.yield()
        }
        #expect(Set(await gated.arrivedRecordNames) == ["daily-beginner", "daily-intermediate", "daily-expert"])

        // Release in a DIFFERENT order than they arrived — proves the final
        // merge keys off `Difficulty`, not completion order.
        await gated.release("daily-expert")
        await gated.release("daily-beginner")
        await gated.release("daily-intermediate")

        await bootstrapTask.value

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(cards.first { $0.difficulty == .beginner }?.bestTimeSeconds == 42)
        #expect(cards.first { $0.difficulty == .intermediate }?.bestTimeSeconds == 900)
        #expect(cards.first { $0.difficulty == .expert }?.bestTimeSeconds == 500)
    }
}

// MARK: - GatedFetchGateway

/// A `PrivateCKGateway` decorator whose `fetch(recordName:)` hangs per
/// `recordName` until individually `release`d — every other operation
/// delegates straight through to `delegate` (a real, pre-seeded
/// `FakePrivateCKGateway`) unchanged. Lets a test seed data via the store's
/// normal `recordCompletion` write path first, then gate ONLY the read calls
/// the view model itself issues.
private actor GatedFetchGateway: PrivateCKGateway {
    private let delegate: FakePrivateCKGateway
    private var continuations: [String: [CheckedContinuation<Void, Never>]] = [:]
    private(set) var arrivedRecordNames: [String] = []

    init(delegate: FakePrivateCKGateway) {
        self.delegate = delegate
    }

    func release(_ recordName: String) {
        let waiting = continuations.removeValue(forKey: recordName) ?? []
        for continuation in waiting {
            continuation.resume()
        }
    }

    func provisionZone() async throws { try await delegate.provisionZone() }
    func installSubscriptionIfNeeded() async throws { try await delegate.installSubscriptionIfNeeded() }
    func save(_ payload: RecordPayload, policy: RecordSavePolicy) async throws {
        try await delegate.save(payload, policy: policy)
    }
    func delete(recordName: String) async throws { try await delegate.delete(recordName: recordName) }
    func query(_ predicate: RecordPredicate) async throws -> [RecordPayload] { try await delegate.query(predicate) }

    func fetch(recordName: String) async throws -> RecordPayload? {
        arrivedRecordNames.append(recordName)
        await withCheckedContinuation { continuation in
            continuations[recordName, default: []].append(continuation)
        }
        return try await delegate.fetch(recordName: recordName)
    }
}
