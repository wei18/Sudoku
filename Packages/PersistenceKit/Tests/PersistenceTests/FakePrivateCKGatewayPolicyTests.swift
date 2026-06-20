// FakePrivateCKGatewayPolicyTests — #552: RecordSavePolicy behaviour on FakePrivateCKGateway.
//
// Tests the .ifUnchanged policy (optimistic concurrency) and .lastWriteWins
// (always-accept). Validates: stale etag → .syncConflict; matching etag →
// accepted + version bumped; absent record → accepted as insert; .lastWriteWins
// always accepted regardless of etag.

import Foundation
import Testing
import PersistenceTesting
@testable import Persistence

@Suite("FakePrivateCKGateway — RecordSavePolicy")
struct FakePrivateCKGatewayPolicyTests {

    private func makeGateway() -> FakePrivateCKGateway {
        FakePrivateCKGateway()
    }

    private func basePayload(recordName: String = "daily-easy") -> RecordPayload {
        RecordPayload(
            recordType: "PersonalRecord",
            recordName: recordName,
            fields: ["bestTimeSeconds": .int(100)]
        )
    }

    // MARK: - .lastWriteWins

    @Test func lastWriteWinsAlwaysAcceptsWithNoEtag() async throws {
        let gateway = makeGateway()
        let payload = basePayload()
        // No prior record — should succeed
        try await gateway.save(payload, policy: .lastWriteWins)
        let fetched = try? await gateway.fetch(recordName: payload.recordName)
        #expect(fetched != nil)
    }

    @Test func lastWriteWinsAcceptsWithoutMatchingEtag() async throws {
        let gateway = makeGateway()
        await gateway.seed(basePayload())
        // Save with a stale/wrong etag under lastWriteWins — must succeed
        var payload = basePayload()
        payload.encodedSystemFields = Data("wrong-etag".utf8)
        try await gateway.save(payload, policy: .lastWriteWins)
        // no throw = pass
    }

    // MARK: - .ifUnchanged (optimistic concurrency)

    @Test func ifUnchangedInsertSucceedsWhenRecordAbsent() async throws {
        let gateway = makeGateway()
        // No prior record — insert path, etag may be nil
        let payload = basePayload()
        try await gateway.save(payload, policy: .ifUnchanged)
        let fetched = try? await gateway.fetch(recordName: payload.recordName)
        #expect(fetched != nil)
    }

    @Test func ifUnchangedAcceptsMatchingEtag() async throws {
        let gateway = makeGateway()
        // Seed v1 (sets etag to "etag-v1" internally)
        await gateway.seed(basePayload())
        // Fetch to get stamped etag
        let fetched = try await gateway.fetch(recordName: "daily-easy")
        var payload = basePayload()
        payload.encodedSystemFields = fetched?.encodedSystemFields
        // Save with matching etag — must succeed
        try await gateway.save(payload, policy: .ifUnchanged)
        // Fetch again — version should have bumped
        let refetched = try await gateway.fetch(recordName: "daily-easy")
        // etag must differ from fetched (version bumped)
        #expect(refetched?.encodedSystemFields != fetched?.encodedSystemFields)
    }

    @Test func ifUnchangedRejectsStaleEtag() async throws {
        let gateway = makeGateway()
        await gateway.seed(basePayload())
        // Capture etag BEFORE another write bumps it
        let fetchedBefore = try await gateway.fetch(recordName: "daily-easy")
        let staleEtag = fetchedBefore?.encodedSystemFields
        // Another write bumps the version
        var firstWrite = basePayload()
        firstWrite.encodedSystemFields = staleEtag
        try await gateway.save(firstWrite, policy: .ifUnchanged)
        // Now stale etag is truly stale — second write must conflict
        var staleSave = basePayload()
        staleSave.encodedSystemFields = staleEtag
        await #expect(throws: PersistenceError.syncConflict(recordName: "daily-easy")) {
            try await gateway.save(staleSave, policy: .ifUnchanged)
        }
    }

    @Test func ifUnchangedVersionBumpsOnEachAcceptedSave() async throws {
        let gateway = makeGateway()
        await gateway.seed(basePayload())
        // Three successive saves each with the fresh etag
        for _ in 0..<3 {
            let fresh = try await gateway.fetch(recordName: "daily-easy")
            var payload = basePayload()
            payload.encodedSystemFields = fresh?.encodedSystemFields
            try await gateway.save(payload, policy: .ifUnchanged)
        }
        // Should have completed without conflict
        let final = try await gateway.fetch(recordName: "daily-easy")
        // etag-v4 (seed=v1, + 3 saves = v4)
        #expect(final?.encodedSystemFields == Data("etag-v4".utf8))
    }

    // MARK: - default save(_:) still works

    @Test func defaultSaveMethodStillCompiles() async throws {
        let gateway = makeGateway()
        // The default extension `save(_:)` should be callable (last-write-wins)
        try await gateway.save(basePayload())
    }
}
