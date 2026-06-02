// ReconcilerIAPTests — pure-function tests on the IAP slice of the
// reconciler (issue #200, Phase 1.a). Mirrors `ReconcilerTests` shape.
//
// Coverage matrix (per dispatch brief):
//   - missing localization → create
//   - existing match       → unchanged
//   - existing mismatch    → update
//   - root attribute drift → updateIAP
//   - missing IAP product  → no actions (no createIAP; Phase 1.a skips)

// swiftlint:disable identifier_name trailing_comma

internal import Foundation
internal import Testing
@testable import ASCRegister

@Suite("Reconciler IAP")
internal struct ReconcilerIAPTests {

    // MARK: - Fixtures

    private static let removeAds = IAPProduct(
        productId: "com.wei18.sudoku.iap.remove_ads",
        referenceName: "Remove Ads v1",
        familyShareable: true,
        reviewNote: "Test review note."
    )

    private static let onlyRemoveAds = ConfigSnapshot(
        leaderboards: [],
        achievements: [],
        iaps: [removeAds]
    )

    private static let enOnly: XCStringsParser.LocalizedKeys = [
        "en": [
            "iap.remove_ads.name": "Remove Ads",
            "iap.remove_ads.description": "Removes all ads.",
        ],
    ]

    // MARK: - Tests

    @Test("Missing IAP on ASC: reconciler emits no actions (Phase 1.a never creates)")
    internal func missingIAPProduct() {
        let actions = Reconciler.plan(
            config: Self.onlyRemoveAds,
            strings: Self.enOnly,
            remote: RemoteState()
        )
        #expect(actions.isEmpty)
    }

    @Test("IAP exists, attrs match, localization absent → updateIAP unchanged-skipped + createIAPLocalization")
    internal func missingLocalizationCreates() {
        var remote = RemoteState()
        remote.iaps["com.wei18.sudoku.iap.remove_ads"] = RemoteState.IAPRemoteAttributes(
            id: "iap-1",
            referenceName: "Remove Ads v1",
            reviewNote: "Test review note.",
            familyShareable: true
        )
        let actions = Reconciler.plan(
            config: Self.onlyRemoveAds,
            strings: Self.enOnly,
            remote: remote
        )
        // Expect: iapUnchanged + createIAPLocalization(en-US).
        #expect(actions.count == 2)
        switch actions[0] {
        case .iapUnchanged(let productId, let id):
            #expect(productId == "com.wei18.sudoku.iap.remove_ads")
            #expect(id == "iap-1")
        default:
            Issue.record("expected iapUnchanged first")
        }
        switch actions[1] {
        case .createIAPLocalization(let iapId, let pid, let locale, let name, let description):
            #expect(iapId == "iap-1")
            #expect(pid == "com.wei18.sudoku.iap.remove_ads")
            #expect(locale == "en-US")
            #expect(name == "Remove Ads")
            #expect(description == "Removes all ads.")
        default:
            Issue.record("expected createIAPLocalization second")
        }
    }

    @Test("IAP + localization both present and matching → unchanged everywhere")
    internal func existingMatchUnchanged() {
        var remote = RemoteState()
        remote.iaps["com.wei18.sudoku.iap.remove_ads"] = RemoteState.IAPRemoteAttributes(
            id: "iap-1",
            referenceName: "Remove Ads v1",
            reviewNote: "Test review note.",
            familyShareable: true
        )
        remote.iapLocalizations[
            RemoteState.LocalizationKey(
                vendorId: "com.wei18.sudoku.iap.remove_ads", locale: "en-US"
            )
        ] = RemoteState.IAPLocalizationRemoteAttributes(
            id: "loc-en",
            name: "Remove Ads",
            description: "Removes all ads."
        )
        let actions = Reconciler.plan(
            config: Self.onlyRemoveAds,
            strings: Self.enOnly,
            remote: remote
        )
        #expect(actions.count == 2)
        if case .iapUnchanged = actions[0] {} else {
            Issue.record("expected iapUnchanged first")
        }
        switch actions[1] {
        case .iapLocalizationUnchanged(let pid, let locale):
            #expect(pid == "com.wei18.sudoku.iap.remove_ads")
            #expect(locale == "en-US")
        default:
            Issue.record("expected iapLocalizationUnchanged second")
        }
    }

    @Test("Localization name/description drift → updateIAPLocalization")
    internal func localizationMismatchUpdates() {
        var remote = RemoteState()
        remote.iaps["com.wei18.sudoku.iap.remove_ads"] = RemoteState.IAPRemoteAttributes(
            id: "iap-1",
            referenceName: "Remove Ads v1",
            reviewNote: "Test review note.",
            familyShareable: true
        )
        remote.iapLocalizations[
            RemoteState.LocalizationKey(
                vendorId: "com.wei18.sudoku.iap.remove_ads", locale: "en-US"
            )
        ] = RemoteState.IAPLocalizationRemoteAttributes(
            id: "loc-en",
            name: "Old Name",
            description: "Old desc."
        )
        let actions = Reconciler.plan(
            config: Self.onlyRemoveAds,
            strings: Self.enOnly,
            remote: remote
        )
        #expect(actions.count == 2)
        switch actions[1] {
        case .updateIAPLocalization(let locId, let locale, let name, let description):
            #expect(locId == "loc-en")
            #expect(locale == "en-US")
            #expect(name == "Remove Ads")
            #expect(description == "Removes all ads.")
        default:
            Issue.record("expected updateIAPLocalization for drift")
        }
    }

    @Test("Root attribute drift (reviewNote) → updateIAP, not iapUnchanged")
    internal func rootAttributeDriftUpdates() {
        var remote = RemoteState()
        remote.iaps["com.wei18.sudoku.iap.remove_ads"] = RemoteState.IAPRemoteAttributes(
            id: "iap-1",
            referenceName: "Remove Ads v1",
            reviewNote: "Outdated note.",
            familyShareable: true
        )
        let actions = Reconciler.plan(
            config: Self.onlyRemoveAds,
            strings: Self.enOnly,
            remote: remote
        )
        #expect(actions.count == 2)
        switch actions[0] {
        case .updateIAP(let id, let product):
            #expect(id == "iap-1")
            #expect(product.productId == "com.wei18.sudoku.iap.remove_ads")
        default:
            Issue.record("expected updateIAP first when remote reviewNote drifts")
        }
    }

    @Test("Root attribute drift (familyShareable) → updateIAP")
    internal func familyShareableDriftUpdates() {
        var remote = RemoteState()
        remote.iaps["com.wei18.sudoku.iap.remove_ads"] = RemoteState.IAPRemoteAttributes(
            id: "iap-1",
            referenceName: "Remove Ads v1",
            reviewNote: "Test review note.",
            familyShareable: false  // local config says true
        )
        let actions = Reconciler.plan(
            config: Self.onlyRemoveAds,
            strings: Self.enOnly,
            remote: remote
        )
        if case .updateIAP = actions.first {} else {
            Issue.record("expected updateIAP when familyShareable drifts")
        }
    }

    @Test("Nil remote attrs (first PATCH after ASC create) → updateIAP")
    internal func nilRemoteAttrsForceUpdate() {
        var remote = RemoteState()
        remote.iaps["com.wei18.sudoku.iap.remove_ads"] = RemoteState.IAPRemoteAttributes(
            id: "iap-1"
        )
        let actions = Reconciler.plan(
            config: Self.onlyRemoveAds,
            strings: Self.enOnly,
            remote: remote
        )
        if case .updateIAP = actions.first {} else {
            Issue.record("expected updateIAP when remote attrs are nil")
        }
    }

    @Test("Locale without translation skipped — only en in xcstrings emits one localization")
    internal func partialLocaleCoverage() {
        var remote = RemoteState()
        remote.iaps["com.wei18.sudoku.iap.remove_ads"] = RemoteState.IAPRemoteAttributes(
            id: "iap-1",
            referenceName: "Remove Ads v1",
            reviewNote: "Test review note.",
            familyShareable: true
        )
        let actions = Reconciler.plan(
            config: Self.onlyRemoveAds,
            strings: Self.enOnly,
            remote: remote
        )
        let locales = actions.compactMap { action -> String? in
            switch action {
            case .createIAPLocalization(_, _, let l, _, _): return l
            case .updateIAPLocalization(_, let l, _, _): return l
            case .iapLocalizationUnchanged(_, let l): return l
            default: return nil
            }
        }
        #expect(Set(locales) == ["en-US"])
    }

    @Test("Locale code mapping: zh-Hant xcstrings → zh-Hant ASC code (no region)")
    internal func localeCodeMapping() {
        let strings: XCStringsParser.LocalizedKeys = [
            "zh-Hant": [
                "iap.remove_ads.name": "移除廣告",
                "iap.remove_ads.description": "永久移除廣告。",
            ],
        ]
        var remote = RemoteState()
        remote.iaps["com.wei18.sudoku.iap.remove_ads"] = RemoteState.IAPRemoteAttributes(
            id: "iap-1",
            referenceName: "Remove Ads v1",
            reviewNote: "Test review note.",
            familyShareable: true
        )
        let actions = Reconciler.plan(
            config: Self.onlyRemoveAds,
            strings: strings,
            remote: remote
        )
        // iapUnchanged + createIAPLocalization(zh-Hant).
        #expect(actions.count == 2)
        switch actions[1] {
        case .createIAPLocalization(let iapId, _, let locale, _, _):
            #expect(iapId == "iap-1")
            #expect(locale == "zh-Hant")
        default:
            Issue.record("expected createIAPLocalization with zh-Hant locale")
        }
    }

    @Test("Root attribute drift (referenceName / ASC `name`) → updateIAP")
    internal func rootNameDriftUpdates() {
        var remote = RemoteState()
        remote.iaps["com.wei18.sudoku.iap.remove_ads"] = RemoteState.IAPRemoteAttributes(
            id: "iap-1",
            referenceName: "Stale Display Name",   // diverges from config's "Remove Ads v1"
            reviewNote: "Test review note.",
            familyShareable: true
        )
        let actions = Reconciler.plan(
            config: Self.onlyRemoveAds,
            strings: Self.enOnly,
            remote: remote
        )
        switch actions.first {
        case .updateIAP(let id, let product):
            #expect(id == "iap-1")
            #expect(product.referenceName == "Remove Ads v1")
        default:
            Issue.record("expected updateIAP when remote ASC root `name` drifts from config referenceName")
        }
    }

    @Test("Replan after apply emits all-unchanged (idempotency round-trip)")
    internal func replanAfterApplyEmitsUnchanged() {
        // remote_v1: missing localization, drifted root reviewNote.
        var remoteV1 = RemoteState()
        remoteV1.iaps["com.wei18.sudoku.iap.remove_ads"] = RemoteState.IAPRemoteAttributes(
            id: "iap-1",
            referenceName: "Stale Name",
            reviewNote: "Stale review note.",
            familyShareable: false
        )
        let firstPlan = Reconciler.plan(
            config: Self.onlyRemoveAds,
            strings: Self.enOnly,
            remote: remoteV1
        )
        // Sanity: first plan should NOT be all-unchanged.
        let firstChanged = firstPlan.contains { action in
            switch action {
            case .updateIAP, .createIAPLocalization, .updateIAPLocalization: return true
            default: return false
            }
        }
        #expect(firstChanged, "fixture should require at least one mutation")

        // remote_v2: reflects ASC state after apply (everything now matches config).
        var remoteV2 = RemoteState()
        remoteV2.iaps["com.wei18.sudoku.iap.remove_ads"] = RemoteState.IAPRemoteAttributes(
            id: "iap-1",
            referenceName: "Remove Ads v1",
            reviewNote: "Test review note.",
            familyShareable: true
        )
        remoteV2.iapLocalizations[
            RemoteState.LocalizationKey(
                vendorId: "com.wei18.sudoku.iap.remove_ads", locale: "en-US"
            )
        ] = RemoteState.IAPLocalizationRemoteAttributes(
            id: "loc-en",
            name: "Remove Ads",
            description: "Removes all ads."
        )
        let secondPlan = Reconciler.plan(
            config: Self.onlyRemoveAds,
            strings: Self.enOnly,
            remote: remoteV2
        )
        // Replan must be 100% no-op cases.
        for action in secondPlan {
            switch action {
            case .iapUnchanged, .iapLocalizationUnchanged:
                continue
            default:
                Issue.record("replan after apply emitted non-unchanged action: \(action)")
            }
        }
        #expect(!secondPlan.isEmpty)
    }
}
