// PrivateCKGateway — narrow protocol abstracting CloudKit Private DB ops.
//
// Persistence target uses this seam so:
//   - the public surface stays CloudKit-free (Telemetry, GameState don't
//     transitively import CloudKit);
//   - tests run via `FakePrivateCKGateway` (in SudokuKitTesting) without
//     touching live iCloud — see plan.md Phase 5 note (live validation
//     deferred to Phase 10).
//
// Field-level CKRecord encoding is done via a small `RecordPayload` value
// type so the protocol does not import CloudKit either. The Live impl
// (Sources/Persistence/Live/PrivateCKGateway.swift) imports CloudKit and
// performs `RecordPayload ↔ CKRecord` mapping at the seam.

public import Foundation

/// Wire-level value bag for a single record. Keys correspond to CloudKit
/// field names (§How.2). Values are restricted to a small primitive set
/// (`String`, `Int`, `Date`, `Data`, `[String]`).
public enum RecordValue: Sendable, Equatable, Hashable {
    case string(String)
    case int(Int)
    case date(Date)
    case data(Data)
    case stringSet([String])
}

public struct RecordPayload: Sendable, Equatable, Hashable {
    public let recordType: String
    public let recordName: String
    public var fields: [String: RecordValue]

    public init(recordType: String, recordName: String, fields: [String: RecordValue]) {
        self.recordType = recordType
        self.recordName = recordName
        self.fields = fields
    }
}

/// Predicate hooks used by `query` / `fetch`. Kept enum-shaped so the Fake
/// doesn't need to evaluate `NSPredicate`. Only the subset Persistence
/// actually issues is encoded here.
public enum RecordPredicate: Sendable, Equatable, Hashable {
    case all(recordType: String)
    case statusEquals(recordType: String, status: String)
    case dailyCompletedOn(dayPrefix: String)   // puzzleId hasPrefix dayPrefix
}

public protocol PrivateCKGateway: Sendable {

    // MARK: - Zone

    func provisionZone() async throws

    // MARK: - Subscription

    func installSubscriptionIfNeeded() async throws

    // MARK: - CRUD

    func fetch(recordName: String) async throws -> RecordPayload?
    func save(_ payload: RecordPayload) async throws
    func delete(recordName: String) async throws
    func query(_ predicate: RecordPredicate) async throws -> [RecordPayload]
}

// MARK: - Constants

public enum PrivateCKConstants {
    public static let zoneName = "com.wei18.sudoku.userZone"
    public static let subscriptionID = "com.wei18.sudoku.userZone.changes"
    public static let savedGameRecordType = "SavedGame"
    public static let personalRecordRecordType = "PersonalRecord"
}
