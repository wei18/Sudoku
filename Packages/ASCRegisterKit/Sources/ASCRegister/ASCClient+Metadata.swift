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
        // Side-load ALL SIX category relationships so drift compares against
        // the genre + both sub slots, not just the two genres (issue #310 —
        // the old 2-slot include made sub drift invisible and mis-classified
        // the live category state).
        let path = "/v1/apps/\(appId)/appInfos"
            + "?include=appInfoLocalizations,"
            + "primaryCategory,primarySubcategoryOne,primarySubcategoryTwo,"
            + "secondaryCategory,secondarySubcategoryOne,secondarySubcategoryTwo"
            + "&fields[appInfos]=appStoreState,state,appStoreAgeRating,"
            + "appInfoLocalizations,"
            + "primaryCategory,primarySubcategoryOne,primarySubcategoryTwo,"
            + "secondaryCategory,secondarySubcategoryOne,secondarySubcategoryTwo"
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

    /// GET the app's `appStoreVersions`. Used to find the single editable
    /// version + compute `hasReleasedVersion` (plan §5: version creation stays
    /// user-owned; we GET-and-fail-loud if missing). Version localizations are
    /// fetched SEPARATELY via the paginated `listVersionLocalizations` — the
    /// `?include=` side-load truncated and missed an existing locale → a
    /// CREATE/UPDATE mis-classification (issue #310).
    internal func listAppStoreVersions(appId: String) async throws -> APICollectionWithIncluded {
        let path = "/v1/apps/\(appId)/appStoreVersions"
            + "?fields[appStoreVersions]=versionString,appStoreState,appVersionState"
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

    /// PATCH the `appInfos` SIX category relationships: the two top-level
    /// genres (`primaryCategory` / `secondaryCategory`) and up to two
    /// sub-categories each (`…SubcategoryOne` / `…SubcategoryTwo`). The genre
    /// goes in the `…Category` slot and each sub in its own subcategory slot —
    /// sending a sub as the genre was the live `409 RELATIONSHIP.INVALID`
    /// (issue #310). A `nil` slot is omitted from the PATCH. Idempotent.
    internal func updateAppInfoCategories(
        appInfoId: String,
        categories: MetadataCategoryIds
    ) async throws -> APIResource {
        var relationships: [String: Any] = [:]
        func add(_ name: String, _ id: String?) {
            guard let id else { return }
            relationships[name] = ["data": ["type": "appCategories", "id": id]]
        }
        add("primaryCategory", categories.primary)
        add("primarySubcategoryOne", categories.primarySubOne)
        add("primarySubcategoryTwo", categories.primarySubTwo)
        add("secondaryCategory", categories.secondary)
        add("secondarySubcategoryOne", categories.secondarySubOne)
        add("secondarySubcategoryTwo", categories.secondarySubTwo)
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

    // MARK: - appStoreVersionLocalizations (reliable, paginated list)

    /// List ALL `appStoreVersionLocalizations` for one version, following
    /// `links.next` pagination (issue #310). The `?include=…` side-load on the
    /// `appStoreVersions` GET truncates at the default page size, so an
    /// existing locale (the live `es-ES`) could be missed → mis-classified as
    /// CREATE → `409 ATTRIBUTE.INVALID.DUPLICATE`. Hitting the version's own
    /// relationship endpoint with pagination captures every existing loc.
    internal func listVersionLocalizations(versionId: String) async throws -> [APIResource] {
        let path = "/v1/appStoreVersions/\(versionId)/appStoreVersionLocalizations"
            + "?fields[appStoreVersionLocalizations]=locale,description,keywords,"
            + "promotionalText,whatsNew,marketingUrl,supportUrl"
            + "&limit=200"
        return try await getAllPages(path: path)
    }

    /// List ALL `appInfoLocalizations` for one appInfo, following pagination
    /// (issue #310 — same truncation risk as version-locs; keeps the appInfo
    /// snapshot complete so existing locales classify as UPDATE).
    internal func listAppInfoLocalizations(appInfoId: String) async throws -> [APIResource] {
        let path = "/v1/appInfos/\(appInfoId)/appInfoLocalizations"
            + "?fields[appInfoLocalizations]=locale,name,subtitle,privacyPolicyUrl"
            + "&limit=200"
        return try await getAllPages(path: path)
    }
}
