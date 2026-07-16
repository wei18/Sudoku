// LivePersistence — public production facade composing the Live stores
// behind the `PersistenceProtocol` seam.
//
// Per docs/v1/design.md §How.1 (DI composition root): the App target should not have
// to know about the internal split between `SavedGameStore`,
// `PersonalRecordStore`, and `LivePrivateCKGateway`. This facade is the
// single public entry that `SudokuAppComposition.live(...)` constructs.
//
// The CloudKit-talking parts (`LivePrivateCKGateway`, zone provisioning,
// subscription installation) stay internal to this module — only this
// facade is exposed.

public import Foundation
public import SudokuGameState
public import SudokuEngine
public import Telemetry

public actor LivePersistence: PersistenceProtocol {

    public typealias PuzzleLoader = @Sendable (String) async throws -> Puzzle

    private let telemetry: Telemetry
    private let puzzleLoader: PuzzleLoader
    // `nonisolated` so the `monetizationStateStore()` factory below can
    // read it without hopping into the actor. Safe — `PrivateCKConfig` is
    // an immutable `Sendable` value.
    private nonisolated let ckConfig: PrivateCKConfig

    // Lazy: `CKContainer.default()` traps when invoked outside a properly
    // configured app bundle (entitlements + container id). Deferring
    // construction lets `SudokuAppComposition.live()` be safely called from unit
    // tests that do not own those entitlements — IO calls would fail later,
    // but the wiring is exercised.
    private var _gateway: LivePrivateCKGateway?
    private var _savedGameStore: SavedGameStore?
    private var _personalRecordStore: PersonalRecordStore?

    public init(
        telemetry: Telemetry,
        ckConfig: PrivateCKConfig,
        puzzleLoader: @escaping PuzzleLoader
    ) {
        self.telemetry = telemetry
        self.ckConfig = ckConfig
        self.puzzleLoader = puzzleLoader
    }

    private func gateway() -> LivePrivateCKGateway {
        if let existing = _gateway { return existing }
        let gateway = LivePrivateCKGateway(config: ckConfig)
        _gateway = gateway
        return gateway
    }

    private func savedGameStore() -> SavedGameStore {
        if let existing = _savedGameStore { return existing }
        let store = SavedGameStore(
            gateway: gateway(),
            telemetry: telemetry,
            puzzleLoader: puzzleLoader
        )
        _savedGameStore = store
        return store
    }

    private func personalRecordStore() -> PersonalRecordStore {
        if let existing = _personalRecordStore { return existing }
        let store = PersonalRecordStore(gateway: gateway())
        _personalRecordStore = store
        return store
    }

    /// Lazy one-time CloudKit zone + subscription provisioning. Safe to
    /// call multiple times — the gateway no-ops after the first success.
    public func bootstrap() async throws {
        let gateway = gateway()
        try await gateway.provisionZone()
        try await gateway.installSubscriptionIfNeeded()
    }

    // MARK: - PersistenceProtocol

    public func latestInProgress() async throws -> SavedGameSummary? {
        try await savedGameStore().latestInProgress()
    }

    public func loadOrCreate(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> GameSessionSnapshot {
        try await savedGameStore().loadOrCreate(
            puzzleId: puzzleId,
            mode: mode,
            difficulty: difficulty
        )
    }

    public func loadIfExists(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> GameSessionSnapshot? {
        try await savedGameStore().loadIfExists(
            puzzleId: puzzleId,
            mode: mode,
            difficulty: difficulty
        )
    }

    public func save(
        _ snapshot: GameSessionSnapshot,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws {
        try await savedGameStore().save(
            snapshot,
            puzzleId: puzzleId,
            mode: mode,
            difficulty: difficulty
        )
    }

    public func markCompleted(_ summary: SavedGameSummary) async throws {
        try await savedGameStore().markCompleted(summary)
    }

    public func deleteAbandoned(recordName: String) async throws {
        try await savedGameStore().deleteAbandoned(recordName: recordName)
    }

    public func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> {
        try await savedGameStore().fetchCompletedDailyIds(for: date)
    }

    public func fetchPersonalRecord(
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> PersonalRecord {
        try await personalRecordStore().fetch(mode: mode, difficulty: difficulty)
    }

    public func upsertPersonalRecord(_ record: PersonalRecord) async throws {
        try await personalRecordStore().upsert(record)
    }

    /// #552: override default impl with the optimistic retry path.
    public func recordPuzzleCompletion(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty,
        elapsedSeconds: Int
    ) async throws {
        try await personalRecordStore().recordCompletion(
            puzzleId: puzzleId,
            mode: mode,
            difficulty: difficulty,
            elapsedSeconds: elapsedSeconds
        )
    }

    // MARK: - Monetization wiring helper (v2.3.1)

    /// Construct a `LiveMonetizationStateStore` that shares this facade's
    /// underlying `PrivateCKGateway`. SudokuAppComposition.live calls this to wire
    /// AdGate without having to know about the gateway type (which stays
    /// internal to this module).
    ///
    /// `nonisolated` so `SudokuAppComposition.live()` stays sync. Returns a fresh
    /// `LiveMonetizationStateStore` whose own lazy provider does the
    /// CloudKit hop on first IO — symmetric to other store factories above.
    public nonisolated func monetizationStateStore() -> LiveMonetizationStateStore {
        let config = ckConfig
        return LiveMonetizationStateStore(
            gatewayProvider: {
                // Fresh gateway per store — observationally identical to
                // routing through actor `self.gateway()` (lazy CKContainer
                // construction is the only state to share, and CK's
                // identity-on-container guarantees idempotent zone /
                // subscription install).
                LivePrivateCKGateway(config: config)
            }
        )
    }
}
