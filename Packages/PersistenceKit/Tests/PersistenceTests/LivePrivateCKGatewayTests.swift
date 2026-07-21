// LivePrivateCKGatewayTests — gateway-boundary error translation.
//
// Issue #64 Code Reviewer (2026-05-25): verify that `CKError.serverRecordChanged`
// (the wire signal for §How.6.7 conflict resolution) is translated to
// `PersistenceError.syncConflict(recordName:)` at the live adapter boundary.
// Without this translation the store's `catch PersistenceError.syncConflict`
// clause is unreachable in production.
//
// The actor's `database` is a concrete `CKDatabase` and is not constructed
// here (would require a CloudKit container and an authenticated iCloud
// session). Instead we assert the pure mapping function `translate(_:recordName:)`
// directly — that is the "live wiring proof" for the boundary.

#if canImport(CloudKit)
import CloudKit
import Foundation
import Testing
@testable import Persistence
import PersistenceTesting

@Suite("LivePrivateCKGateway — error translation (issue #64)")
struct LivePrivateCKGatewayTests {

    @Test func serverRecordChangedMapsToSyncConflict() {
        let recordName = "daily-2026-05-25"
        let ckError = CKError(.serverRecordChanged)

        let translated = LivePrivateCKGateway.translate(ckError, recordName: recordName)

        guard let persistenceError = translated as? PersistenceError else {
            Issue.record("expected PersistenceError, got \(type(of: translated))")
            return
        }
        #expect(persistenceError == .syncConflict(recordName: recordName))
    }

    @Test func nonConflictCKErrorPassesThrough() {
        let ckError = CKError(.quotaExceeded)

        let translated = LivePrivateCKGateway.translate(ckError, recordName: "x")

        // Non-conflict CKError is returned as-is (callers may surface it
        // via `PersistenceError.underlying` at a higher layer; the gateway
        // only translates the cases callers need to switch on).
        #expect((translated as? CKError)?.code == .quotaExceeded)
    }

    @Test func nonCKErrorPassesThrough() {
        struct Sentinel: Error, Equatable {}
        let translated = LivePrivateCKGateway.translate(Sentinel(), recordName: "x")
        #expect(translated is Sentinel)
    }

    // MARK: - delete idempotency (#757 wave-6)
    //
    // `LivePrivateCKGateway.delete`'s new `.unknownItem → return` branch is
    // inline CloudKit-call handling — like `fetch`/`query` above it can't be
    // exercised without a live, authenticated `CKDatabase`, so there is no
    // seam to invoke the actual `delete(recordName:)` here (same limitation
    // this suite's header documents for `fetch`/`query`). What IS reachable:
    // (1) `FakePrivateCKGateway.delete` — the fake every `PersistenceKit`
    // test actually exercises — which proves the `PrivateCKGateway` protocol
    // contract itself tolerates deleting an absent record; and (2) the
    // `translate(_:recordName:)` mapping delete's catch-all now routes
    // through for any OTHER error, already covered by
    // `nonConflictCKErrorPassesThrough` / `serverRecordChangedMapsToSyncConflict`
    // above — those same assertions ARE the "non-unknownItem error still
    // surfaces, translated" proof for delete's catch-all branch.
    @Test func deletingAbsentRecordViaFakeGatewayDoesNotThrow() async throws {
        let gateway = FakePrivateCKGateway()

        // No prior save — "record-a" was never inserted.
        try await gateway.delete(recordName: "record-a")

        let operations = await gateway.operations
        #expect(operations == [.delete(recordName: "record-a")])
    }

    @Test func deletingExistingRecordViaFakeGatewayStillRemovesIt() async throws {
        let gateway = FakePrivateCKGateway()
        let payload = RecordPayload(
            recordType: PrivateCKConstants.savedGameRecordType,
            recordName: "record-b",
            fields: [:],
            encodedSystemFields: nil
        )
        await gateway.seed(payload)
        #expect(await gateway.recordCount() == 1)

        try await gateway.delete(recordName: "record-b")

        #expect(await gateway.recordCount() == 0)
    }
}
#endif
