// ASCClient IAP operations — split from ASCClient.swift to keep the main
// actor body within swiftlint `type_body_length` budget. Same actor, same
// isolation; this is purely a file split.
//
// Phase 1.a (issue #200): we ONLY read + mutate metadata on EXISTING IAP
// products. We do NOT POST `/v1/inAppPurchasesV2` (no product creation).
// We do NOT touch `/v1/inAppPurchasePriceSchedules` (pricing is Phase 1.b,
// separate PR).
//
// Endpoints used (all confirmed against `aaronsky/asc-swift` Generated
// path files — see proposal §3.1, §3.3, §3.5):
//   - GET   /v1/apps/{appId}/inAppPurchasesV2
//   - POST  /v1/inAppPurchaseLocalizations
//   - PATCH /v1/inAppPurchaseLocalizations/{id}
//   - GET   /v1/inAppPurchases/{id}/inAppPurchaseLocalizations
//   - PATCH /v1/inAppPurchases/{id}                          ← UNCONFIRMED path
//
// The IAP root PATCH path is the most likely shape per the v2 API conventions
// but has not been runtime-verified. First live `apply` will surface any
// mismatch as an ENTITY_ERROR which `asc-apply-round.js` will decode (per the
// dispatch brief's "PATCH path verification deferred to runtime" decision).

import Foundation

extension ASCClient {

    // MARK: - Read IAP by productId under an app

    /// GET all IAPs under the app, with their localizations side-loaded
    /// in a single request via `?include=inAppPurchaseLocalizations`
    /// (proposal §3.1). The returned `APICollectionWithIncluded` carries
    /// both the IAP primary resources and the localization side-load,
    /// plus a relationship map so the caller can re-attach each
    /// localization to its parent IAP without a follow-up GET.
    ///
    /// We side-load instead of issuing a per-IAP
    /// `GET /v1/inAppPurchases/{id}/inAppPurchaseLocalizations` because
    /// that relationship URL responds 404 / PATH_ERROR (the relationship
    /// name is not exposed under the legacy `inAppPurchases` path; the
    /// resource lives under `inAppPurchasesV2` and the only reliable read
    /// path is via the parent collection's `include`).
    ///
    /// Price schedules are intentionally not side-loaded — pricing is
    /// Phase 1.b.
    internal func listIAPs(appId: String) async throws -> APICollectionWithIncluded {
        let path = "/v1/apps/\(appId)/inAppPurchasesV2"
            + "?include=inAppPurchaseLocalizations"
            + "&fields[inAppPurchases]=name,productId,reviewNote,familySharable,state,inAppPurchaseType,inAppPurchaseLocalizations"
            + "&fields[inAppPurchaseLocalizations]=locale,name,description,state"
        return try await getCollectionWithIncluded(path: path)
    }

    // MARK: - PATCH IAP root attributes

    /// PATCH the v2 IAP root resource with Phase 1.a fields (`name`,
    /// `reviewNote`, `familySharable`).
    ///
    /// Verified against aaronsky/asc-swift Entities/InAppPurchaseV2UpdateRequest.swift
    /// + Paths/PathsV2InAppPurchasesWithID.swift on 2026-06-02:
    /// - Path is `/v2/inAppPurchases/{id}` (V2 is in path **prefix**, not
    ///   resource name).
    /// - JSON:API `data.type` is `"inAppPurchases"` (lowercase plural,
    ///   NOT `inAppPurchasesV2`).
    /// - Earlier attempts failed: `/v1/inAppPurchases/{id}` → 403
    ///   FORBIDDEN_ERROR (GET-only); `/v1/inAppPurchasesV2/{id}` → 404
    ///   NOT_FOUND (no such resource).
    internal func updateIAP(
        iapId: String,
        config: IAPProduct
    ) async throws -> APIResource {
        let body: [String: Any] = [
            "data": [
                "type": "inAppPurchases",
                "id": iapId,
                "attributes": [
                    "name": config.referenceName,
                    "reviewNote": config.reviewNote,
                    "familySharable": config.familyShareable
                ]
            ]
        ]
        return try await mutate(
            method: "PATCH",
            path: "/v2/inAppPurchases/\(iapId)",
            body: body
        )
    }

    // MARK: - IAP localization create / update

    internal func createIAPLocalization(
        iapId: String,
        locale: String,
        name: String,
        description: String
    ) async throws -> APIResource {
        let body: [String: Any] = [
            "data": [
                "type": "inAppPurchaseLocalizations",
                "attributes": [
                    "locale": locale,
                    "name": name,
                    "description": description
                ],
                "relationships": [
                    "inAppPurchaseV2": [
                        "data": ["type": "inAppPurchases", "id": iapId]
                    ]
                ]
            ]
        ]
        return try await mutate(
            method: "POST",
            path: "/v1/inAppPurchaseLocalizations",
            body: body
        )
    }

    internal func updateIAPLocalization(
        localizationId: String,
        name: String,
        description: String
    ) async throws -> APIResource {
        let body: [String: Any] = [
            "data": [
                "type": "inAppPurchaseLocalizations",
                "id": localizationId,
                "attributes": [
                    "name": name,
                    "description": description
                ]
            ]
        ]
        return try await mutate(
            method: "PATCH",
            path: "/v1/inAppPurchaseLocalizations/\(localizationId)",
            body: body
        )
    }
}
