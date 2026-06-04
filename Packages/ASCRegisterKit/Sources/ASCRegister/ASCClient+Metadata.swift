// ASCClient app-listing metadata operations (issue #310) — split from
// ASCClient.swift to keep the main actor body within swiftlint
// `type_body_length` budget. Same actor, same isolation.
//
// Resource map (plan §2):
//   apps/{id}
//   ├── appInfos                      (pick the editable one)
//   │   ├── appInfoLocalizations      ← name, subtitle, privacyPolicyUrl
//   │   └── rel primary/secondaryCategory → appCategories
//   └── appStoreVersions
//       └── appStoreVersionLocalizations ← description, keywords,
//             promotionalText, whatsNew, marketingUrl, supportUrl
//
// Endpoint paths follow the documented ASC REST conventions
// (https://developer.apple.com/documentation/appstoreconnectapi). Attribute
// names that were UNCONFIRMED in plan §7 are resolved against the live GET in
// the first `metadata plan` pass; the read paths below GET-and-print so that
// pass surfaces Apple's real schema in one run.

import Foundation

extension ASCClient {

    // MARK: - appInfos (name / subtitle / privacyPolicyUrl + categories)

    /// GET all `appInfos` for the app, with their localizations + category
    /// relationships side-loaded in one request. An app can have several
    /// `appInfos` (one per app-store state); the caller picks the editable
    /// one by `state` (plan §7 UNCONFIRMED → resolved at run time).
    internal func listAppInfos(appId: String) async throws -> APICollectionWithIncluded {
        let path = "/v1/apps/\(appId)/appInfos"
            + "?include=appInfoLocalizations,primaryCategory,secondaryCategory"
            + "&fields[appInfos]=appStoreState,state,appStoreAgeRating,"
            + "appInfoLocalizations,primaryCategory,secondaryCategory"
            + "&fields[appInfoLocalizations]=locale,name,subtitle,privacyPolicyUrl"
        return try await getCollectionWithIncluded(path: path)
    }

    internal func createAppInfoLocalization(
        appInfoId: String,
        locale: String,
        name: String?,
        subtitle: String?,
        privacyPolicyUrl: String?
    ) async throws -> APIResource {
        var attributes: [String: Any] = ["locale": locale]
        if let name { attributes["name"] = name }
        if let subtitle { attributes["subtitle"] = subtitle }
        if let privacyPolicyUrl { attributes["privacyPolicyUrl"] = privacyPolicyUrl }
        let body: [String: Any] = [
            "data": [
                "type": "appInfoLocalizations",
                "attributes": attributes,
                "relationships": [
                    "appInfo": ["data": ["type": "appInfos", "id": appInfoId]],
                ],
            ],
        ]
        return try await mutate(method: "POST", path: "/v1/appInfoLocalizations", body: body)
    }

    internal func updateAppInfoLocalization(
        localizationId: String,
        name: String?,
        subtitle: String?,
        privacyPolicyUrl: String?
    ) async throws -> APIResource {
        var attributes: [String: Any] = [:]
        if let name { attributes["name"] = name }
        if let subtitle { attributes["subtitle"] = subtitle }
        if let privacyPolicyUrl { attributes["privacyPolicyUrl"] = privacyPolicyUrl }
        let body: [String: Any] = [
            "data": [
                "type": "appInfoLocalizations",
                "id": localizationId,
                "attributes": attributes,
            ],
        ]
        return try await mutate(
            method: "PATCH",
            path: "/v1/appInfoLocalizations/\(localizationId)",
            body: body
        )
    }

    // MARK: - appStoreVersions (description / keywords / ... per version)

    /// GET the app's `appStoreVersions`, with version localizations
    /// side-loaded. Used to find the single editable version (plan §5:
    /// version creation stays user-owned; we GET-and-fail-loud if missing).
    internal func listAppStoreVersions(appId: String) async throws -> APICollectionWithIncluded {
        let path = "/v1/apps/\(appId)/appStoreVersions"
            + "?include=appStoreVersionLocalizations"
            + "&fields[appStoreVersions]=versionString,appStoreState,appVersionState,"
            + "appStoreVersionLocalizations"
            + "&fields[appStoreVersionLocalizations]=locale,description,keywords,"
            + "promotionalText,whatsNew,marketingUrl,supportUrl"
        return try await getCollectionWithIncluded(path: path)
    }

    internal func createVersionLocalization(
        versionId: String,
        locale: String,
        description: String?,
        keywords: String?,
        promotionalText: String?,
        whatsNew: String?,
        marketingUrl: String?,
        supportUrl: String?
    ) async throws -> APIResource {
        var attributes: [String: Any] = ["locale": locale]
        if let description { attributes["description"] = description }
        if let keywords { attributes["keywords"] = keywords }
        if let promotionalText { attributes["promotionalText"] = promotionalText }
        // `whatsNew` omitted when nil. On a first submission (no released
        // predecessor) the reconciler nils it upstream so this guard skips it,
        // avoiding ASC's `409 STATE_ERROR — Attribute 'whatsNew' cannot be
        // edited at this time` (issue #310).
        if let whatsNew { attributes["whatsNew"] = whatsNew }
        if let marketingUrl { attributes["marketingUrl"] = marketingUrl }
        if let supportUrl { attributes["supportUrl"] = supportUrl }
        let body: [String: Any] = [
            "data": [
                "type": "appStoreVersionLocalizations",
                "attributes": attributes,
                "relationships": [
                    "appStoreVersion": [
                        "data": ["type": "appStoreVersions", "id": versionId],
                    ],
                ],
            ],
        ]
        return try await mutate(
            method: "POST",
            path: "/v1/appStoreVersionLocalizations",
            body: body
        )
    }

    internal func updateVersionLocalization(
        localizationId: String,
        description: String?,
        keywords: String?,
        promotionalText: String?,
        whatsNew: String?,
        marketingUrl: String?,
        supportUrl: String?
    ) async throws -> APIResource {
        var attributes: [String: Any] = [:]
        if let description { attributes["description"] = description }
        if let keywords { attributes["keywords"] = keywords }
        if let promotionalText { attributes["promotionalText"] = promotionalText }
        // `whatsNew` omitted when nil — see the create path: the reconciler
        // nils it on a first submission to avoid `409 STATE_ERROR` (issue #310).
        if let whatsNew { attributes["whatsNew"] = whatsNew }
        if let marketingUrl { attributes["marketingUrl"] = marketingUrl }
        if let supportUrl { attributes["supportUrl"] = supportUrl }
        let body: [String: Any] = [
            "data": [
                "type": "appStoreVersionLocalizations",
                "id": localizationId,
                "attributes": attributes,
            ],
        ]
        return try await mutate(
            method: "PATCH",
            path: "/v1/appStoreVersionLocalizations/\(localizationId)",
            body: body
        )
    }

    // MARK: - appCategories (category relationship on appInfos)

    /// GET the full ASC category catalog (top-level genres + their
    /// subcategories side-loaded). Resolves the human-label → id-token map
    /// (plan §7 UNCONFIRMED). Returns the primary `data[]` (genres) plus the
    /// `included[]` (subcategories).
    internal func listAppCategories() async throws -> APICollectionWithIncluded {
        let path = "/v1/appCategories"
            + "?include=subcategories"
            + "&exists[parent]=false"
            + "&fields[appCategories]=platforms,subcategories"
        return try await getCollectionWithIncluded(path: path)
    }

    /// PATCH the `appInfos` primary + secondary category relationships.
    /// Each relationship points at one `appCategories` id (the sub-category
    /// id when present, else the genre id). Idempotent: a PATCH to the same
    /// ids is a no-op ASC-side.
    internal func updateAppInfoCategories(
        appInfoId: String,
        primaryCategoryId: String?,
        secondaryCategoryId: String?
    ) async throws -> APIResource {
        var relationships: [String: Any] = [:]
        if let primaryCategoryId {
            relationships["primaryCategory"] = [
                "data": ["type": "appCategories", "id": primaryCategoryId],
            ]
        }
        if let secondaryCategoryId {
            relationships["secondaryCategory"] = [
                "data": ["type": "appCategories", "id": secondaryCategoryId],
            ]
        }
        let body: [String: Any] = [
            "data": [
                "type": "appInfos",
                "id": appInfoId,
                "relationships": relationships,
            ],
        ]
        return try await mutate(
            method: "PATCH",
            path: "/v1/appInfos/\(appInfoId)",
            body: body
        )
    }
}
