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

    /// Two-platform `appStoreVersions` GET body — one editable IOS version
    /// (1.0) + one MAC_OS version whose `appStoreState` is templated, so a test
    /// can make the macOS version editable (`PREPARE_FOR_SUBMISSION`) or
    /// locked (`READY_FOR_SALE`). Shared across the platform-aware tests.
    private static func twoPlatformVersions(macState: String) -> String {
        #"""
        {"data":[
          {"id":"ios-v","type":"appStoreVersions",
           "attributes":{"versionString":"1.0","platform":"IOS",
                         "appStoreState":"PREPARE_FOR_SUBMISSION"}},
          {"id":"mac-v","type":"appStoreVersions",
           "attributes":{"versionString":"2.3.5","platform":"MAC_OS",
                         "appStoreState":"\#(macState)"}}
        ],"links":{}}
        """#
    }

    /// A minimal 200 PATCH/echo body for an appStoreVersions mutation.
    private static let okVersionPatch = #"""
    {"data":{"id":"x","type":"appStoreVersions","attributes":{"versionString":"2.5"}}}
    """#

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

    // MARK: - Platform-aware version selection (multi-platform defect)

    /// `set-version --platform all` must rename BOTH the IOS and the MAC_OS
    /// editable version in one run. The app GETs one `appStoreVersions`
    /// collection carrying a `platform` token per version; `applySetVersion`
    /// groups by platform and PATCHes each editable one.
    @Test("set-version all renames both an IOS and a MAC_OS editable version")
    internal func setVersionAllHitsBothPlatforms() async throws {
        StubState.reset(with: [
            StubResponse(status: 200, body: Self.twoPlatformVersions(macState: "PREPARE_FOR_SUBMISSION")),
            StubResponse(status: 200, body: Self.okVersionPatch),  // PATCH ios-v
            StubResponse(status: 200, body: Self.okVersionPatch),  // PATCH mac-v
        ])

        let client = Self.makeClient()
        let versions = try await client.listAppStoreVersions(appId: "app-1")
        try await ASCRegisterCLI.applySetVersion(
            client: client,
            platformVersions: ASCRegisterCLI.platformVersions(from: versions.data),
            filter: .all,
            target: "2.5"
        )

        let reqs = StubState.recordedRequests()
        // 1 GET + 2 PATCH (one per platform).
        #expect(reqs.count == 3)
        #expect(reqs[0].method == "GET")
        let patches = reqs.filter { $0.method == "PATCH" }
        #expect(patches.count == 2)
        // Both platform version ids were PATCHed — iOS no longer stuck at 1.0.
        #expect(patches.contains { $0.url.hasSuffix("/v1/appStoreVersions/ios-v") })
        #expect(patches.contains { $0.url.hasSuffix("/v1/appStoreVersions/mac-v") })
    }

    /// `set-version --platform ios` targets ONLY the iOS version; the MAC_OS
    /// version is left untouched.
    @Test("set-version --platform ios renames only the iOS version")
    internal func setVersionIOSFilterTargetsOnlyIOS() async throws {
        StubState.reset(with: [
            StubResponse(status: 200, body: Self.twoPlatformVersions(macState: "PREPARE_FOR_SUBMISSION")),
            StubResponse(status: 200, body: Self.okVersionPatch),  // PATCH ios-v only
        ])

        let client = Self.makeClient()
        let versions = try await client.listAppStoreVersions(appId: "app-1")
        try await ASCRegisterCLI.applySetVersion(
            client: client,
            platformVersions: ASCRegisterCLI.platformVersions(from: versions.data),
            filter: .ios,
            target: "2.5"
        )

        let reqs = StubState.recordedRequests()
        let patches = reqs.filter { $0.method == "PATCH" }
        #expect(patches.count == 1)
        #expect(patches[0].url.hasSuffix("/v1/appStoreVersions/ios-v"))
        #expect(!patches.contains { $0.url.hasSuffix("/v1/appStoreVersions/mac-v") })
    }

    /// A platform whose only version is released/locked has NO editable version
    /// — `set-version` must warn and skip it (not crash), still renaming the
    /// other platform's editable version.
    @Test("set-version warns + skips a platform with no editable version, renames the other")
    internal func setVersionSkipsPlatformWithoutEditableVersion() async throws {
        // macOS version is READY_FOR_SALE → no editable version for that
        // platform → warn + skip (not crash); iOS still renamed.
        StubState.reset(with: [
            StubResponse(status: 200, body: Self.twoPlatformVersions(macState: "READY_FOR_SALE")),
            StubResponse(status: 200, body: Self.okVersionPatch),  // PATCH ios-v only (mac skipped)
        ])

        let client = Self.makeClient()
        let versions = try await client.listAppStoreVersions(appId: "app-1")
        // Must NOT throw — the MAC_OS-has-no-editable case is a warn+skip.
        try await ASCRegisterCLI.applySetVersion(
            client: client,
            platformVersions: ASCRegisterCLI.platformVersions(from: versions.data),
            filter: .all,
            target: "2.5"
        )

        let reqs = StubState.recordedRequests()
        let patches = reqs.filter { $0.method == "PATCH" }
        #expect(patches.count == 1)
        #expect(patches[0].url.hasSuffix("/v1/appStoreVersions/ios-v"))
    }

    /// `metadata apply` snapshot must produce a per-platform version snapshot
    /// for BOTH IOS and MAC_OS, each carrying that version's own version-locs —
    /// so version-loc copy is pushed to every platform, not one.
    @Test("snapshotPlatformVersions yields a snapshot per platform with its own version-locs")
    internal func snapshotProducesPerPlatformVersionLocs() async throws {
        let iosLocs = #"""
        {"data":[{"id":"ios-loc-en","type":"appStoreVersionLocalizations",
        "attributes":{"locale":"en-US","description":"iOS desc"}}],"links":{}}
        """#
        let macLocs = #"""
        {"data":[{"id":"mac-loc-en","type":"appStoreVersionLocalizations",
        "attributes":{"locale":"en-US","description":"Mac desc"}}],"links":{}}
        """#
        StubState.reset(with: [
            StubResponse(status: 200, body: Self.twoPlatformVersions(macState: "PREPARE_FOR_SUBMISSION")),
            StubResponse(status: 200, body: iosLocs),  // GET ios-v locs
            StubResponse(status: 200, body: macLocs),  // GET mac-v locs
        ])

        let client = Self.makeClient()
        let snapshots = try await ASCRegisterCLI.snapshotPlatformVersions(
            client: client, appId: "app-1", filter: .all, versionFilter: nil
        )

        #expect(snapshots.count == 2)
        let byPlatform = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.platform, $0) })
        #expect(byPlatform["IOS"]?.versionId == "ios-v")
        #expect(byPlatform["MAC_OS"]?.versionId == "mac-v")
        // Each platform's snapshot carries its OWN version-loc set (proving the
        // per-platform GET fan-out, not a shared one).
        #expect(byPlatform["IOS"]?.versionLocalizations["en-US"]?.description == "iOS desc")
        #expect(byPlatform["MAC_OS"]?.versionLocalizations["en-US"]?.description == "Mac desc")
        // The version-locs were fetched from each version's own endpoint.
        let getURLs = StubState.recordedRequests().filter { $0.method == "GET" }.map(\.url)
        #expect(getURLs.contains { $0.contains("/v1/appStoreVersions/ios-v/appStoreVersionLocalizations") })
        #expect(getURLs.contains { $0.contains("/v1/appStoreVersions/mac-v/appStoreVersionLocalizations") })
    }

    /// `--platform ios` on the snapshot path fetches version-locs for the iOS
    /// version only (no MAC_OS loc GET).
    @Test("snapshotPlatformVersions --platform ios snapshots only iOS")
    internal func snapshotIOSFilterOnlyIOS() async throws {
        let iosLocs = #"""
        {"data":[{"id":"ios-loc-en","type":"appStoreVersionLocalizations",
        "attributes":{"locale":"en-US","description":"iOS desc"}}],"links":{}}
        """#
        StubState.reset(with: [
            StubResponse(status: 200, body: Self.twoPlatformVersions(macState: "PREPARE_FOR_SUBMISSION")),
            StubResponse(status: 200, body: iosLocs),  // only iOS locs fetched
        ])

        let client = Self.makeClient()
        let snapshots = try await ASCRegisterCLI.snapshotPlatformVersions(
            client: client, appId: "app-1", filter: .ios, versionFilter: nil
        )

        #expect(snapshots.count == 1)
        #expect(snapshots[0].platform == "IOS")
        let getURLs = StubState.recordedRequests().filter { $0.method == "GET" }.map(\.url)
        #expect(!getURLs.contains { $0.contains("/v1/appStoreVersions/mac-v/appStoreVersionLocalizations") })
    }
}
