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

// swiftlint:disable file_length
// WHY: the screenshot upload suite (reserve→PUT→commit + checksum + idempotency)
// shares this file's `StubURLProtocol` harness (it is `private` here), so its
// tests live alongside the metadata ones rather than duplicating the stub.

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

/// One recorded request the client actually issued (for assertion). `body`
/// captures the request payload (resolving `httpBodyStream` when URLSession
/// converted a set `httpBody` to a stream) so tests can assert the reserve POST
/// shape, the PUT chunk bytes, and the commit PATCH checksum.
private struct RecordedRequest: Sendable {
    let method: String
    let url: String
    let body: Data
    /// Request headers the client set. NOTE: URLSession may add/normalize a few
    /// of its own (e.g. Content-Length, Host), and some reserved headers can be
    /// dropped before `URLProtocol` sees them — so assert on headers the CLIENT
    /// is responsible for (the ASC-returned PUT `Content-Type`) and on the
    /// ABSENCE of the ASC `Authorization` JWT, not on an exact header set.
    let headers: [String: String]
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
            url: request.url?.absoluteString ?? "?",
            body: bodyData(of: request),
            headers: request.allHTTPHeaderFields ?? [:]
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

    /// Resolve a request's payload. URLSession often moves a set `httpBody` into
    /// `httpBodyStream` by the time `URLProtocol` sees it, so we drain the stream
    /// when `httpBody` is nil. Returns empty `Data` for body-less requests (GET).
    private static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var out = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            out.append(buffer, count: read)
        }
        return out
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

    /// A two-platform `appStoreVersions` body where each platform may carry a
    /// RELEASED predecessor alongside its editable version, and the state token
    /// key (`appStoreState` legacy vs `appVersionState` modern) is selectable.
    /// Used by the per-platform `hasReleasedVersion` tests (#362): the editable
    /// version is what gets patched, the optional released predecessor is what
    /// flips that platform's `hasReleasedVersion` to true.
    ///
    /// - `stateKey`: `"appStoreState"` (legacy) or `"appVersionState"` (modern).
    /// - `iosReleased` / `macReleased`: emit a released predecessor (using
    ///   `releasedToken`) for that platform's version list.
    /// - `releasedToken`: the released-state token (e.g. `READY_FOR_SALE` or the
    ///   modern `READY_FOR_DISTRIBUTION`).
    private static func twoPlatformVersionsWithReleased(
        stateKey: String,
        iosReleased: Bool,
        macReleased: Bool,
        releasedToken: String
    ) -> String {
        func releasedRow(platform: String, id: String) -> String {
            #"""
            {"id":"\#(id)","type":"appStoreVersions",
             "attributes":{"versionString":"1.0","platform":"\#(platform)",
                           "\#(stateKey)":"\#(releasedToken)"}}
            """#
        }
        func editableRow(platform: String, id: String, version: String) -> String {
            #"""
            {"id":"\#(id)","type":"appStoreVersions",
             "attributes":{"versionString":"\#(version)","platform":"\#(platform)",
                           "\#(stateKey)":"PREPARE_FOR_SUBMISSION"}}
            """#
        }
        var rows: [String] = []
        if iosReleased { rows.append(releasedRow(platform: "IOS", id: "ios-rel")) }
        rows.append(editableRow(platform: "IOS", id: "ios-v", version: "2.0"))
        if macReleased { rows.append(releasedRow(platform: "MAC_OS", id: "mac-rel")) }
        rows.append(editableRow(platform: "MAC_OS", id: "mac-v", version: "2.0"))
        return "{\"data\":[" + rows.joined(separator: ",") + "],\"links\":{}}"
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

    // MARK: - Per-platform hasReleasedVersion (#362)

    /// Each platform's `hasReleasedVersion` is computed from THAT platform's own
    /// versions, not app-wide. iOS first submission (no released predecessor) +
    /// macOS has a released predecessor ⇒ iOS snapshot is NOT released, macOS IS.
    @Test("snapshotPlatformVersions computes hasReleasedVersion per platform")
    internal func snapshotHasReleasedVersionPerPlatform() async throws {
        let emptyLocs = #"{"data":[],"links":{}}"#
        StubState.reset(with: [
            StubResponse(status: 200, body: Self.twoPlatformVersionsWithReleased(
                stateKey: "appStoreState", iosReleased: false, macReleased: true,
                releasedToken: "READY_FOR_SALE"
            )),
            StubResponse(status: 200, body: emptyLocs),  // GET ios-v locs
            StubResponse(status: 200, body: emptyLocs),  // GET mac-v locs
        ])

        let client = Self.makeClient()
        let snapshots = try await ASCRegisterCLI.snapshotPlatformVersions(
            client: client, appId: "app-1", filter: .all, versionFilter: nil
        )

        let byPlatform = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.platform, $0) })
        #expect(byPlatform["IOS"]?.hasReleasedVersion == false)
        #expect(byPlatform["MAC_OS"]?.hasReleasedVersion == true)
    }

    /// A platform whose released predecessor reports the MODERN `appVersionState`
    /// token (`READY_FOR_DISTRIBUTION`) still computes `hasReleasedVersion == true`
    /// — the released-states set now accepts modern tokens (#362).
    @Test("snapshotPlatformVersions sees a release via modern appVersionState token")
    internal func snapshotReleasedViaModernToken() async throws {
        let emptyLocs = #"{"data":[],"links":{}}"#
        StubState.reset(with: [
            StubResponse(status: 200, body: Self.twoPlatformVersionsWithReleased(
                stateKey: "appVersionState", iosReleased: true, macReleased: false,
                releasedToken: "READY_FOR_DISTRIBUTION"
            )),
            StubResponse(status: 200, body: emptyLocs),  // GET ios-v locs
            StubResponse(status: 200, body: emptyLocs),  // GET mac-v locs
        ])

        let client = Self.makeClient()
        let snapshots = try await ASCRegisterCLI.snapshotPlatformVersions(
            client: client, appId: "app-1", filter: .all, versionFilter: nil
        )

        let byPlatform = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.platform, $0) })
        // iOS released (via modern token) ⇒ true; macOS first submission ⇒ false.
        #expect(byPlatform["IOS"]?.hasReleasedVersion == true)
        #expect(byPlatform["MAC_OS"]?.hasReleasedVersion == false)
    }

    /// End-to-end whatsNew gating: iOS first submission + macOS released ⇒ the
    /// reconciler drops `whatsNew` for the iOS version-loc create but keeps it
    /// for macOS — the multi-platform mixed case that fix #1 would otherwise
    /// unmask into a first-submission iOS 409 STATE_ERROR.
    @Test("per-platform plan drops whatsNew for first-submission iOS, keeps it for released macOS")
    internal func perPlatformWhatsNewGating() async throws {
        let emptyLocs = #"{"data":[],"links":{}}"#
        StubState.reset(with: [
            StubResponse(status: 200, body: Self.twoPlatformVersionsWithReleased(
                stateKey: "appVersionState", iosReleased: false, macReleased: true,
                releasedToken: "READY_FOR_DISTRIBUTION"
            )),
            StubResponse(status: 200, body: emptyLocs),  // GET ios-v locs
            StubResponse(status: 200, body: emptyLocs),  // GET mac-v locs
        ])

        let client = Self.makeClient()
        let snapshots = try await ASCRegisterCLI.snapshotPlatformVersions(
            client: client, appId: "app-1", filter: .all, versionFilter: nil
        )

        let cfg = MetadataConfig(
            appMeta: AppMeta(
                app: "sudoku", appleId: "1", copyright: nil,
                categories: AppMeta.Categories(
                    primary: nil, primaryFirstSub: nil, primarySecondSub: nil,
                    secondary: nil, secondaryFirstSub: nil, secondarySecondSub: nil
                )
            ),
            listings: [ListingLocale(
                locale: "en-US", name: nil, subtitle: nil, privacyPolicyUrl: nil,
                description: "desc", keywords: nil, promotionalText: nil,
                whatsNew: "Bug fixes", marketingUrl: nil, supportUrl: nil
            )]
        )

        func createWhatsNew(for platform: String) -> String?? {
            guard let snap = snapshots.first(where: { $0.platform == platform }) else { return nil }
            let remote = MetadataRemoteState(
                versionId: snap.versionId,
                versionLocalizations: snap.versionLocalizations,
                hasReleasedVersion: snap.hasReleasedVersion
            )
            let actions = MetadataReconciler.plan(config: cfg, remote: remote)
            return actions.compactMap { action -> String?? in
                if case let .createVersionLoc(_, _, payload) = action { return payload.whatsNew }
                return nil
            }.first
        }

        // iOS first submission → whatsNew dropped (nil) → no 409.
        #expect(createWhatsNew(for: "IOS") == .some(.none))
        // macOS released → whatsNew preserved.
        #expect(createWhatsNew(for: "MAC_OS") == .some(.some("Bug fixes")))
    }

    /// Multi-platform mixed idempotency: iOS version-loc already matches config,
    /// macOS does not ⇒ exactly ONE update action across both platforms (the
    /// macOS update); iOS plans a no-op (`versionLocUnchanged`).
    @Test("metadata mixed idempotency: iOS already at target, macOS not → exactly one update")
    internal func mixedIdempotencyOneUpdate() async throws {
        // Both platforms released so whatsNew gating doesn't interfere; the only
        // drift is macOS's description.
        StubState.reset(with: [
            StubResponse(status: 200, body: Self.twoPlatformVersionsWithReleased(
                stateKey: "appVersionState", iosReleased: true, macReleased: true,
                releasedToken: "READY_FOR_DISTRIBUTION"
            )),
            // iOS locs: already "synced desc" → matches config → no update.
            StubResponse(status: 200, body: #"""
            {"data":[{"id":"ios-loc-en","type":"appStoreVersionLocalizations",
            "attributes":{"locale":"en-US","description":"synced desc"}}],"links":{}}
            """#),
            // macOS locs: stale "old desc" → differs → one update.
            StubResponse(status: 200, body: #"""
            {"data":[{"id":"mac-loc-en","type":"appStoreVersionLocalizations",
            "attributes":{"locale":"en-US","description":"old desc"}}],"links":{}}
            """#),
        ])

        let client = Self.makeClient()
        let snapshots = try await ASCRegisterCLI.snapshotPlatformVersions(
            client: client, appId: "app-1", filter: .all, versionFilter: nil
        )
        let listing = ListingLocale(
            locale: "en-US", name: nil, subtitle: nil, privacyPolicyUrl: nil,
            description: "synced desc", keywords: nil, promotionalText: nil,
            whatsNew: nil, marketingUrl: nil, supportUrl: nil
        )
        let cfg = MetadataConfig(
            appMeta: AppMeta(
                app: "sudoku", appleId: "1", copyright: nil,
                categories: AppMeta.Categories(
                    primary: nil, primaryFirstSub: nil, primarySecondSub: nil,
                    secondary: nil, secondaryFirstSub: nil, secondarySecondSub: nil
                )
            ),
            listings: [listing]
        )

        var updates: [String] = []  // versionId of each platform planning an update
        for snap in snapshots {
            let remote = MetadataRemoteState(
                versionId: snap.versionId,
                versionLocalizations: snap.versionLocalizations,
                hasReleasedVersion: snap.hasReleasedVersion
            )
            for action in MetadataReconciler.plan(config: cfg, remote: remote) {
                if case .updateVersionLoc = action { updates.append(snap.versionId) }
            }
        }

        // Exactly one update across both platforms — the macOS one. iOS matched
        // config so it stayed a no-op (no spurious second update).
        #expect(updates == ["mac-v"])
    }

    // MARK: - Screenshot upload (reserve → PUT → commit + checksum)

    /// A reservation response with ONE upload operation (single-part). The
    /// `uploadOperations` array carries the asset-storage PUT url + the byte
    /// window + the headers ASC wants echoed back. `offset`/`length` cover the
    /// whole `byteLen`-byte asset.
    private static func reservationBody(id: String, putURL: String, byteLen: Int) -> String {
        #"""
        {"data":{"id":"\#(id)","type":"appScreenshots",
          "attributes":{"fileName":"01-home.png","fileSize":\#(byteLen),
            "assetDeliveryState":{"state":"AWAITING_UPLOAD"},
            "uploadOperations":[
              {"method":"PUT","url":"\#(putURL)","offset":0,"length":\#(byteLen),
               "requestHeaders":[{"name":"Content-Type","value":"image/png"}]}
            ]}}}
        """#
    }

    /// `reserveScreenshot` parses the POST response into (id, operations); the
    /// reserve POST body carries fileName + fileSize + the appScreenshotSet
    /// relationship.
    @Test("reserveScreenshot posts fileName/fileSize/set and parses uploadOperations")
    internal func reserveParsesUploadOperations() async throws {
        StubState.reset(with: [
            StubResponse(status: 201, body: Self.reservationBody(
                id: "shot-1", putURL: "https://assets.apple.example/upload/abc", byteLen: 12
            )),
        ])
        let client = Self.makeClient()
        let (id, ops) = try await client.reserveScreenshot(
            screenshotSetId: "set-9", fileName: "01-home.png", fileSize: 12
        )
        #expect(id == "shot-1")
        #expect(ops.count == 1)
        #expect(ops[0].method == "PUT")
        #expect(ops[0].url == "https://assets.apple.example/upload/abc")
        #expect(ops[0].offset == 0)
        #expect(ops[0].length == 12)
        #expect(ops[0].requestHeaders["Content-Type"] == "image/png")

        let reqs = StubState.recordedRequests()
        #expect(reqs.count == 1)
        #expect(reqs[0].method == "POST")
        #expect(reqs[0].url.hasSuffix("/v1/appScreenshots"))
        let bodyJSON = try #require(
            try JSONSerialization.jsonObject(with: reqs[0].body) as? [String: Any]
        )
        let data = try #require(bodyJSON["data"] as? [String: Any])
        let attrs = try #require(data["attributes"] as? [String: Any])
        #expect(attrs["fileName"] as? String == "01-home.png")
        #expect((attrs["fileSize"] as? NSNumber)?.intValue == 12)
        let rels = try #require(data["relationships"] as? [String: Any])
        let setRel = try #require(rels["appScreenshotSet"] as? [String: Any])
        let setData = try #require(setRel["data"] as? [String: Any])
        #expect(setData["type"] as? String == "appScreenshotSets")
        #expect(setData["id"] as? String == "set-9")
    }

    /// `uploadPart` PUTs exactly the operation's byte window to the asset URL
    /// (not the ASC base URL) with the supplied headers — and NO Authorization
    /// header (the asset URL self-authorizes; signing it with the ASC JWT is
    /// wrong).
    @Test("uploadPart PUTs the offset/length chunk to the asset URL, unsigned")
    internal func uploadPartSendsChunkUnsigned() async throws {
        let asset = Data("HELLOWORLD!!".utf8)  // 12 bytes
        // One operation covering bytes [3..<8) → "LOWOR".
        let operation = UploadOperation(
            method: "PUT",
            url: "https://assets.apple.example/upload/xyz",
            offset: 3, length: 5,
            requestHeaders: ["Content-Type": "image/png", "X-Apple-Token": "tok"]
        )
        StubState.reset(with: [StubResponse(status: 200, body: "")])
        let client = Self.makeClient()
        try await client.uploadPart(operation, of: asset)

        let reqs = StubState.recordedRequests()
        #expect(reqs.count == 1)
        #expect(reqs[0].method == "PUT")
        #expect(reqs[0].url == "https://assets.apple.example/upload/xyz")
        // Exactly the [3..<8) window was sent.
        #expect(reqs[0].body == Data("LOWOR".utf8))
        // The ASC-returned PUT headers are echoed back verbatim (the asset URL's
        // own auth token rides in `requestHeaders`).
        #expect(reqs[0].headers["Content-Type"] == "image/png")
        #expect(reqs[0].headers["X-Apple-Token"] == "tok")
        // And the ASC JWT must NOT be injected onto the asset-storage URL — that
        // endpoint is not api.appstoreconnect.apple.com and self-authorizes.
        #expect(reqs[0].headers["Authorization"] == nil)
    }

    /// Multi-part upload e2e: a reservation that returns TWO upload operations
    /// (Apple splits the asset into byte windows) must PUT each window in order,
    /// to the right URL, before a single commit PATCH carrying the WHOLE file's
    /// MD5. Guards the loop in `uploadOneScreenshot` against single-part-only
    /// assumptions (#370 CR).
    @Test("uploadScreenshots apply: PUTs every operation of a multi-part reservation")
    internal func uploadScreenshotsMultiPart() async throws {
        let bytes = Data("ABCDEFGHIJ".utf8)  // 10 bytes → split [0..<6) + [6..<10)
        let tree = try Self.makeScreenshotTree(
            device: "iphone-6.9", locale: "en", fileName: "01-home.png", bytes: bytes
        )
        defer { try? FileManager.default.removeItem(at: tree) }
        let expectedMD5 = AssetChecksum.md5Hex(bytes)

        let twoPartReservation = #"""
        {"data":{"id":"shot-mp","type":"appScreenshots",
          "attributes":{"fileName":"01-home.png","fileSize":10,
            "assetDeliveryState":{"state":"AWAITING_UPLOAD"},
            "uploadOperations":[
              {"method":"PUT","url":"https://assets.apple.example/u/p1","offset":0,"length":6,
               "requestHeaders":[{"name":"Content-Type","value":"image/png"}]},
              {"method":"PUT","url":"https://assets.apple.example/u/p2","offset":6,"length":4,
               "requestHeaders":[{"name":"Content-Type","value":"image/png"}]}
            ]}}}
        """#
        StubState.reset(with: [
            StubResponse(status: 200, body: #"""
            {"data":[{"id":"ios-v","type":"appStoreVersions",
            "attributes":{"versionString":"1.0","platform":"IOS",
            "appStoreState":"PREPARE_FOR_SUBMISSION"}}],"links":{}}
            """#),
            StubResponse(status: 200, body: #"""
            {"data":[{"id":"loc-en","type":"appStoreVersionLocalizations",
            "attributes":{"locale":"en-US"}}],"links":{}}
            """#),
            StubResponse(status: 200, body: #"{"data":[],"included":[],"links":{}}"#),  // no existing sets
            StubResponse(status: 201, body: #"""
            {"data":{"id":"set-67","type":"appScreenshotSets",
            "attributes":{"screenshotDisplayType":"APP_IPHONE_67"}}}
            """#),
            StubResponse(status: 201, body: twoPartReservation),
            StubResponse(status: 200, body: ""),  // PUT part 1
            StubResponse(status: 200, body: ""),  // PUT part 2
            StubResponse(status: 200, body: #"""
            {"data":{"id":"shot-mp","type":"appScreenshots",
            "attributes":{"assetDeliveryState":{"state":"COMPLETE"}}}}
            """#),
        ])

        let client = Self.makeClient()
        let assets = ScreenshotDiscovery.discover(
            screenshotsDir: tree.path, app: "sudoku", platform: .ios, localeFilter: "en"
        )
        try await ASCRegisterCLI.uploadScreenshots(
            client: client, appId: "app-1", ascLocale: "en-US",
            platform: .ios, assets: assets, apply: true
        )

        let reqs = StubState.recordedRequests()
        // GET×3, POST set, POST reserve, PUT, PUT, PATCH commit — TWO PUTs.
        #expect(reqs.map(\.method) == ["GET", "GET", "GET", "POST", "POST", "PUT", "PUT", "PATCH"])
        let puts = reqs.filter { $0.method == "PUT" }
        #expect(puts.count == 2)
        // Each window went to its own URL with exactly its byte slice, in order.
        #expect(puts[0].url == "https://assets.apple.example/u/p1")
        #expect(puts[0].body == Data("ABCDEF".utf8))
        #expect(puts[1].url == "https://assets.apple.example/u/p2")
        #expect(puts[1].body == Data("GHIJ".utf8))
        // A single commit carrying the WHOLE-file MD5, after both PUTs.
        let commit = try #require(reqs.first { $0.method == "PATCH" })
        let commitBody = try #require(
            try JSONSerialization.jsonObject(with: commit.body) as? [String: Any]
        )
        let commitAttrs = try #require((commitBody["data"] as? [String: Any])?["attributes"] as? [String: Any])
        #expect(commitAttrs["sourceFileChecksum"] as? String == expectedMD5)
    }

    /// `commitScreenshot` PATCHes /v1/appScreenshots/{id} with uploaded:true and
    /// the MD5 checksum the caller computed.
    @Test("commitScreenshot patches uploaded:true + sourceFileChecksum")
    internal func commitSendsChecksum() async throws {
        StubState.reset(with: [
            StubResponse(status: 200, body: #"""
            {"data":{"id":"shot-1","type":"appScreenshots",
            "attributes":{"assetDeliveryState":{"state":"COMPLETE"}}}}
            """#),
        ])
        let client = Self.makeClient()
        let checksum = AssetChecksum.md5Hex(Data("HELLOWORLD!!".utf8))
        _ = try await client.commitScreenshot(screenshotId: "shot-1", checksum: checksum)

        let reqs = StubState.recordedRequests()
        #expect(reqs.count == 1)
        #expect(reqs[0].method == "PATCH")
        #expect(reqs[0].url.hasSuffix("/v1/appScreenshots/shot-1"))
        let bodyJSON = try #require(
            try JSONSerialization.jsonObject(with: reqs[0].body) as? [String: Any]
        )
        let data = try #require(bodyJSON["data"] as? [String: Any])
        let attrs = try #require(data["attributes"] as? [String: Any])
        #expect(attrs["uploaded"] as? Bool == true)
        #expect(attrs["sourceFileChecksum"] as? String == checksum)
    }

    /// MD5 is the algorithm ASC expects; verify against a known vector so a
    /// future refactor can't silently swap the hash.
    @Test("AssetChecksum.md5Hex matches the known MD5 vector")
    internal func md5KnownVector() {
        // MD5("abc") = 900150983cd24fb0d6963f7d28e17f72
        #expect(AssetChecksum.md5Hex(Data("abc".utf8)) == "900150983cd24fb0d6963f7d28e17f72")
        #expect(AssetChecksum.md5Hex(Data()) == "d41d8cd98f00b204e9800998ecf8427e")
    }

    /// End-to-end orchestration in APPLY mode: GET versions → GET version-locs →
    /// GET existing sets (empty) → CREATE set → reserve POST → PUT chunk →
    /// commit PATCH. Asserts the full reserve→PUT→commit ordering AND that the
    /// committed checksum is the MD5 of the on-disk file bytes.
    @Test("uploadScreenshots apply: GET→createSet→reserve→PUT→commit with file MD5")
    internal func uploadScreenshotsApplyFullSequence() async throws {
        let tree = try Self.makeScreenshotTree(
            device: "iphone-6.9", locale: "en", fileName: "01-home.png",
            bytes: Data("PNGDATA-12345".utf8)
        )
        defer { try? FileManager.default.removeItem(at: tree) }
        let fileBytes = Data("PNGDATA-12345".utf8)
        let expectedMD5 = AssetChecksum.md5Hex(fileBytes)

        // iOS version + en-US version-loc + empty set list + create-set echo +
        // reservation + PUT 200 + commit 200.
        StubState.reset(with: [
            StubResponse(status: 200, body: #"""
            {"data":[{"id":"ios-v","type":"appStoreVersions",
            "attributes":{"versionString":"1.0","platform":"IOS",
            "appStoreState":"PREPARE_FOR_SUBMISSION"}}],"links":{}}
            """#),
            StubResponse(status: 200, body: #"""
            {"data":[{"id":"loc-en","type":"appStoreVersionLocalizations",
            "attributes":{"locale":"en-US"}}],"links":{}}
            """#),
            StubResponse(status: 200, body: #"{"data":[],"included":[],"links":{}}"#),  // no existing sets
            StubResponse(status: 201, body: #"""
            {"data":{"id":"set-67","type":"appScreenshotSets",
            "attributes":{"screenshotDisplayType":"APP_IPHONE_67"}}}
            """#),
            StubResponse(status: 201, body: Self.reservationBody(
                id: "shot-1", putURL: "https://assets.apple.example/u/1", byteLen: fileBytes.count
            )),
            StubResponse(status: 200, body: ""),  // PUT chunk
            StubResponse(status: 200, body: #"""
            {"data":{"id":"shot-1","type":"appScreenshots",
            "attributes":{"assetDeliveryState":{"state":"COMPLETE"}}}}
            """#),
        ])

        let client = Self.makeClient()
        let assets = ScreenshotDiscovery.discover(
            screenshotsDir: tree.path, app: "sudoku", platform: .ios, localeFilter: "en"
        )
        #expect(assets.count == 1)
        try await ASCRegisterCLI.uploadScreenshots(
            client: client, appId: "app-1", ascLocale: "en-US",
            platform: .ios, assets: assets, apply: true
        )

        let reqs = StubState.recordedRequests()
        let methods = reqs.map(\.method)
        // GET versions, GET version-locs, GET sets, POST set, POST reserve, PUT, PATCH commit.
        #expect(methods == ["GET", "GET", "GET", "POST", "POST", "PUT", "PATCH"])
        // The set was created for the iPhone 6.9" display type.
        let createSet = try #require(reqs.first { $0.url.hasSuffix("/v1/appScreenshotSets") })
        let setBody = try #require(
            try JSONSerialization.jsonObject(with: createSet.body) as? [String: Any]
        )
        let setAttrs = try #require((setBody["data"] as? [String: Any])?["attributes"] as? [String: Any])
        #expect(setAttrs["screenshotDisplayType"] as? String == "APP_IPHONE_67")
        // The PUT carried the file bytes; the commit carried that file's MD5.
        let put = try #require(reqs.first { $0.method == "PUT" })
        #expect(put.body == fileBytes)
        #expect(put.url == "https://assets.apple.example/u/1")
        let commit = try #require(reqs.first { $0.method == "PATCH" })
        let commitBody = try #require(
            try JSONSerialization.jsonObject(with: commit.body) as? [String: Any]
        )
        let commitAttrs = try #require((commitBody["data"] as? [String: Any])?["attributes"] as? [String: Any])
        #expect(commitAttrs["uploaded"] as? Bool == true)
        #expect(commitAttrs["sourceFileChecksum"] as? String == expectedMD5)
    }

    /// Idempotency: a file whose name already lives in the matching set is
    /// SKIPPED — no createSet, no reserve, no PUT, no commit. Only the read GETs
    /// run.
    @Test("uploadScreenshots apply: skips a file already present in the set")
    internal func uploadScreenshotsSkipsExisting() async throws {
        let tree = try Self.makeScreenshotTree(
            device: "iphone-6.9", locale: "en", fileName: "01-home.png",
            bytes: Data("PNGDATA".utf8)
        )
        defer { try? FileManager.default.removeItem(at: tree) }

        StubState.reset(with: [
            StubResponse(status: 200, body: #"""
            {"data":[{"id":"ios-v","type":"appStoreVersions",
            "attributes":{"versionString":"1.0","platform":"IOS",
            "appStoreState":"PREPARE_FOR_SUBMISSION"}}],"links":{}}
            """#),
            StubResponse(status: 200, body: #"""
            {"data":[{"id":"loc-en","type":"appStoreVersionLocalizations",
            "attributes":{"locale":"en-US"}}],"links":{}}
            """#),
            // Existing set already contains 01-home.png, COMPLETE, with the
            // MD5 of the local bytes → truly present → skip (#370: skip requires
            // BOTH a COMPLETE delivery state AND a matching checksum).
            StubResponse(status: 200, body: Self.existingSetBody(
                fileName: "01-home.png", state: "COMPLETE",
                checksum: AssetChecksum.md5Hex(Data("PNGDATA".utf8))
            )),
        ])

        let client = Self.makeClient()
        let assets = ScreenshotDiscovery.discover(
            screenshotsDir: tree.path, app: "sudoku", platform: .ios, localeFilter: "en"
        )
        try await ASCRegisterCLI.uploadScreenshots(
            client: client, appId: "app-1", ascLocale: "en-US",
            platform: .ios, assets: assets, apply: true
        )

        let methods = StubState.recordedRequests().map(\.method)
        // Only the three read GETs — no mutation for an already-present file.
        #expect(methods == ["GET", "GET", "GET"])
    }

    /// An existing-set `listScreenshotSets` body with a single screenshot whose
    /// `assetDeliveryState` + optional `sourceFileChecksum` are templated, so the
    /// #370 idempotency tests can drive COMPLETE-skip vs non-COMPLETE-reupload vs
    /// checksum-drift-reupload from one helper.
    private static func existingSetBody(
        fileName: String, state: String, checksum: String?
    ) -> String {
        let checksumAttr = checksum.map { #","sourceFileChecksum":"\#($0)""# } ?? ""
        return #"""
        {"data":[{"id":"set-67","type":"appScreenshotSets",
        "attributes":{"screenshotDisplayType":"APP_IPHONE_67"},
        "relationships":{"appScreenshots":{"data":[{"id":"shot-x","type":"appScreenshots"}]}}}],
        "included":[{"id":"shot-x","type":"appScreenshots",
        "attributes":{"fileName":"\#(fileName)","assetDeliveryState":{"state":"\#(state)"}\#(checksumAttr)}}],
        "links":{}}
        """#
    }

    /// The reserve→PUT→commit response triplet a single-part re-upload consumes,
    /// reusing the existing `set-67` (no createSet). Shared by the
    /// non-COMPLETE and checksum-drift re-upload tests.
    private static func reuploadResponses(byteLen: Int) -> [StubResponse] {
        [
            StubResponse(status: 201, body: Self.reservationBody(
                id: "shot-new", putURL: "https://assets.apple.example/u/9", byteLen: byteLen
            )),
            StubResponse(status: 200, body: ""),  // PUT chunk
            StubResponse(status: 200, body: #"""
            {"data":{"id":"shot-new","type":"appScreenshots",
            "attributes":{"assetDeliveryState":{"state":"COMPLETE"}}}}
            """#),
        ]
    }

    /// #370 Med-2: a screenshot with the right fileName but a NON-COMPLETE
    /// delivery state (a prior reserve whose PUT/commit failed) must be evicted
    /// (DELETE) and re-uploaded, not skipped forever.
    @Test("uploadScreenshots apply: deletes + re-uploads a non-COMPLETE existing screenshot")
    internal func uploadScreenshotsReuploadsNonComplete() async throws {
        let bytes = Data("PNGDATA-12345".utf8)
        let tree = try Self.makeScreenshotTree(
            device: "iphone-6.9", locale: "en", fileName: "01-home.png", bytes: bytes
        )
        defer { try? FileManager.default.removeItem(at: tree) }

        var responses = [
            StubResponse(status: 200, body: #"""
            {"data":[{"id":"ios-v","type":"appStoreVersions",
            "attributes":{"versionString":"1.0","platform":"IOS",
            "appStoreState":"PREPARE_FOR_SUBMISSION"}}],"links":{}}
            """#),
            StubResponse(status: 200, body: #"""
            {"data":[{"id":"loc-en","type":"appStoreVersionLocalizations",
            "attributes":{"locale":"en-US"}}],"links":{}}
            """#),
            StubResponse(status: 200, body: Self.existingSetBody(
                fileName: "01-home.png", state: "AWAITING_UPLOAD", checksum: nil
            )),
            StubResponse(status: 204, body: ""),  // DELETE the stale shot-x
        ]
        responses.append(contentsOf: Self.reuploadResponses(byteLen: bytes.count))
        StubState.reset(with: responses)

        let client = Self.makeClient()
        let assets = ScreenshotDiscovery.discover(
            screenshotsDir: tree.path, app: "sudoku", platform: .ios, localeFilter: "en"
        )
        try await ASCRegisterCLI.uploadScreenshots(
            client: client, appId: "app-1", ascLocale: "en-US",
            platform: .ios, assets: assets, apply: true
        )

        let reqs = StubState.recordedRequests()
        // GET versions, GET locs, GET sets, DELETE stale, reserve POST, PUT, commit PATCH.
        #expect(reqs.map(\.method) == ["GET", "GET", "GET", "DELETE", "POST", "PUT", "PATCH"])
        let del = try #require(reqs.first { $0.method == "DELETE" })
        #expect(del.url.hasSuffix("/v1/appScreenshots/shot-x"))
        // No createSet — the existing set-67 is reused for the re-reserve.
        #expect(!reqs.contains { $0.method == "POST" && $0.url.hasSuffix("/v1/appScreenshotSets") })
    }

    /// #370 Med-3: a COMPLETE screenshot whose `sourceFileChecksum` differs from
    /// the local file's MD5 (content drift) must be evicted + re-uploaded so ASC
    /// stops serving the stale image.
    @Test("uploadScreenshots apply: deletes + re-uploads on checksum drift")
    internal func uploadScreenshotsReuploadsOnChecksumDrift() async throws {
        let bytes = Data("PNGDATA-12345".utf8)
        let tree = try Self.makeScreenshotTree(
            device: "iphone-6.9", locale: "en", fileName: "01-home.png", bytes: bytes
        )
        defer { try? FileManager.default.removeItem(at: tree) }

        var responses = [
            StubResponse(status: 200, body: #"""
            {"data":[{"id":"ios-v","type":"appStoreVersions",
            "attributes":{"versionString":"1.0","platform":"IOS",
            "appStoreState":"PREPARE_FOR_SUBMISSION"}}],"links":{}}
            """#),
            StubResponse(status: 200, body: #"""
            {"data":[{"id":"loc-en","type":"appStoreVersionLocalizations",
            "attributes":{"locale":"en-US"}}],"links":{}}
            """#),
            // COMPLETE, but the stored checksum is for DIFFERENT bytes → drift.
            StubResponse(status: 200, body: Self.existingSetBody(
                fileName: "01-home.png", state: "COMPLETE",
                checksum: AssetChecksum.md5Hex(Data("OLD-STALE-BYTES".utf8))
            )),
            StubResponse(status: 204, body: ""),  // DELETE the drifted shot-x
        ]
        responses.append(contentsOf: Self.reuploadResponses(byteLen: bytes.count))
        StubState.reset(with: responses)

        let client = Self.makeClient()
        let assets = ScreenshotDiscovery.discover(
            screenshotsDir: tree.path, app: "sudoku", platform: .ios, localeFilter: "en"
        )
        try await ASCRegisterCLI.uploadScreenshots(
            client: client, appId: "app-1", ascLocale: "en-US",
            platform: .ios, assets: assets, apply: true
        )

        let reqs = StubState.recordedRequests()
        #expect(reqs.map(\.method) == ["GET", "GET", "GET", "DELETE", "POST", "PUT", "PATCH"])
        // The commit PATCH carried the NEW file's MD5 (the drift was corrected).
        let commit = try #require(reqs.first { $0.method == "PATCH" })
        let commitBody = try #require(
            try JSONSerialization.jsonObject(with: commit.body) as? [String: Any]
        )
        let commitAttrs = try #require((commitBody["data"] as? [String: Any])?["attributes"] as? [String: Any])
        #expect(commitAttrs["sourceFileChecksum"] as? String == AssetChecksum.md5Hex(bytes))
    }

    /// Dry-run (apply:false): resolves + lists, prints what WOULD upload, but
    /// issues NO mutating request (no createSet / reserve / PUT / commit).
    @Test("uploadScreenshots dry-run issues no mutating request")
    internal func uploadScreenshotsDryRunNoMutation() async throws {
        let tree = try Self.makeScreenshotTree(
            device: "iphone-6.9", locale: "en", fileName: "01-home.png",
            bytes: Data("PNGDATA".utf8)
        )
        defer { try? FileManager.default.removeItem(at: tree) }

        StubState.reset(with: [
            StubResponse(status: 200, body: #"""
            {"data":[{"id":"ios-v","type":"appStoreVersions",
            "attributes":{"versionString":"1.0","platform":"IOS",
            "appStoreState":"PREPARE_FOR_SUBMISSION"}}],"links":{}}
            """#),
            StubResponse(status: 200, body: #"""
            {"data":[{"id":"loc-en","type":"appStoreVersionLocalizations",
            "attributes":{"locale":"en-US"}}],"links":{}}
            """#),
            StubResponse(status: 200, body: #"{"data":[],"included":[],"links":{}}"#),
        ])

        let client = Self.makeClient(mode: .plan)
        let assets = ScreenshotDiscovery.discover(
            screenshotsDir: tree.path, app: "sudoku", platform: .ios, localeFilter: "en"
        )
        try await ASCRegisterCLI.uploadScreenshots(
            client: client, appId: "app-1", ascLocale: "en-US",
            platform: .ios, assets: assets, apply: false
        )

        let methods = StubState.recordedRequests().map(\.method)
        // Read-only: GET versions, GET version-locs, GET sets. Zero mutations.
        #expect(methods.allSatisfy { $0 == "GET" })
        #expect(methods == ["GET", "GET", "GET"])
    }

    /// Build a throwaway `screenshots/<app>/<device>/<locale>/<file>` tree under
    /// a temp dir for the discovery + file-read paths. Returns the root to pass
    /// as `--screenshots-dir`.
    private static func makeScreenshotTree(
        device: String, locale: String, fileName: String, bytes: Data
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-shots-\(UUID().uuidString)")
        let dir = root
            .appendingPathComponent("sudoku")
            .appendingPathComponent(device)
            .appendingPathComponent(locale)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try bytes.write(to: dir.appendingPathComponent(fileName))
        return root
    }
}
