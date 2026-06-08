// ASCClient App Store screenshot UPLOAD operations — Apple's multi-part
// reservation flow (reserve → PUT chunks → commit). Split from ASCClient.swift
// to keep the actor body within swiftlint `type_body_length` budget; same actor,
// same isolation.
//
// The flow (verified against fastlane spaceship + Apple ASC API docs, 2026-06-05):
//   1. GET-or-create the appScreenshotSet for (appStoreVersionLocalization,
//      screenshotDisplayType).
//   2. POST /v1/appScreenshots {fileName,fileSize, rel:appScreenshotSet} →
//      response carries `uploadOperations[]` (method/url/offset/length/
//      requestHeaders) + the new screenshot id.
//   3. PUT each upload operation: the raw bytes for that offset/length to the
//      Apple-returned URL with the returned headers. These URLs carry their OWN
//      auth token in the headers — we must NOT inject the ASC JWT (it is not an
//      api.appstoreconnect.apple.com URL).
//   4. PATCH /v1/appScreenshots/{id} {uploaded:true, sourceFileChecksum:<MD5>}
//      to commit the reservation. ASC verifies the MD5 against the bytes it
//      received and moves the asset to COMPLETE.
//
// No live calls in tests — the URLProtocol stub harness drives the whole
// sequence offline (ASCClientURLProtocolTests).

import CryptoKit
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Upload-operation value types (pure, decodable, testable)

/// One PUT operation Apple returns in an `appScreenshots` reservation. Apple
/// splits the asset into one or more parts; each part names the destination
/// URL, the byte window (`offset`/`length`) of the source file it covers, and
/// the headers to send. `requestHeaders` is a JSON array of `{name,value}`
/// objects (NOT a dictionary) — decoded into a flat `[String: String]` here.
internal struct UploadOperation: Sendable, Equatable {
    internal let method: String
    internal let url: String
    internal let offset: Int
    internal let length: Int
    internal let requestHeaders: [String: String]

    /// Parse the `uploadOperations[]` array out of an `appScreenshots` POST
    /// response body. Pure + static so the reservation decode is unit-testable
    /// without URLSession (mirrors `ASCClient.nextPageLink`).
    internal static func parse(reservationBody data: Data) -> [UploadOperation] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inner = json["data"] as? [String: Any],
              let attrs = inner["attributes"] as? [String: Any],
              let ops = attrs["uploadOperations"] as? [[String: Any]]
        else { return [] }
        return ops.compactMap { operation in
            guard let method = operation["method"] as? String,
                  let url = operation["url"] as? String,
                  let offset = (operation["offset"] as? NSNumber)?.intValue,
                  let length = (operation["length"] as? NSNumber)?.intValue
            else { return nil }
            var headers: [String: String] = [:]
            if let raw = operation["requestHeaders"] as? [[String: Any]] {
                for header in raw {
                    if let name = header["name"] as? String, let value = header["value"] as? String {
                        headers[name] = value
                    }
                }
            }
            return UploadOperation(
                method: method, url: url, offset: offset, length: length, requestHeaders: headers
            )
        }
    }
}

// MARK: - Checksum (real logic, stub-tested)

internal enum AssetChecksum {
    /// Lowercase hex MD5 of the asset bytes — the value ASC expects in the
    /// commit PATCH's `sourceFileChecksum` (matches fastlane spaceship's
    /// `Digest::MD5.hexdigest`). MD5 is what ASC's content-integrity check uses;
    /// CryptoKit's `Insecure.MD5` is the right primitive despite the name (this
    /// is an upload-integrity hash, not a security boundary).
    internal static func md5Hex(_ data: Data) -> String {
        Insecure.MD5.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

// MARK: - Screenshot upload client methods

extension ASCClient {

    /// List the `appScreenshotSets` already attached to an
    /// `appStoreVersionLocalization`, with the screenshots in each set
    /// side-loaded so idempotency can compare by fileName without an extra GET.
    internal func listScreenshotSets(
        versionLocalizationId: String
    ) async throws -> APICollectionWithIncluded {
        let path = "/v1/appStoreVersionLocalizations/\(versionLocalizationId)/appScreenshotSets"
            + "?include=appScreenshots"
            + "&fields[appScreenshotSets]=screenshotDisplayType,appScreenshots"
            + "&fields[appScreenshots]=fileName,fileSize,assetDeliveryState,sourceFileChecksum"
            + "&limit=50"
        return try await getCollectionWithIncluded(path: path)
    }

    /// CREATE an `appScreenshotSet` for `(versionLocalizationId, displayType)`.
    /// One set per (locale, displayType) is allowed by ASC; the caller GETs
    /// first and only creates when absent (the "Screenshots Already Exists"
    /// STATE_ERROR otherwise).
    internal func createScreenshotSet(
        versionLocalizationId: String,
        displayType: String
    ) async throws -> APIResource {
        let body: [String: Any] = [
            "data": [
                "type": "appScreenshotSets",
                "attributes": ["screenshotDisplayType": displayType],
                "relationships": [
                    "appStoreVersionLocalization": [
                        "data": [
                            "type": "appStoreVersionLocalizations",
                            "id": versionLocalizationId,
                        ],
                    ],
                ],
            ],
        ]
        return try await mutate(method: "POST", path: "/v1/appScreenshotSets", body: body)
    }

    /// RESERVE a screenshot upload: POST /v1/appScreenshots with the file name +
    /// byte size + parent set. The response carries the new screenshot id plus
    /// the `uploadOperations[]` describing the multi-part PUT to perform. The
    /// raw response `Data` is returned so the caller can parse the operations
    /// via `UploadOperation.parse` (the minimal `APIResource` decoder drops the
    /// nested array). Returns `(id, operations)`.
    internal func reserveScreenshot(
        screenshotSetId: String,
        fileName: String,
        fileSize: Int
    ) async throws -> (id: String, operations: [UploadOperation]) {
        let body: [String: Any] = [
            "data": [
                "type": "appScreenshots",
                "attributes": [
                    "fileName": fileName,
                    "fileSize": fileSize,
                ],
                "relationships": [
                    "appScreenshotSet": [
                        "data": ["type": "appScreenshotSets", "id": screenshotSetId],
                    ],
                ],
            ],
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        // `send` (not `mutate`): the reservation POST must actually run; the
        // plan/apply gate lives in the COMMAND (it builds an `.apply` client only
        // when `--i-am-sure` is given), so the client itself does not short-circuit.
        let (data, status) = try await send(method: "POST", path: "/v1/appScreenshots", body: bodyData)
        guard (200..<300).contains(status) else {
            throw ClientError.httpStatus(code: status, path: "/v1/appScreenshots", body: truncateBody(data))
        }
        let resource = try APIResource.decodeSingle(from: data, path: "/v1/appScreenshots", status: status)
        return (resource.id, UploadOperation.parse(reservationBody: data))
    }

    /// PUT one upload operation's byte window to the Apple-returned URL. The URL
    /// is an asset-storage endpoint that carries its OWN auth in the returned
    /// `requestHeaders` — we must NOT inject the ASC JWT or rewrite the host
    /// (unlike every other request, which `makeRequest` resolves against
    /// `baseURL` + signs). Slices `data[offset..<offset+length]` and sends it
    /// with exactly the headers ASC supplied.
    internal func uploadPart(_ operation: UploadOperation, of data: Data) async throws {
        guard let url = URL(string: operation.url) else {
            throw ClientError.invalidURL(operation.url)
        }
        let end = operation.offset + operation.length
        guard operation.offset >= 0, end <= data.count else {
            throw ClientError.httpStatus(
                code: -1, path: operation.url,
                body: "upload operation window [\(operation.offset)..<\(end)] out of bounds for \(data.count) bytes"
            )
        }
        let chunk = data.subdata(in: operation.offset..<end)
        var req = URLRequest(url: url)
        req.httpMethod = operation.method
        for (name, value) in operation.requestHeaders {
            req.setValue(value, forHTTPHeaderField: name)
        }
        req.httpBody = chunk
        let (respData, status) = try await perform(req)
        guard (200..<300).contains(status) else {
            throw ClientError.httpStatus(code: status, path: operation.url, body: truncateBody(respData))
        }
    }

    /// COMMIT a reserved screenshot: PATCH /v1/appScreenshots/{id} with
    /// `uploaded:true` + the MD5 `sourceFileChecksum`. ASC verifies the checksum
    /// against the bytes it received from the PUT(s) and advances the asset to
    /// COMPLETE. Must run ONLY after every upload operation has succeeded.
    internal func commitScreenshot(
        screenshotId: String,
        checksum: String
    ) async throws -> APIResource {
        let body: [String: Any] = [
            "data": [
                "type": "appScreenshots",
                "id": screenshotId,
                "attributes": [
                    "uploaded": true,
                    "sourceFileChecksum": checksum,
                ],
            ],
        ]
        return try await mutate(
            method: "PATCH",
            path: "/v1/appScreenshots/\(screenshotId)",
            body: body
        )
    }

    /// DELETE /v1/appScreenshots/{id}. Used to evict a stale screenshot before
    /// re-reserving a replacement (issue #370): either a prior reservation left
    /// in a non-COMPLETE `assetDeliveryState`, or a COMPLETE asset whose source
    /// bytes drifted (checksum mismatch). Mirrors fastlane deliver's
    /// delete-then-upload — ASC has no in-place screenshot replace.
    internal func deleteScreenshot(screenshotId: String) async throws {
        let path = "/v1/appScreenshots/\(screenshotId)"
        // `send` (not `mutate`): DELETE returns 204 with an EMPTY body, which
        // `mutate`'s `decodeSingle` would reject (it requires a `data` object).
        // The apply/plan gate is enforced by the COMMAND only building an
        // `.apply` client under `--i-am-sure`, mirroring `reserveScreenshot`.
        let (data, status) = try await send(method: "DELETE", path: path, body: nil)
        guard (200..<300).contains(status) else {
            throw ClientError.httpStatus(code: status, path: path, body: truncateBody(data))
        }
    }
}
