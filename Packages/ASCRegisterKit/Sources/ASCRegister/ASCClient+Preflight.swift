// ASCClient submission-preflight reads (issue: ops preflight gate).
//
// Every method here is a READ-ONLY GET against a to-one relationship or a
// singleton sub-resource that ASC returns EITHER as a 404 OR as a
// `200 {"data": null}` when the thing has never been set — the exact shape
// is UNCONFIRMED per-endpoint (mirrors `getIAPReviewScreenshot`'s own
// UNCONFIRMED note), so every helper tolerates both and resolves to `nil`.
// `nil` here means "not configured yet", which the preflight logic (see
// Preflight.swift) turns into a BLOCK row — never a crash.
//
// Endpoint / attribute names verified against Apple's official App Store
// Connect API reference (developer.apple.com/documentation/appstoreconnectapi,
// retrieved 2026-07-29):
//   - appStoreVersions.copyright / .releaseType (enum MANUAL/AFTER_APPROVAL/
//     SCHEDULED) — AppStoreVersion.Attributes.
//   - appStoreVersions relationships: `build`, `appStoreReviewDetail`.
//   - appInfos relationship: `ageRatingDeclaration`.
//   - apps.contentRightsDeclaration (enum DOES_NOT_USE_THIRD_PARTY_CONTENT /
//     USES_THIRD_PARTY_CONTENT) — App.Attributes.
//   - apps relationships: `appPriceSchedule`, `reviewSubmissions`.
//   - appStoreReviewDetail attributes: contactEmail, contactFirstName,
//     contactLastName, contactPhone, demoAccountName, demoAccountPassword,
//     demoAccountRequired, notes.
//   - reviewSubmissions attributes: platform, state (READY_FOR_REVIEW,
//     WAITING_FOR_REVIEW, IN_REVIEW, UNRESOLVED_ISSUES, CANCELING,
//     COMPLETING, COMPLETE); no DELETE operation is documented for this
//     resource (matches the live 2026-07-28 finding that a stray submission
//     could not be deleted, only cancelled from an in-review state).
// The exact GET path for a to-one relationship (`/v1/<parent>/<id>/<rel>`)
// follows the SAME convention already used elsewhere in this file
// (`getGameCenterDetail`, `getIAPReviewScreenshot`) — UNCONFIRMED beyond that
// convention until a live run's error/success body confirms it.

import Foundation

extension ASCClient {

    // MARK: - App-level (issue #6 contentRightsDeclaration, #4 appPriceSchedule, #9 reviewSubmissions)

    /// GET `/v1/apps/{appId}` for the fields the preflight needs.
    internal func getApp(appId: String) async throws -> APIResource {
        try await getResource(path: "/v1/apps/\(appId)?fields[apps]=name,bundleId,contentRightsDeclaration")
    }

    /// GET the app's price schedule. `nil` when Apple has never had one set
    /// for this app (`STATE_ERROR.APP_PRICING_REQUIRED` at submission time).
    internal func getAppPriceSchedule(appId: String) async throws -> APIResource? {
        try await getOptionalResource(path: "/v1/apps/\(appId)/appPriceSchedule")
    }

    /// GET every `reviewSubmissions` record for the app (any platform, any
    /// state) — used to detect a stray non-terminal submission blocking a
    /// new one from being created.
    internal func listReviewSubmissions(appId: String) async throws -> [APIResource] {
        try await getCollection(
            path: "/v1/apps/\(appId)/reviewSubmissions?fields[reviewSubmissions]=platform,state,submittedDate"
        )
    }

    // MARK: - AppInfo-level (issue #5 ageRatingDeclaration)

    /// GET the age rating declaration for an `appInfo`. `nil` when it has
    /// never been answered.
    internal func getAgeRatingDeclaration(appInfoId: String) async throws -> APIResource? {
        try await getOptionalResource(path: "/v1/appInfos/\(appInfoId)/ageRatingDeclaration")
    }

    // MARK: - Version-level (issue #1 releaseType, #2 build, #7 reviewDetail)

    /// GET the build attached to an `appStoreVersion`. `nil` when none is
    /// attached yet.
    internal func getAttachedBuild(versionId: String) async throws -> APIResource? {
        try await getOptionalResource(path: "/v1/appStoreVersions/\(versionId)/build")
    }

    /// GET the App Review contact record for an `appStoreVersion`. `nil`
    /// when it was never created (the live 2026-07-28 finding: this record
    /// did not exist at all, not merely empty).
    internal func getAppStoreReviewDetail(versionId: String) async throws -> APIResource? {
        try await getOptionalResource(path: "/v1/appStoreVersions/\(versionId)/appStoreReviewDetail")
    }

    /// GET candidate builds to attach via `--fix`, newest first, with each
    /// build's `preReleaseVersion` (→ `platform`) side-loaded so the caller
    /// can pick the newest VALID build for a specific platform without a
    /// separate GET per build (Build itself carries no `platform` attribute).
    internal func listRecentBuildsWithPlatform(appId: String) async throws -> APICollectionWithIncluded {
        let path = "/v1/apps/\(appId)/builds"
            + "?include=preReleaseVersion"
            + "&fields[builds]=processingState,uploadedDate,version,preReleaseVersion"
            + "&fields[preReleaseVersions]=platform,version"
            + "&sort=-uploadedDate&limit=20"
        return try await getCollectionWithIncluded(path: path)
    }

    // MARK: - `--fix` mutations (copyright / releaseType / build attach — see main.swift)

    /// PATCH `/v1/appStoreVersions/{id}` — only the attributes/relationships
    /// the caller supplies are sent (both optional so a caller can fix just
    /// one of copyright/releaseType/build in a single request, or combine
    /// all three).
    internal func fixAppStoreVersion(
        versionId: String,
        copyright: String?,
        releaseType: String?,
        attachBuildId: String?
    ) async throws -> APIResource {
        var attributes: [String: Any] = [:]
        if let copyright { attributes["copyright"] = copyright }
        if let releaseType { attributes["releaseType"] = releaseType }
        var data: [String: Any] = ["type": "appStoreVersions", "id": versionId]
        if !attributes.isEmpty { data["attributes"] = attributes }
        if let attachBuildId {
            data["relationships"] = [
                "build": ["data": ["type": "builds", "id": attachBuildId]],
            ]
        }
        return try await mutate(method: "PATCH", path: "/v1/appStoreVersions/\(versionId)", body: ["data": data])
    }

    // MARK: - Shared optional-singleton GET (mirrors `getIAPReviewScreenshot`)

    /// GET a to-one relationship / singleton resource, tolerating BOTH a 404
    /// response AND a `200 {"data": null}` response as "not configured yet"
    /// (the exact shape ASC uses per-endpoint is UNCONFIRMED — see file
    /// header). Any other non-2xx status still throws.
    private func getOptionalResource(path: String) async throws -> APIResource? {
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
        guard let inner = json["data"] as? [String: Any] else { return nil }
        return try APIResource.fromDict(inner, path: path, status: status, data: data)
    }
}
