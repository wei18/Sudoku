// ASCClientURLProtocolTests — offline integration tests for the issue #310
// metadata-snapshot reliability orchestration, using a `URLProtocol` stub so
// the REAL client/command code runs end-to-end without any live ASC call
// (issue #333, CR #332 follow-up). Complements the pure-helper coverage in
// ASCClientPaginationTests (`nextPageLink` / `isDuplicateValueError`).
//
// Covered paths:
//   1. `getAllPages` follows `links.next` across ≥2 pages and concatenates.
//   2. `ASCRegisterCLI.createOrUpdateVersionLoc` POST→409-DUPLICATE→GET→PATCH
//      self-heal (CREATE that dups switches to UPDATE on the re-fetched id).
//
// The suite is `.serialized` because `StubURLProtocol` shares a process-global
// response queue (URLProtocol is instantiated by URLSession, so per-instance
// injection isn't available).

internal import CryptoKit
internal import Foundation
internal import Testing
@testable import ASCRegister

// MARK: - URLProtocol stub

/// A canned HTTP response: status + JSON body, served in FIFO order.
private struct StubResponse: Sendable {
    let status: Int
    let body: String
}

/// One recorded request the client actually issued (for assertion).
private struct RecordedRequest: Sendable {
    let method: String
    let url: String
}

/// Process-global, lock-guarded harness state. `URLProtocol` subclasses are
/// instantiated by `URLSession` (no DI hook), so the queue + recorder live in
/// statics guarded by a single lock. `reset()` clears between tests; the suite
/// is `.serialized` so there is no cross-test interleaving.
private enum StubState {
    nonisolated(unsafe) static var responses: [StubResponse] = []
    nonisolated(unsafe) static var recorded: [RecordedRequest] = []
    static let lock = NSLock()

    static func reset(with responses: [StubResponse]) {
        lock.lock(); defer { lock.unlock() }
        self.responses = responses
        recorded = []
    }

    static func nextResponse(for request: URLRequest) -> StubResponse {
        lock.lock(); defer { lock.unlock() }
        recorded.append(RecordedRequest(
            method: request.httpMethod ?? "?",
            url: request.url?.absoluteString ?? "?"
        ))
        guard !responses.isEmpty else {
            return StubResponse(status: 599, body: #"{"errors":[{"detail":"stub queue empty"}]}"#)
        }
        return responses.removeFirst()
    }

    static func recordedRequests() -> [RecordedRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }
}

/// Serves `StubState.responses` in order; records every request. Registered on
/// an ephemeral `URLSessionConfiguration` so nothing touches the network.
private class StubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let stub = StubState.nextResponse(for: request)
        let url = request.url ?? URL(string: "https://stub.local")!
        let response = HTTPURLResponse(
            url: url, statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

// MARK: - Tests

@Suite("ASCClient URLProtocol harness", .serialized)
internal struct ASCClientURLProtocolTests {

    /// Build a client wired to the stub protocol with a throwaway signing key.
    private static func makeClient(mode: ASCClient.Mode = .apply) -> ASCClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let pem = P256.Signing.PrivateKey().pemRepresentation
        let auth = ASCClient.Auth(keyId: "TESTKEY", issuerId: "ISSUER", keyPEM: pem)
        return ASCClient(
            auth: auth,
            mode: mode,
            baseURL: URL(string: "https://stub.local")!,
            session: session,
            log: { _ in }
        )
    }

    @Test("getAllPages follows links.next across two pages and concatenates")
    internal func paginationAcrossTwoPages() async throws {
        let page1 = #"""
        {"data":[{"id":"vl-1","type":"appStoreVersionLocalizations",
        "attributes":{"locale":"en-US"}}],
        "links":{"next":"https://stub.local/v1/page2?cursor=B"}}
        """#
        let page2 = #"""
        {"data":[{"id":"vl-2","type":"appStoreVersionLocalizations",
        "attributes":{"locale":"es-ES"}}],
        "links":{"self":"https://stub.local/v1/page2?cursor=B"}}
        """#
        StubState.reset(with: [
            StubResponse(status: 200, body: page1),
            StubResponse(status: 200, body: page2),
        ])

        let client = Self.makeClient()
        let all = try await client.listVersionLocalizations(versionId: "v-1")

        #expect(all.count == 2)
        #expect(all.map(\.id) == ["vl-1", "vl-2"])
        #expect(all.compactMap { $0.attributes["locale"] } == ["en-US", "es-ES"])
        // Exactly two GETs were issued (page1, then the links.next page2).
        let reqs = StubState.recordedRequests()
        #expect(reqs.count == 2)
        #expect(reqs.allSatisfy { request in request.method == "GET" })
        #expect(reqs[1].url == "https://stub.local/v1/page2?cursor=B")
    }

    @Test("createOrUpdateVersionLoc self-heals POST→409-dup→GET→PATCH")
    internal func createFallsBackToPatchOn409Duplicate() async throws {
        // 1) POST create → 409 DUPLICATE (locale already exists)
        let dup409 = #"""
        {"errors":[{"status":"409","code":"ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE",
        "detail":"The attribute 'locale' with value 'es-ES' already exists. Try updating."}]}
        """#
        // 2) GET re-fetch the version's locs → find the existing id
        let existing = #"""
        {"data":[{"id":"vl-existing","type":"appStoreVersionLocalizations",
        "attributes":{"locale":"es-ES"}}],"links":{}}
        """#
        // 3) PATCH update on that id → 200
        let patched = #"""
        {"data":{"id":"vl-existing","type":"appStoreVersionLocalizations",
        "attributes":{"locale":"es-ES","description":"Updated."}}}
        """#
        StubState.reset(with: [
            StubResponse(status: 409, body: dup409),
            StubResponse(status: 200, body: existing),
            StubResponse(status: 200, body: patched),
        ])

        let client = Self.makeClient()
        let listing = ListingLocale(
            locale: "es-ES", name: nil, subtitle: nil, privacyPolicyUrl: nil,
            description: "Updated.", keywords: nil, promotionalText: nil,
            whatsNew: nil, marketingUrl: nil, supportUrl: nil
        )
        // Must NOT throw — the 409 dup is swallowed and converted to a PATCH.
        try await ASCRegisterCLI.createOrUpdateVersionLoc(
            client: client, versionId: "v-1", locale: "es-ES", listing: listing
        )

        let reqs = StubState.recordedRequests()
        #expect(reqs.count == 3)
        // POST create, GET re-fetch, PATCH the existing id — in that order.
        #expect(reqs[0].method == "POST")
        #expect(reqs[0].url.hasSuffix("/v1/appStoreVersionLocalizations"))
        #expect(reqs[1].method == "GET")
        #expect(reqs[2].method == "PATCH")
        #expect(reqs[2].url.hasSuffix("/v1/appStoreVersionLocalizations/vl-existing"))
    }

    @Test("createOrUpdateVersionLoc rethrows a non-duplicate 409 (no false self-heal)")
    internal func nonDuplicate409Rethrows() async throws {
        let other409 = #"""
        {"errors":[{"status":"409","code":"ENTITY_ERROR.RELATIONSHIP.INVALID",
        "detail":"primaryCategory is not valid"}]}
        """#
        StubState.reset(with: [StubResponse(status: 409, body: other409)])

        let client = Self.makeClient()
        let listing = ListingLocale(
            locale: "es-ES", name: nil, subtitle: nil, privacyPolicyUrl: nil,
            description: "x", keywords: nil, promotionalText: nil,
            whatsNew: nil, marketingUrl: nil, supportUrl: nil
        )
        await #expect(throws: ASCClient.ClientError.self) {
            try await ASCRegisterCLI.createOrUpdateVersionLoc(
                client: client, versionId: "v-1", locale: "es-ES", listing: listing
            )
        }
        // Only the POST was issued — no GET/PATCH self-heal on a non-dup 409.
        #expect(StubState.recordedRequests().count == 1)
    }
}
