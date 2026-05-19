// LivePersistence — public production facade composing the Live stores
// behind the `PersistenceProtocol` seam.
//
// Per design.md §How.1 (DI composition root): the App target should not have
// to know about the internal split between `SavedGameStore`,
// `PersonalRecordStore`, `LivePrivateCKGateway`, `AccountMonitor`, or
// `SubscriptionInstaller`. This facade is the single public entry that
// `AppComposition.live(...)` constructs.
//
// The CloudKit-talking parts (`LivePrivateCKGateway`, zone provisioning,
// subscription installation) stay internal to this module — only this
// facade is exposed.

public import Foundation
public import GameState
public import SudokuEngine
public import Telemetry

public final class LivePersistence: PersistenceProtocol, @unchecked Sendable {

    public typealias PuzzleLoader = @Sendable (String) async throws -> Puzzle

    private let telemetry: Telemetry
    private let puzzleLoader: PuzzleLoader

    // Lazy: `CKContainer.default()` traps when invoked outside a properly
    // configured app bundle (entitlements + container id). Deferring
    // construction lets `AppComposition.live()` be safely called from unit
    // tests that do not own those entitlements — IO calls would fail later,
    // but the wiring is exercised.
    private let lock = NSLock()
    private var _gateway: LivePrivateCKGateway?
    private var _savedGameStore: SavedGameStore?
    private var _personalRecordStore: PersonalRecordStore?

    public init(
        telemetry: Telemetry,
        puzzleLoader: @escaping PuzzleLoader
    ) {
        self.telemetry = telemetry
        self.puzzleLoader = puzzleLoader
    }

    private func gateway() -> LivePrivateCKGateway {
        lock.lock()
        defer { lock.unlock() }
        if let existing = _gateway { return existing }
        let gateway = LivePrivateCKGateway()
        _gateway = gateway
        return gateway
    }

    private func savedGameStore() -> SavedGameStore {
        lock.lock()
        defer { lock.unlock() }
        if let existing = _savedGameStore { return existing }
        let gateway = _gateway ?? {
            let gateway = LivePrivateCKGateway()
            _gateway = gateway
            return gateway
        }()
        let store = SavedGameStore(
            gateway: gateway,
            telemetry: telemetry,
            puzzleLoader: puzzleLoader
        )
        _savedGameStore = store
        return store
    }

    private func personalRecordStore() -> PersonalRecordStore {
        lock.lock()
        defer { lock.unlock() }
        if let existing = _personalRecordStore { return existing }
        let gateway = _gateway ?? {
            let gateway = LivePrivateCKGateway()
            _gateway = gateway
            return gateway
        }()
        let store = PersonalRecordStore(gateway: gateway)
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
        mode: String,
        difficulty: String
    ) async throws -> GameSessionSnapshot {
        try await savedGameStore().loadOrCreate(
            puzzleId: puzzleId,
            mode: mode,
            difficulty: difficulty
        )
    }

    public func save(_ snapshot: GameSessionSnapshot) async throws {
        try await savedGameStore().save(snapshot)
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
        mode: String,
        difficulty: String
    ) async throws -> PersonalRecord {
        try await personalRecordStore().fetch(mode: mode, difficulty: difficulty)
    }

    public func upsertPersonalRecord(_ record: PersonalRecord) async throws {
        try await personalRecordStore().upsert(record)
    }
}
