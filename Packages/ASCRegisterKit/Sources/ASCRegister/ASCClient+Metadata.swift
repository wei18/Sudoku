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

    // MARK: - appStoreVersions versionString rename (#310)

    /// PATCH `/v1/appStoreVersions/{id}` to rename the version's
    /// `versionString`. Only valid for an EDITABLE version with no build
    /// attached (PREPARE_FOR_SUBMISSION etc.); the caller (`SetVersionResolver`)
    /// gates the state before this is invoked. The body shape follows the ASC
    /// `appStoreVersions` PATCH reference: `data.type/id/attributes.versionString`.
    internal func setVersionString(
        versionId: String,
        versionString: String
    ) async throws -> APIResource {
        let body = ASCClient.setVersionStringBody(versionId: versionId, versionString: versionString)
        return try await mutate(
            method: "PATCH",
            path: "/v1/appStoreVersions/\(versionId)",
            body: body
        )
    }

    /// Pure builder for the `setVersionString` PATCH body. Kept static so the
    /// payload shape is unit-testable without URLSession (mirrors
    /// `nextPageLink` / `isDuplicateValueError`).
    internal static func setVersionStringBody(
        versionId: String,
        versionString: String
    ) -> [String: Any] {
        [
            "data": [
                "type": "appStoreVersions",
                "id": versionId,
                "attributes": ["versionString": versionString],
            ],
        ]
    }
}

// MARK: - Editable-version selection for `metadata set-version` (#310)

/// Pure resolver that picks the single editable `appStoreVersion` to rename and
/// refuses released/locked ones. No I/O — fed the decoded version list so the
/// state guard + disambiguation logic is unit-testable without a live API.
internal enum SetVersionResolver {

    /// Version states whose `versionString` may still be edited (no build
    /// locked in). Same set the metadata snapshot uses (ASCClient+Metadata
    /// `snapshotMetadata`) — kept here as the single source for the guard.
    internal static let editableVersionStates: Set<String> = [
        "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
        "METADATA_REJECTED", "INVALID_BINARY", "WAITING_FOR_REVIEW",
    ]

    internal struct Version: Sendable, Equatable {
        internal let id: String
        internal let versionString: String
        internal let state: String
        internal init(id: String, versionString: String, state: String) {
            self.id = id
            self.versionString = versionString
            self.state = state
        }
    }

    internal enum ResolveError: Error, CustomStringConvertible, Equatable {
        case noVersions
        case noneEditable(states: [String])
        case ambiguous(versionStrings: [String])
        case locked(versionString: String, state: String)

        internal var description: String {
            switch self {
            case .noVersions:
                return "no appStoreVersions found for this app"
            case .noneEditable(let states):
                return "no editable appStoreVersion to rename (states present: "
                    + "\(states.sorted().joined(separator: ", "))). Only versions in "
                    + "\(SetVersionResolver.editableVersionStates.sorted().joined(separator: ", ")) "
                    + "may be renamed."
            case .ambiguous(let versionStrings):
                return "multiple editable appStoreVersions "
                    + "(\(versionStrings.joined(separator: ", "))) and none is "
                    + "PREPARE_FOR_SUBMISSION — disambiguate with --version <string>."
            case .locked(let versionString, let state):
                return "appStoreVersion \(versionString) is in state \(state), which is "
                    + "released/locked — refusing to rename. Only editable versions "
                    + "(\(SetVersionResolver.editableVersionStates.sorted().joined(separator: ", "))) "
                    + "may be renamed."
            }
        }
    }

    /// Pick the editable version to rename.
    ///
    /// - When `versionFilter` is set, restrict to versions whose
    ///   `versionString` equals it, then apply the editable guard — this also
    ///   covers the disambiguation case (caller passes `--version`).
    /// - With no filter: if exactly one editable → that one; if several editable
    ///   → the PREPARE_FOR_SUBMISSION one, else `.ambiguous`.
    /// - If a filter names a single version that is released/locked → `.locked`
    ///   (clear error naming the state), not a silent skip.
    internal static func choose(
        versions: [Version],
        versionFilter: String?
    ) -> Result<Version, ResolveError> {
        guard !versions.isEmpty else { return .failure(.noVersions) }

        let candidates = versionFilter.map { filter in
            versions.filter { $0.versionString == filter }
        } ?? versions

        // A filter that names exactly one version (released or not) gets a
        // precise locked/editable verdict rather than a generic "none editable".
        if versionFilter != nil, candidates.count == 1, let only = candidates.first,
           !editableVersionStates.contains(only.state) {
            return .failure(.locked(versionString: only.versionString, state: only.state))
        }

        let editable = candidates.filter { editableVersionStates.contains($0.state) }
        switch editable.count {
        case 0:
            return .failure(.noneEditable(states: candidates.map(\.state)))
        case 1:
            return .success(editable[0])
        default:
            if let prepare = editable.first(where: { $0.state == "PREPARE_FOR_SUBMISSION" }) {
                return .success(prepare)
            }
            return .failure(.ambiguous(versionStrings: editable.map(\.versionString)))
        }
    }
}
