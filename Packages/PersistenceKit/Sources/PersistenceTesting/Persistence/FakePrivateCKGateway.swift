// FakePrivateCKGateway — in-memory `PrivateCKGateway` implementation used
// by every PersistenceTests case (plan.md Phase 5: live CloudKit deferred
// to Phase 10).
//
// Records every operation it observes so tests can assert on call shape
// (e.g. "provisioning the zone is idempotent — second call performs zero
// `modifyRecordZones` operations").

import Foundation
public import Persistence

public enum FakeCKOperation: Sendable, Equatable, Hashable {
    case modifyRecordZones
    case modifySubscriptions
    case fetch(recordName: String)
    case save(recordName: String)
    case delete(recordName: String)
    case query
}

public actor FakePrivateCKGateway: PrivateCKGateway {

    public private(set) var operations: [FakeCKOperation] = []

    // MARK: - Storage

    private var zoneExists = false
    private var subscriptionExists = false
    private var records: [String: RecordPayload] = [:]

    // MARK: - Failure injection

    public enum FailureMode: Sendable, Equatable {
        case none
        case alwaysOnSave(PersistenceError)
    }

    public var failureMode: FailureMode = .none

    /// When non-nil, every `fetch(recordName:)` call throws this error.
    /// Models iCloud-signed-out / network-unavailable fetch failures for
    /// `loadOrCreate` offline resilience tests. Mutated only via
    /// `setFetchError(_:)` (Swift 6 actor isolation).
    private var fetchError: (any Error & Sendable)?
    /// #886: per-recordName fetch errors — models a failure scoped to ONE
    /// record (e.g. one difficulty's `PersonalRecord`) while sibling records
    /// still fetch successfully, for tests pinning per-record-independent
    /// degrade (as opposed to `fetchError`'s blanket "every fetch fails").
    /// Checked before the global `fetchError`. Mutated only via
    /// `setFetchError(_:forRecordName:)`.
    private var fetchErrorsByRecordName: [String: any Error & Sendable] = [:]

    public init() {}

    public func setFailureMode(_ mode: FailureMode) {
        self.failureMode = mode
    }

    public func setFetchError(_ error: (any Error & Sendable)?) {
        self.fetchError = error
    }

    /// #886: scope a fetch failure to one `recordName` — see
    /// `fetchErrorsByRecordName`'s doc.
    public func setFetchError(_ error: (any Error & Sendable)?, forRecordName recordName: String) {
        fetchErrorsByRecordName[recordName] = error
    }

    // MARK: - Optimistic concurrency model (#552)

    /// Per-record version counter. Present only when the record has been
    /// saved at least once. Etag = `Data("etag-v\(version)".utf8)`.
    private var versions: [String: Int] = [:]

    private static func etag(forVersion version: Int) -> Data {
        Data("etag-v\(version)".utf8)
    }

    // MARK: - PrivateCKGateway

    public func provisionZone() async throws {
        guard !zoneExists else { return }
        operations.append(.modifyRecordZones)
        zoneExists = true
    }

    public func installSubscriptionIfNeeded() async throws {
        guard !subscriptionExists else { return }
        operations.append(.modifySubscriptions)
        subscriptionExists = true
    }

    public func fetch(recordName: String) async throws -> RecordPayload? {
        operations.append(.fetch(recordName: recordName))
        if let error = fetchErrorsByRecordName[recordName] { throw error }
        if let error = fetchError { throw error }
        return records[recordName]
    }

    public func save(_ payload: RecordPayload, policy: RecordSavePolicy) async throws {
        if case .alwaysOnSave(let error) = failureMode {
            throw error
        }
        operations.append(.save(recordName: payload.recordName))
        switch policy {
        case .lastWriteWins:
            // Always accept; stamp etag so future ifUnchanged saves can carry it.
            let nextVersion = (versions[payload.recordName] ?? 0) + 1
            versions[payload.recordName] = nextVersion
            var stored = payload
            stored.encodedSystemFields = Self.etag(forVersion: nextVersion)
            records[payload.recordName] = stored
        case .ifUnchanged:
            // CloudKit-style optimistic concurrency: an existing record requires
            // a matching etag; absent record is accepted as insert.
            if let currentVersion = versions[payload.recordName] {
                guard payload.encodedSystemFields == Self.etag(forVersion: currentVersion) else {
                    throw PersistenceError.syncConflict(recordName: payload.recordName)
                }
            }
            let nextVersion = (versions[payload.recordName] ?? 0) + 1
            versions[payload.recordName] = nextVersion
            var stored = payload
            stored.encodedSystemFields = Self.etag(forVersion: nextVersion)
            records[payload.recordName] = stored
        }
    }

    public func delete(recordName: String) async throws {
        operations.append(.delete(recordName: recordName))
        records.removeValue(forKey: recordName)
        versions.removeValue(forKey: recordName)
    }

    public func query(_ predicate: RecordPredicate) async throws -> [RecordPayload] {
        operations.append(.query)
        return records.values.filter { Self.matches($0, predicate: predicate) }
    }

    // MARK: - Test helpers

    /// Reach into the store directly without recording an op. Used by tests
    /// to seed fixtures. Stamps v1 etag so subsequent `.ifUnchanged` saves
    /// can carry the correct etag.
    public func seed(_ payload: RecordPayload) {
        versions[payload.recordName] = 1
        var stored = payload
        stored.encodedSystemFields = Self.etag(forVersion: 1)
        records[payload.recordName] = stored
    }

    public func recordCount() -> Int { records.count }

    public func resetOperations() { operations.removeAll() }

    // MARK: - Predicate evaluation

    private static func matches(_ payload: RecordPayload, predicate: RecordPredicate) -> Bool {
        switch predicate {
        case .all(let type):
            return payload.recordType == type
        case let .statusEquals(type, status):
            guard payload.recordType == type else { return false }
            if case .string(let value) = payload.fields["status"] {
                return value == status
            }
            return false
        case .dailyCompletedOn(let dayPrefix):
            guard payload.recordType == PrivateCKConstants.savedGameRecordType else { return false }
            guard case .string("daily") = payload.fields["mode"] else { return false }
            guard case .string("completed") = payload.fields["status"] else { return false }
            guard case .string(let puzzleId) = payload.fields["puzzleId"] else { return false }
            return puzzleId.hasPrefix(dayPrefix)
        }
    }
}
