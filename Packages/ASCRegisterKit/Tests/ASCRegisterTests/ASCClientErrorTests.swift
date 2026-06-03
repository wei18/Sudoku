// ASCClientErrorTests — verify ClientError.decodeFailed carries path, status,
// and body excerpt; verify the 2KB truncation marker on oversized bodies.
//
// Tests call APIResource.decodeSingle / decodeCollection directly with
// hand-crafted Data — no URLSession mocking required. This keeps the suite
// hermetic and focused on the error-shape contract, not network plumbing.

internal import Foundation
internal import Testing
@testable import ASCRegister

@Suite("ASCClient error context")
internal struct ASCClientErrorTests {

    @Test("decodeSingle with null data carries path + status + body excerpt")
    internal func decodeSingleMissingDataCarriesContext() throws {
        let body = #"{"data": null, "links": {"self": "/v1/apps/x/gameCenterDetail"}}"#
        let data = Data(body.utf8)

        do {
            _ = try APIResource.decodeSingle(
                from: data,
                path: "/v1/apps/6771248206/gameCenterDetail",
                status: 200
            )
            Issue.record("expected throw")
        } catch let ASCClient.ClientError.decodeFailed(reason, path, status, bodyExcerpt) {
            #expect(reason == "missing data")
            #expect(path == "/v1/apps/6771248206/gameCenterDetail")
            #expect(status == 200)
            #expect(bodyExcerpt == body)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("decodeCollection with missing data array carries reason + body")
    internal func decodeCollectionMissingArrayCarriesContext() throws {
        let body = #"{}"#
        let data = Data(body.utf8)

        do {
            _ = try APIResource.decodeCollection(
                from: data,
                path: "/v1/gameCenterDetails/abc/gameCenterLeaderboards",
                status: 200
            )
            Issue.record("expected throw")
        } catch let ASCClient.ClientError.decodeFailed(reason, path, status, bodyExcerpt) {
            #expect(reason == "missing data array")
            #expect(path == "/v1/gameCenterDetails/abc/gameCenterLeaderboards")
            #expect(status == 200)
            #expect(bodyExcerpt == body)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("decodeSingle with attributes-only data carries 'missing id/type' + body")
    internal func decodeSingleMissingIDCarriesContext() throws {
        let body = #"{"data": {"attributes": {"foo": "bar"}}}"#
        let data = Data(body.utf8)

        do {
            _ = try APIResource.decodeSingle(
                from: data,
                path: "/v1/gameCenterLeaderboards/L1",
                status: 200
            )
            Issue.record("expected throw")
        } catch let ASCClient.ClientError.decodeFailed(reason, path, status, bodyExcerpt) {
            #expect(reason == "missing id/type")
            #expect(path == "/v1/gameCenterLeaderboards/L1")
            #expect(status == 200)
            #expect(bodyExcerpt == body)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("oversized body is truncated with explicit marker at 2KB cap")
    internal func bodyTruncationAddsMarker() throws {
        // Valid JSON object whose body exceeds 2KB. Decode succeeds parsing
        // outer object but fails on "missing data" — error excerpt should be
        // truncated.
        let filler = String(repeating: "A", count: 3072)
        let body = #"{"unrelated":"\#(filler)"}"#  // total = 3072 + 16 = 3088 bytes
        let data = Data(body.utf8)

        do {
            _ = try APIResource.decodeSingle(
                from: data,
                path: "/v1/test",
                status: 200
            )
            Issue.record("expected throw")
        } catch let ASCClient.ClientError.decodeFailed(reason, _, _, bodyExcerpt) {
            #expect(reason == "missing data")
            let remaining = data.count - 2048
            let suffix = "... <truncated, \(remaining) more bytes>"
            #expect(bodyExcerpt.hasSuffix(suffix))
            #expect(bodyExcerpt.count == 2048 + suffix.count)
        } catch {
            Issue.record("wrong error: \(error)")
        }

        // Also sanity-check truncateBody directly with a 3KB raw payload.
        let raw = Data(String(repeating: "A", count: 3072).utf8)
        let excerpt = truncateBody(raw)
        #expect(excerpt.hasSuffix("... <truncated, 1024 more bytes>"))
        #expect(excerpt.count == 2048 + "... <truncated, 1024 more bytes>".count)
    }
}
