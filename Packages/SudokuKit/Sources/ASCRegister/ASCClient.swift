// ASCClient — thin async wrapper over the App Store Connect REST API.
//
// We do NOT model the full ASC schema. Each method sends a hand-rolled JSON
// body matching the documented shape and decodes only the few fields we
// need (id, attributes.<minimal>). The ASC API is documented at
// https://developer.apple.com/documentation/appstoreconnectapi — but the
// Game Center sub-tree (`gameCenterLeaderboards`, `gameCenterAchievements`,
// `gameCenterDetails`) has incomplete public docs as of writing; UNCONFIRMED
// markers below flag the spots that need a real GET response to verify.
//
// Logging: every request body is printed in dry-run mode (`plan`). In
// `apply` mode we print "POST /v1/... → 201" status lines only.

// swiftlint:disable trailing_comma

import CryptoKit
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

internal actor ASCClient {

    internal struct Auth: Sendable {
        internal let keyId: String
        internal let issuerId: String
        internal let keyPEM: String
    }

    internal enum Mode: Sendable, Equatable {
        case plan   // dry-run: print, don't send mutations (GETs still run).
        case apply  // execute.
    }

    internal enum ClientError: Error, Sendable, Equatable {
        case httpStatus(code: Int, path: String, body: String)
        // TODO: remove if still unused after error refactor settles
        case missingResponseBody
        case decodeFailed(reason: String, path: String, status: Int, bodyExcerpt: String)
        case invalidURL(String)
        case unsupportedOnLinux  // FoundationNetworking lacks `data(for:)` async
    }

    /// Maximum bytes of response body retained in error messages.
    /// Bodies larger than this are truncated with an explicit marker so the
    /// reader knows content was elided rather than silently cut.
    internal static let errorBodyByteCap: Int = 2048

    private let auth: Auth
    private let mode: Mode
    private let session: URLSession
    private let baseURL: URL
    private let log: @Sendable (String) -> Void

    internal init(
        auth: Auth,
        mode: Mode,
        baseURL: URL = URL(string: "https://api.appstoreconnect.apple.com")!, // swiftlint:disable:this force_unwrapping
        session: URLSession = .shared,
        log: @escaping @Sendable (String) -> Void = { print($0) }
    ) {
        self.auth = auth
        self.mode = mode
        self.baseURL = baseURL
        self.session = session
        self.log = log
    }

    // MARK: - Game Center detail lookup

    /// UNCONFIRMED: exact endpoint shape. Public ASC docs suggest
    /// `GET /v1/apps/{appId}/gameCenterDetail` (singular). Resolve by
    /// running a manual `curl` against the user's app and pasting the
    /// JSON shape here.
    internal func getGameCenterDetail(appId: String) async throws -> APIResource {
        try await getResource(path: "/v1/apps/\(appId)/gameCenterDetail")
    }

    // MARK: - Leaderboards

    internal func listLeaderboards(detailId: String) async throws -> [APIResource] {
        // UNCONFIRMED: relationship path. Likely
        // `/v1/gameCenterDetails/{id}/gameCenterLeaderboards`.
        try await getCollection(path: "/v1/gameCenterDetails/\(detailId)/gameCenterLeaderboards")
    }

    internal func createLeaderboard(
        detailId: String,
        config: LeaderboardConfig
    ) async throws -> APIResource {
        // UNCONFIRMED: exact `type` literal and recurrence nesting. Best
        // guess based on ASC OpenAPI shape:
        let body: [String: Any] = [
            "data": [
                "type": "gameCenterLeaderboards",
                "attributes": [
                    "referenceName": config.referenceName,
                    "vendorIdentifier": config.id,
                    "scoreFormat": config.scoreFormatType,
                    "scoreSortType": config.sortOrder,
                    "defaultFormatter": [
                        // UNCONFIRMED: minimum/maximum field names.
                        "scoreRangeStart": "1",
                        "scoreRangeEnd": String(Config.leaderboardScoreMaxMilliseconds)
                    ],
                    "recurrenceRule": [
                        // UNCONFIRMED: ASC may want "DURATION_DAYS": 1 or an
                        // ISO-8601 "P1D" duration, or a frequency enum.
                        "frequency": "DAILY",
                        "duration": "P1D"
                    ]
                ],
                "relationships": [
                    "gameCenterDetail": [
                        "data": ["type": "gameCenterDetails", "id": detailId]
                    ]
                ]
            ]
        ]
        return try await mutate(method: "POST", path: "/v1/gameCenterLeaderboards", body: body)
    }

    internal func updateLeaderboard(
        leaderboardId: String,
        config: LeaderboardConfig
    ) async throws -> APIResource {
        let body: [String: Any] = [
            "data": [
                "type": "gameCenterLeaderboards",
                "id": leaderboardId,
                "attributes": [
                    "referenceName": config.referenceName
                ]
            ]
        ]
        return try await mutate(method: "PATCH", path: "/v1/gameCenterLeaderboards/\(leaderboardId)", body: body)
    }

    internal func listLeaderboardLocalizations(leaderboardId: String) async throws -> [APIResource] {
        try await getCollection(path: "/v1/gameCenterLeaderboards/\(leaderboardId)/localizations")
    }

    internal func createLeaderboardLocalization(
        leaderboardId: String,
        locale: String,
        title: String
    ) async throws -> APIResource {
        let body: [String: Any] = [
            "data": [
                "type": "gameCenterLeaderboardLocalizations",
                "attributes": [
                    "locale": locale,
                    "name": title
                ],
                "relationships": [
                    "gameCenterLeaderboard": [
                        "data": ["type": "gameCenterLeaderboards", "id": leaderboardId]
                    ]
                ]
            ]
        ]
        return try await mutate(method: "POST", path: "/v1/gameCenterLeaderboardLocalizations", body: body)
    }

    internal func updateLeaderboardLocalization(
        localizationId: String,
        title: String
    ) async throws -> APIResource {
        let body: [String: Any] = [
            "data": [
                "type": "gameCenterLeaderboardLocalizations",
                "id": localizationId,
                "attributes": ["name": title]
            ]
        ]
        return try await mutate(
            method: "PATCH",
            path: "/v1/gameCenterLeaderboardLocalizations/\(localizationId)",
            body: body
        )
    }

    // MARK: - Plumbing
    // Achievement operations live in ASCClient+Achievements.swift to keep this
    // actor body within swiftlint type_body_length budget.

    fileprivate func makeRequest(method: String, path: String, body: Data?) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw ClientError.invalidURL(path)
        }
        let token = try JWT.sign(
            keyId: auth.keyId,
            issuerId: auth.issuerId,
            keyPEM: auth.keyPEM
        )
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = body
        return req
    }

    internal func getResource(path: String) async throws -> APIResource {
        let (data, status) = try await send(method: "GET", path: path, body: nil)
        guard (200..<300).contains(status) else {
            throw ClientError.httpStatus(code: status, path: path, body: truncateBody(data))
        }
        return try APIResource.decodeSingle(from: data, path: path, status: status)
    }

    internal func getCollection(path: String) async throws -> [APIResource] {
        let (data, status) = try await send(method: "GET", path: path, body: nil)
        guard (200..<300).contains(status) else {
            throw ClientError.httpStatus(code: status, path: path, body: truncateBody(data))
        }
        return try APIResource.decodeCollection(from: data, path: path, status: status)
    }

    internal func mutate(method: String, path: String, body: [String: Any]) async throws -> APIResource {
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        if mode == .plan {
            log("[plan] \(method) \(path)\n\(stringify(bodyData))")
            // Return a stub resource so reconciler can keep going.
            return APIResource(id: "<dry-run>", type: "stub", attributes: [:])
        }
        let (data, status) = try await send(method: method, path: path, body: bodyData)
        guard (200..<300).contains(status) else {
            throw ClientError.httpStatus(code: status, path: path, body: truncateBody(data))
        }
        log("[apply] \(method) \(path) → \(status)")
        return try APIResource.decodeSingle(from: data, path: path, status: status)
    }

    fileprivate func send(method: String, path: String, body: Data?) async throws -> (Data, Int) {
        let req = try makeRequest(method: method, path: path, body: body)
        #if canImport(FoundationNetworking)
        // Linux URLSession lacks async — ASCRegister is Apple-only.
        throw ClientError.unsupportedOnLinux
        #else
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (data, status)
        #endif
    }

    fileprivate func stringify(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? "<\(data.count) bytes non-utf8>"
    }
}

/// Returns a UTF-8 excerpt of `data` capped at `ASCClient.errorBodyByteCap` bytes.
/// When the input exceeds the cap, appends an explicit
/// `... <truncated, N more bytes>` marker so the reader knows content was
/// elided rather than silently cut. Non-UTF-8 payloads degrade to a byte-count
/// placeholder (same shape as `ASCClient.stringify`).
internal func truncateBody(_ data: Data) -> String {
    let cap = ASCClient.errorBodyByteCap
    if data.count <= cap {
        return String(data: data, encoding: .utf8) ?? "<\(data.count) bytes non-utf8>"
    }
    let head = data.prefix(cap)
    let remaining = data.count - cap
    guard let headString = String(data: head, encoding: .utf8) else {
        return "<\(data.count) bytes non-utf8>"
    }
    return "\(headString)... <truncated, \(remaining) more bytes>"
}

// MARK: - Minimal JSON:API decoding

internal struct APIResource: Sendable, Equatable {
    internal let id: String
    internal let type: String
    /// Subset of attributes we care about. Stored as opaque strings.
    internal let attributes: [String: String]

    internal static func decodeSingle(from data: Data, path: String, status: Int) throws -> APIResource {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inner = json["data"] as? [String: Any]
        else {
            throw ASCClient.ClientError.decodeFailed(
                reason: "missing data",
                path: path,
                status: status,
                bodyExcerpt: truncateBody(data)
            )
        }
        return try fromDict(inner, path: path, status: status, data: data)
    }

    internal static func decodeCollection(from data: Data, path: String, status: Int) throws -> [APIResource] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]]
        else {
            throw ASCClient.ClientError.decodeFailed(
                reason: "missing data array",
                path: path,
                status: status,
                bodyExcerpt: truncateBody(data)
            )
        }
        return try arr.map { try fromDict($0, path: path, status: status, data: data) }
    }

    private static func fromDict(
        _ dict: [String: Any],
        path: String,
        status: Int,
        data: Data
    ) throws -> APIResource {
        guard let id = dict["id"] as? String,
              let type = dict["type"] as? String
        else {
            throw ASCClient.ClientError.decodeFailed(
                reason: "missing id/type",
                path: path,
                status: status,
                bodyExcerpt: truncateBody(data)
            )
        }
        var attrs: [String: String] = [:]
        if let raw = dict["attributes"] as? [String: Any] {
            for (key, value) in raw {
                if let str = value as? String {
                    attrs[key] = str
                } else if let num = value as? NSNumber {
                    attrs[key] = num.stringValue
                }
            }
        }
        return APIResource(id: id, type: type, attributes: attrs)
    }
}
