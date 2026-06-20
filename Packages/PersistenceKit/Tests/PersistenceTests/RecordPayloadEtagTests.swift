// RecordPayloadEtagTests — #552: encodedSystemFields excluded from Equatable/Hashable.
//
// Two payloads differing ONLY in etag must compare equal and hash to the same
// bucket — etag is concurrency metadata, not record identity.

import Foundation
import Testing
@testable import Persistence

@Suite("RecordPayload — etag excluded from == and hash")
struct RecordPayloadEtagTests {

    private let fields: [String: RecordValue] = [
        "mode": .string("daily"),
        "bestTimeSeconds": .int(100)
    ]

    @Test func payloadsWithDifferentEtagsAreEqual() {
        let etag1 = Data("etag-v1".utf8)
        let etag2 = Data("etag-v2".utf8)
        let payloadA = RecordPayload(
            recordType: "PersonalRecord",
            recordName: "daily-easy",
            fields: fields,
            encodedSystemFields: etag1
        )
        let payloadB = RecordPayload(
            recordType: "PersonalRecord",
            recordName: "daily-easy",
            fields: fields,
            encodedSystemFields: etag2
        )
        #expect(payloadA == payloadB)
    }

    @Test func payloadWithEtagEqualsPayloadWithoutEtag() {
        let payloadWithEtag = RecordPayload(
            recordType: "PersonalRecord",
            recordName: "daily-easy",
            fields: fields,
            encodedSystemFields: Data("etag-v1".utf8)
        )
        let payloadWithout = RecordPayload(
            recordType: "PersonalRecord",
            recordName: "daily-easy",
            fields: fields,
            encodedSystemFields: nil
        )
        #expect(payloadWithEtag == payloadWithout)
    }

    @Test func payloadsWithDifferentEtagsHashEqually() {
        var setWithEtag: Set<RecordPayload> = []
        setWithEtag.insert(RecordPayload(
            recordType: "PersonalRecord",
            recordName: "daily-easy",
            fields: fields,
            encodedSystemFields: Data("etag-v1".utf8)
        ))
        let payloadV2 = RecordPayload(
            recordType: "PersonalRecord",
            recordName: "daily-easy",
            fields: fields,
            encodedSystemFields: Data("etag-v2".utf8)
        )
        // Insert should be a no-op (same hash bucket, == true)
        setWithEtag.insert(payloadV2)
        #expect(setWithEtag.count == 1)
    }

    @Test func payloadsDifferingInFieldsAreNotEqual() {
        let payloadA = RecordPayload(
            recordType: "PersonalRecord",
            recordName: "daily-easy",
            fields: ["mode": .string("daily")],
            encodedSystemFields: nil
        )
        let payloadB = RecordPayload(
            recordType: "PersonalRecord",
            recordName: "daily-easy",
            fields: ["mode": .string("practice")],
            encodedSystemFields: nil
        )
        #expect(payloadA != payloadB)
    }
}
