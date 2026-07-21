// ASCClient IAP "App Store Review Screenshot" upload operations — the IAP
// counterpart of ASCClient+Screenshots.swift's appScreenshots reserve → PUT →
// commit flow. Split into its own file for the same swiftlint
// `type_body_length` reason as ASCClient+Screenshots.swift; same actor, same
// isolation.
//
// Endpoint shapes verified against `aaronsky/asc-swift` Generated
// Entities/Paths (CreateAPI-compiled from Apple's ASC OpenAPI spec, checked
// 2026-07-20) — the same source-of-truth method ASCClient+IAP.swift already
// uses:
//   - POST   /v1/inAppPurchaseAppStoreReviewScreenshots
//     `InAppPurchaseAppStoreReviewScreenshotCreateRequest`: `data.type` =
//     `"inAppPurchaseAppStoreReviewScreenshots"`, `data.attributes` =
//     `{fileSize, fileName}`, `data.relationships.inAppPurchaseV2.data` =
//     `{type: "inAppPurchases", id}`. Response carries `uploadOperations[]`,
//     parsed by the SAME `UploadOperation.parse` the appScreenshots path uses
//     (both reservation bodies share the `data.attributes.uploadOperations`
//     shape).
//   - PATCH  /v1/inAppPurchaseAppStoreReviewScreenshots/{id}
//     `InAppPurchaseAppStoreReviewScreenshotUpdateRequest`: `data.attributes`
//     = `{sourceFileChecksum, uploaded}` (the Swift property is `isUploaded`,
//     JSON-coded as `"uploaded"`).
//   - DELETE /v1/inAppPurchaseAppStoreReviewScreenshots/{id}
//   - GET    /v2/inAppPurchases/{id}/appStoreReviewScreenshot — the
//     to-one "related" resource for idempotency (an IAP has at most ONE
//     review screenshot, unlike the many-per-set appScreenshots).
//     UNCONFIRMED: whether an IAP with no screenshot yet responds 404 or
//     `200 {"data": null}` — the generated response type's `data` is
//     non-optional, which usually implies a 404-when-absent shape, but this
//     was not runtime-verified. `getIAPReviewScreenshot` below tolerates
//     BOTH shapes (404 → nil, `200 {"data": null}` → nil) so either behavior
//     is handled without crashing; first live run should confirm which one
//     ASC actually returns.
//
// The byte-PUT loop (`uploadPart`) and the MD5 checksum (`AssetChecksum`)
// are the resource-agnostic parts of the reserve→PUT→commit dance — they
// already live in ASCClient+Screenshots.swift and are reused here verbatim,
// not duplicated.
//
// No live calls in tests — the URLProtocol stub harness drives the whole
// sequence offline (ASCClientURLProtocolTests), same as the appScreenshots
// path.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension ASCClient {

    /// RESERVE an IAP review-screenshot upload: POST
    /// /v1/inAppPurchaseAppStoreReviewScreenshots with the file name + byte
    /// size + parent IAP relationship. Mirrors `reserveScreenshot` exactly,
    /// just against the IAP endpoint + `inAppPurchaseV2` relationship key.
    internal func reserveIAPScreenshot(
        iapId: String,
        fileName: String,
        fileSize: Int
    ) async throws -> (id: String, operations: [UploadOperation]) {
        let body: [String: Any] = [
            "data": [
                "type": "inAppPurchaseAppStoreReviewScreenshots",
                "attributes": [
                    "fileName": fileName,
                    "fileSize": fileSize,
                ],
                "relationships": [
                    "inAppPurchaseV2": [
                        "data": ["type": "inAppPurchases", "id": iapId],
                    ],
                ],
            ],
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let path = "/v1/inAppPurchaseAppStoreReviewScreenshots"
        // `send` (not `mutate`): same reasoning as `reserveScreenshot` — the
        // reservation POST must actually run; the plan/apply gate lives in
        // the COMMAND (only builds an `.apply` client under `--i-am-sure`).
        let (data, status) = try await send(method: "POST", path: path, body: bodyData)
        guard (200..<300).contains(status) else {
            throw ClientError.httpStatus(code: status, path: path, body: truncateBody(data))
        }
        let resource = try APIResource.decodeSingle(from: data, path: path, status: status)
        return (resource.id, UploadOperation.parse(reservationBody: data))
    }

    /// COMMIT a reserved IAP review screenshot: PATCH
    /// /v1/inAppPurchaseAppStoreReviewScreenshots/{id} with `uploaded:true` +
    /// the MD5 `sourceFileChecksum`. Mirrors `commitScreenshot`.
    internal func commitIAPScreenshot(
        screenshotId: String,
        checksum: String
    ) async throws -> APIResource {
        let body: [String: Any] = [
            "data": [
                "type": "inAppPurchaseAppStoreReviewScreenshots",
                "id": screenshotId,
                "attributes": [
                    "uploaded": true,
                    "sourceFileChecksum": checksum,
                ],
            ],
        ]
        return try await mutate(
            method: "PATCH",
            path: "/v1/inAppPurchaseAppStoreReviewScreenshots/\(screenshotId)",
            body: body
        )
    }

    /// DELETE /v1/inAppPurchaseAppStoreReviewScreenshots/{id}. Used to evict a
    /// stale IAP review screenshot before re-reserving a replacement — an IAP
    /// has at most one, and ASC has no in-place replace (mirrors
    /// `deleteScreenshot`'s evict-then-upload for app screenshots).
    internal func deleteIAPScreenshot(screenshotId: String) async throws {
        let path = "/v1/inAppPurchaseAppStoreReviewScreenshots/\(screenshotId)"
        let (data, status) = try await send(method: "DELETE", path: path, body: nil)
        guard (200..<300).contains(status) else {
            throw ClientError.httpStatus(code: status, path: path, body: truncateBody(data))
        }
    }

    /// GET /v2/inAppPurchases/{id}/appStoreReviewScreenshot — the IAP's
    /// single (at most one) review screenshot, for the idempotency check.
    /// Returns `nil` when the IAP has no screenshot yet: tolerates BOTH a
    /// 404 response AND a `200 {"data": null}` response (see file header —
    /// which shape ASC actually sends here is UNCONFIRMED).
    internal func getIAPReviewScreenshot(iapId: String) async throws -> APIResource? {
        let path = "/v2/inAppPurchases/\(iapId)/appStoreReviewScreenshot"
        let (data, status) = try await send(method: "GET", path: path, body: nil)
        if status == 404 { return nil }
        guard (200..<300).contains(status) else {
            throw ClientError.httpStatus(code: status, path: path, body: truncateBody(data))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.decodeFailed(
                reason: "invalid JSON", path: path, status: status, bodyExcerpt: truncateBody(data)
            )
        }
        // A missing key AND an explicit `null` both fail this cast — either
        // shape of "no screenshot yet" resolves to nil here.
        guard let inner = json["data"] as? [String: Any] else { return nil }
        return try APIResource.fromDict(inner, path: path, status: status, data: data)
    }
}
