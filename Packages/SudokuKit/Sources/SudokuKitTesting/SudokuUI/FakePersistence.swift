// FakePersistence — scripted `PersistenceProtocol` for SudokuUI tests.
//
// Tracks every method invocation so VMs can assert call shape (e.g.
// "bootstrap calls latestInProgress exactly once"). State is scripted
// upfront; no CloudKit involvement.

public import Foundation
public import GameState
public import Persistence

public actor FakePersistence: PersistenceProtocol {

    public enum Operation: Sendable, Equatable, Hashable {
        case latestInProgress
        case loadOrCreate(puzzleId: String)
        case save(puzzleId: String)
        case markCompleted(recordName: String)
        case deleteAbandoned(recordName: String)
        case fetchCompletedDailyIds(date: Date)
        case fetchPersonalRecord(mode: String, difficulty: String)
        case upsertPersonalRecord(recordName: String)
    }

    public private(set) var operations: [Operation] = []

    public var resumeCandidate: SavedGameSummary?
    public var completedDailyIds: Set<String> = []
    public var personalRecord: PersonalRecord = PersonalRecord(
        recordName: "",
        mode: "",
        difficulty: "",
        bestTimeSeconds: nil,
        totalTimeSeconds: 0,
        completedCount: 0,
        lastUpdatedAt: Date(timeIntervalSince1970: 0),
        completedPuzzleIds: []
    )
    public var loadOrCreateError: PersistenceError?
    public var latestInProgressError: PersistenceError?

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

    // MARK: - PersistenceProtocol

    public func latestInProgress() async throws -> SavedGameSummary? {
        operations.append(.latestInProgress)
        if let error = latestInProgressError {
            throw error
        }
        return resumeCandidate
    }

    public func loadOrCreate(
        puzzleId: String,
        mode: String,
        difficulty: String
    ) async throws -> GameSessionSnapshot {
        operations.append(.loadOrCreate(puzzleId: puzzleId))
        if let error = loadOrCreateError {
            throw error
        }
        // Fake target: tests that hit this path should use a real fixture
        // or override `loadOrCreateError`. Default raises zoneNotProvisioned
        // so accidental hits are loud.
        throw PersistenceError.zoneNotProvisioned
    }

    public func save(_ snapshot: GameSessionSnapshot) async throws {
        // Puzzle has no embedded puzzleId; use seed as the identity proxy.
        operations.append(.save(puzzleId: String(snapshot.puzzle.seed)))
    }

    public func markCompleted(_ summary: SavedGameSummary) async throws {
        operations.append(.markCompleted(recordName: summary.recordName))
    }

    public func deleteAbandoned(recordName: String) async throws {
        operations.append(.deleteAbandoned(recordName: recordName))
    }

    public func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> {
        operations.append(.fetchCompletedDailyIds(date: date))
        return completedDailyIds
    }

    public func fetchPersonalRecord(
        mode: String,
        difficulty: String
    ) async throws -> PersonalRecord {
        operations.append(.fetchPersonalRecord(mode: mode, difficulty: difficulty))
        return personalRecord
    }

    public func upsertPersonalRecord(_ record: PersonalRecord) async throws {
        operations.append(.upsertPersonalRecord(recordName: record.recordName))
        self.personalRecord = record
    }
}
