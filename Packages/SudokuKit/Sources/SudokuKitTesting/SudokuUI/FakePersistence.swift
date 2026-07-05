// FakePersistence — scripted `PersistenceProtocol` for SudokuUI tests.
//
// Tracks every method invocation so VMs can assert call shape (e.g.
// "bootstrap calls latestInProgress exactly once"). State is scripted
// upfront; no CloudKit involvement.

public import Foundation
public import SudokuGameState
public import Persistence
public import SudokuEngine

public actor FakePersistence: PersistenceProtocol {

    public enum Operation: Sendable, Equatable, Hashable {
        case bootstrap
        case latestInProgress
        case loadOrCreate(puzzleId: String)
        case save(puzzleId: String)
        case markCompleted(recordName: String)
        case deleteAbandoned(recordName: String)
        case fetchCompletedDailyIds(date: Date)
        case fetchPersonalRecord(mode: Mode, difficulty: Difficulty)
        case upsertPersonalRecord(recordName: String)
    }

    public private(set) var operations: [Operation] = []

    public var resumeCandidate: SavedGameSummary?
    public var completedDailyIds: Set<String> = []
    public var personalRecord: PersonalRecord = PersonalRecord(
        recordName: "",
        // M5 (issue #65): default mode/difficulty must be valid enum cases;
        // tests that exercise this fake's PersonalRecord path override
        // `personalRecord` explicitly.
        mode: .daily,
        difficulty: .easy,
        bestTimeSeconds: nil,
        totalTimeSeconds: 0,
        completedCount: 0,
        lastUpdatedAt: Date(timeIntervalSince1970: 0),
        completedPuzzleIds: []
    )
    public var loadOrCreateError: PersistenceError?
    public var latestInProgressError: PersistenceError?
    public var deleteAbandonedError: PersistenceError?
    /// When set, `loadOrCreate` returns this snapshot instead of the loud
    /// default throw. Used by tests that exercise the completed-daily
    /// → Completion route (#379).
    public var loadOrCreateSnapshot: GameSessionSnapshot?

    public init(
        resumeCandidate: SavedGameSummary? = nil,
        completedDailyIds: Set<String> = []
    ) {
        self.resumeCandidate = resumeCandidate
        self.completedDailyIds = completedDailyIds
    }

    public func setResumeCandidate(_ candidate: SavedGameSummary?) {
        self.resumeCandidate = candidate
    }

    public func setCompletedDailyIds(_ ids: Set<String>) {
        self.completedDailyIds = ids
    }

    public func setLatestInProgressError(_ error: PersistenceError?) {
        self.latestInProgressError = error
    }

    public func setDeleteAbandonedError(_ error: PersistenceError?) {
        self.deleteAbandonedError = error
    }

    public func setLoadOrCreateSnapshot(_ snapshot: GameSessionSnapshot?) {
        self.loadOrCreateSnapshot = snapshot
    }

    public func setLoadOrCreateError(_ error: PersistenceError?) {
        self.loadOrCreateError = error
    }

    // MARK: - PersistenceProtocol

    public var bootstrapError: PersistenceError?

    public func setBootstrapError(_ error: PersistenceError?) {
        self.bootstrapError = error
    }

    public func bootstrap() async throws {
        operations.append(.bootstrap)
        if let error = bootstrapError {
            throw error
        }
    }

    public func latestInProgress() async throws -> SavedGameSummary? {
        operations.append(.latestInProgress)
        if let error = latestInProgressError {
            throw error
        }
        return resumeCandidate
    }

    public func loadOrCreate(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> GameSessionSnapshot {
        operations.append(.loadOrCreate(puzzleId: puzzleId))
        if let error = loadOrCreateError {
            throw error
        }
        if let snapshot = loadOrCreateSnapshot {
            return snapshot
        }
        // Fake target: tests that hit this path should use a real fixture
        // (`setLoadOrCreateSnapshot`) or override `loadOrCreateError`. Default
        // raises zoneNotProvisioned so accidental hits are loud.
        throw PersistenceError.zoneNotProvisioned
    }

    public func save(
        _ snapshot: GameSessionSnapshot,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws {
        _ = (mode, difficulty)
        operations.append(.save(puzzleId: puzzleId))
    }

    public func markCompleted(_ summary: SavedGameSummary) async throws {
        operations.append(.markCompleted(recordName: summary.recordName))
    }

    public func deleteAbandoned(recordName: String) async throws {
        operations.append(.deleteAbandoned(recordName: recordName))
        if let error = deleteAbandonedError {
            throw error
        }
    }

    public func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> {
        operations.append(.fetchCompletedDailyIds(date: date))
        return completedDailyIds
    }

    public func fetchPersonalRecord(
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> PersonalRecord {
        operations.append(.fetchPersonalRecord(mode: mode, difficulty: difficulty))
        return personalRecord
    }

    public func upsertPersonalRecord(_ record: PersonalRecord) async throws {
        operations.append(.upsertPersonalRecord(recordName: record.recordName))
        self.personalRecord = record
    }
}
