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
    /// #552: the server record's archived `encodeSystemFields` (recordID +
    /// etag/change-tag). Carried so an `.ifUnchanged` save re-uses the live
    /// etag. `nil` for a brand-new, never-saved record.
    /// Excluded from `Equatable`/`Hashable` (concurrency metadata, not record
    /// identity) so existing field-equality assertions are unaffected.
    public var encodedSystemFields: Data?

    public init(
        recordType: String,
        recordName: String,
        fields: [String: RecordValue],
        encodedSystemFields: Data? = nil
    ) {
        self.recordType = recordType
        self.recordName = recordName
        self.fields = fields
        self.encodedSystemFields = encodedSystemFields
    }

    public static func == (lhs: RecordPayload, rhs: RecordPayload) -> Bool {
        lhs.recordType == rhs.recordType
            && lhs.recordName == rhs.recordName
            && lhs.fields == rhs.fields
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(recordType)
        hasher.combine(recordName)
        hasher.combine(fields)
    }
}

/// Predicate hooks used by `query` / `fetch`. Kept enum-shaped so the Fake
/// doesn't need to evaluate `NSPredicate`. Only the subset Persistence
/// actually issues is encoded here.
public enum RecordPredicate: Sendable, Equatable, Hashable {
    case all(recordType: String)
    case statusEquals(recordType: String, status: String)
    case dailyCompletedOn(dayPrefix: String)   // puzzleId hasPrefix dayPrefix
    /// #921: `mode == "daily" AND status == "completed"`, no `puzzleId`
    /// prefix filter — the single-query sibling of `dailyCompletedOn`, used
    /// by `SavedGameStore.fetchCompletedDailyIdsByDay()` to fetch every
    /// completed daily in one round-trip instead of one query per window day.
    case dailyCompletedAll
}

/// #552: per-call save policy. PersonalRecord uses `.ifUnchanged` for
/// optimistic concurrency (best-time race). SavedGame / MonetizationState
/// keep `.lastWriteWins` (last-write-wins is correct for resume/entitlement).
public enum RecordSavePolicy: Sendable {
    /// CloudKit `.allKeys` — always overwrites server record. Use for
    /// SavedGame / MonetizationState where last-write-wins is correct.
    case lastWriteWins
    /// CloudKit `.ifServerRecordUnchanged` — rejected on stale etag.
    /// Caller must carry the fetched etag in `payload.encodedSystemFields`
    /// and implement a retry loop on `.syncConflict`.
    case ifUnchanged
}

public protocol PrivateCKGateway: Sendable {

    // MARK: - Zone

    func provisionZone() async throws

    // MARK: - Subscription

    func installSubscriptionIfNeeded() async throws

    // MARK: - CRUD

    func fetch(recordName: String) async throws -> RecordPayload?
    func save(_ payload: RecordPayload, policy: RecordSavePolicy) async throws
    func delete(recordName: String) async throws
    func query(_ predicate: RecordPredicate) async throws -> [RecordPayload]
}

public extension PrivateCKGateway {
    /// Convenience overload: `save(_:)` defaults to `.lastWriteWins` so all
    /// existing callers (SavedGame, MonetizationState, Game2048, Minesweeper)
    /// need no change.
    func save(_ payload: RecordPayload) async throws {
        try await save(payload, policy: .lastWriteWins)
    }
}

// MARK: - Constants

/// CloudKit record-type names — shared across apps that link this package.
/// Each app keeps its own CKContainer (and thus its own physical database),
/// so reusing these type names across containers does not collide. Only the
/// per-app zone / subscription identifiers vary (see `PrivateCKConfig`).
public enum PrivateCKConstants {
    public static let savedGameRecordType = "SavedGame"
    public static let personalRecordRecordType = "PersonalRecord"
    public static let monetizationStateRecordType = "MonetizationState"
}

// MARK: - Config

/// Per-app CloudKit identifiers. Passed in at `LivePersistence` /
/// `LivePrivateCKGateway` construction so the package can be linked by
/// multiple apps in the same workspace (Sudoku + Minesweeper) without
/// the zone / subscription names colliding across their respective
/// CKContainers.
public struct PrivateCKConfig: Sendable, Equatable {
    public let zoneName: String
    public let subscriptionID: String

    public init(zoneName: String, subscriptionID: String) {
        self.zoneName = zoneName
        self.subscriptionID = subscriptionID
    }
}

extension PrivateCKConfig {
    /// Identifiers used by the Sudoku app since v1.0. DO NOT reuse these in
    /// another app — each app must own its zone / subscription namespace.
    public static let sudoku = PrivateCKConfig(
        zoneName: "com.wei18.sudoku.userZone",
        subscriptionID: "com.wei18.sudoku.userZone.changes"
    )

    /// Identifiers used by the Minesweeper app. Distinct from `.sudoku` so
    /// the two apps' zone / subscription namespaces never collide. The
    /// CKContainer itself (`iCloud.com.wei18.minesweeper`) is resolved by
    /// `CKContainer.default()` from the Minesweeper App target's
    /// entitlements — not encoded here.
    public static let minesweeper = PrivateCKConfig(
        zoneName: "com.wei18.minesweeper.userZone",
        subscriptionID: "com.wei18.minesweeper.userZone.changes"
    )
}
