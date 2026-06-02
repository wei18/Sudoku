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

// swiftlint:disable trailing_comma

import Foundation

extension ASCClient {

    // MARK: - Read IAP by productId under an app

    /// GET the single IAP matching `productId` under the given app, with
    /// localizations side-loaded. Returns nil if ASC has no IAP with that
    /// product id (the caller treats this as "product not yet created in
    /// ASC web UI" — Phase 1.a never creates products).
    ///
    /// Uses the `inAppPurchasesV2` filter endpoint (see proposal §3.1).
    /// We don't side-load price schedules in Phase 1.a — pricing lives in
    /// the future 1.b implementation.
    internal func listIAPs(appId: String) async throws -> [APIResource] {
        // The filter narrows server-side to a single result for our use
        // case, but we use the collection decoder so missing-product is a
        // simple empty array rather than a 404.
        let path = "/v1/apps/\(appId)/inAppPurchasesV2"
            + "?fields[inAppPurchases]=name,productId,reviewNote,familySharable,state,inAppPurchaseType"
        return try await getCollection(path: path)
    }

    /// GET all localizations attached to an existing IAP. Returns the
    /// `inAppPurchaseLocalizations` collection.
    internal func listIAPLocalizations(iapId: String) async throws -> [APIResource] {
        try await getCollection(
            path: "/v1/inAppPurchases/\(iapId)/inAppPurchaseLocalizations"
                + "?fields[inAppPurchaseLocalizations]=locale,name,description,state"
        )
    }

    // MARK: - PATCH IAP root attributes

    /// PATCH the `inAppPurchases` resource with the Phase 1.a fields
    /// (`name`, `reviewNote`, `familySharable`; ASC's v2 IAP root resource
    /// uses `name` for what we call the internal reference label — distinct
    /// from the per-locale localization `name`). The exact path
    /// shape (`/v1/inAppPurchases/{id}` vs `/v1/inAppPurchasesV2/{id}`) is
    /// unverified for v2 products at the time of writing; first live apply
    /// will surface any mismatch via `asc-apply-round.js`'s ENTITY_ERROR
    /// loop (proposal §3.5 open question 1).
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
            path: "/v1/inAppPurchases/\(iapId)",
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
