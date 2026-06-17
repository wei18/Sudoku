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

    /// Per-recordName conflict counter: each save against the recorded
    /// recordName throws `PersistenceError.syncConflict(recordName:)` and
    /// decrements the counter; when it hits zero the save proceeds normally.
    /// Models CloudKit's `serverRecordChanged` for ConflictResolver wiring
    /// tests without coupling the test surface to a separate spy gateway.
    private var conflictOnSaveRemaining: [String: Int] = [:]

    /// #544: opt-in modelling of CloudKit optimistic concurrency. When enabled,
    /// a save against an EXISTING record must carry the record's current etag
    /// (in `payload.encodedSystemFields`) or it's rejected with `.syncConflict`
    /// — reproducing the real `serverRecordChanged` an etag-less re-insert hits.
    /// Off by default so existing tests (which don't thread etags) are
    /// unaffected. `fetch`/`seed` stamp the stored payload with its etag.
    private var enforceOptimisticConcurrency = false
    private var versions: [String: Int] = [:]

    private static func etag(forVersion version: Int) -> Data {
        Data("etag-v\(version)".utf8)
    }

    public init() {}

    public func setFailureMode(_ mode: FailureMode) {
        self.failureMode = mode
    }

    /// #544: turn on CloudKit-style etag enforcement for this fake.
    public func setEnforceOptimisticConcurrency(_ enabled: Bool) {
        self.enforceOptimisticConcurrency = enabled
    }

    public func setFetchError(_ error: (any Error & Sendable)?) {
        self.fetchError = error
    }

    /// Schedule the next `times` saves against `recordName` to throw
    /// `.syncConflict`. After the counter drains the save behaves normally.
    public func setConflictOnSaveTimes(_ times: Int, recordName: String) {
        conflictOnSaveRemaining[recordName] = times
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
        if let error = fetchError { throw error }
        return records[recordName]
    }

    public func save(_ payload: RecordPayload) async throws {
        if case .alwaysOnSave(let error) = failureMode {
            throw error
        }
        if let remaining = conflictOnSaveRemaining[payload.recordName], remaining > 0 {
            conflictOnSaveRemaining[payload.recordName] = remaining - 1
            operations.append(.save(recordName: payload.recordName))
            throw PersistenceError.syncConflict(recordName: payload.recordName)
        }
        operations.append(.save(recordName: payload.recordName))
        guard enforceOptimisticConcurrency else {
            records[payload.recordName] = payload
            return
        }
        // CloudKit-style optimistic concurrency: an existing record requires a
        // matching etag; a new record (no stored version) is accepted as an
        // insert and stamped v1. Each accepted save bumps the version.
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

    public func delete(recordName: String) async throws {
        operations.append(.delete(recordName: recordName))
        records.removeValue(forKey: recordName)
    }

    public func query(_ predicate: RecordPredicate) async throws -> [RecordPayload] {
        operations.append(.query)
        return records.values.filter { Self.matches($0, predicate: predicate) }
    }

    // MARK: - Test helpers

    /// Reach into the store directly without recording an op. Used by tests
    /// to seed fixtures.
    public func seed(_ payload: RecordPayload) {
        guard enforceOptimisticConcurrency else {
            records[payload.recordName] = payload
            return
        }
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
