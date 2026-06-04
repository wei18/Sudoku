// ReconcilerMetadataTests — pure-function tests on the app-listing metadata
// reconciler (issue #310). Mirrors ReconcilerIAPTests' coverage matrix:
//   - missing localization → create (appInfo + version)
//   - existing match       → unchanged
//   - existing mismatch    → update
//   - category drift       → updateCategories; match → categoriesUnchanged
//   - no appInfo/version   → no localization actions emitted
//   - idempotency round-trip (replan after apply = all-unchanged)

internal import Foundation
internal import Testing
@testable import ASCRegister

@Suite("Reconciler Metadata")
internal struct ReconcilerMetadataTests {

    // MARK: - Fixtures

    private static func listing(
        locale: String = "en-US",
        name: String? = "Sudoku",
        subtitle: String? = "Calm logic",
        privacyPolicyUrl: String? = "https://example.com/privacy",
        description: String? = "Long desc.",
        keywords: String? = "sudoku,puzzle",
        promotionalText: String? = "Promo.",
        whatsNew: String? = "v1.",
        marketingUrl: String? = nil,
        supportUrl: String? = "https://example.com/support"
    ) -> ListingLocale {
        ListingLocale(
            locale: locale, name: name, subtitle: subtitle,
            privacyPolicyUrl: privacyPolicyUrl, description: description,
            keywords: keywords, promotionalText: promotionalText,
            whatsNew: whatsNew, marketingUrl: marketingUrl, supportUrl: supportUrl
        )
    }

    private static func config(
        listings: [ListingLocale],
        primary: String? = "Games",
        primarySub: String? = "Puzzle",
        secondary: String? = "Games",
        secondarySub: String? = "Family"
    ) -> MetadataConfig {
        let cats = AppMeta.Categories(
            primary: primary, primaryFirstSub: primarySub, primarySecondSub: nil,
            secondary: secondary, secondaryFirstSub: secondarySub, secondarySecondSub: nil
        )
        return MetadataConfig(
            appMeta: AppMeta(app: "sudoku", appleId: "1", copyright: "2026 Wei18", categories: cats),
            listings: listings
        )
    }

    // MARK: - Tests

    @Test("No appInfo/version in remote → no localization actions, categories unchanged")
    internal func emptyRemoteEmitsNothing() {
        let actions = MetadataReconciler.plan(
            config: Self.config(listings: [Self.listing()]),
            remote: MetadataRemoteState()
        )
        // Only the categories action (categoriesUnchanged, since no appInfoId).
        #expect(actions == [.categoriesUnchanged])
    }

    @Test("Missing localizations → createAppInfoLoc + createVersionLoc + updateCategories")
    internal func missingLocalizationsCreate() {
        let remote = MetadataRemoteState(appInfoId: "ai-1", versionId: "v-1")
        let actions = MetadataReconciler.plan(
            config: Self.config(listings: [Self.listing()]),
            remote: remote
        )
        #expect(actions.contains { if case .createAppInfoLoc(let id, let loc, _) = $0 { return id == "ai-1" && loc == "en-US" } else { return false } })
        #expect(actions.contains { if case .createVersionLoc(let id, let loc, _) = $0 { return id == "v-1" && loc == "en-US" } else { return false } })
        // Categories: remote has nil category ids, config has GAMES_PUZZLE → drift.
        #expect(actions.contains { if case .updateCategories(let id, let primary, let secondary) = $0 {
            return id == "ai-1" && primary == "GAMES_PUZZLE" && secondary == "GAMES_FAMILY"
        } else { return false } })
    }

    @Test("All fields match remote → unchanged everywhere")
    internal func allMatchUnchanged() {
        let listing = Self.listing()
        var remote = MetadataRemoteState(appInfoId: "ai-1", versionId: "v-1")
        remote.appInfoLocalizations["en-US"] = MetadataRemoteState.AppInfoLocRemote(
            id: "ail-en", name: listing.name, subtitle: listing.subtitle,
            privacyPolicyUrl: listing.privacyPolicyUrl
        )
        remote.versionLocalizations["en-US"] = MetadataRemoteState.VersionLocRemote(
            id: "vl-en", description: listing.description, keywords: listing.keywords,
            promotionalText: listing.promotionalText, whatsNew: listing.whatsNew,
            marketingUrl: listing.marketingUrl, supportUrl: listing.supportUrl
        )
        remote.primaryCategoryId = "GAMES_PUZZLE"
        remote.secondaryCategoryId = "GAMES_FAMILY"

        let actions = MetadataReconciler.plan(config: Self.config(listings: [listing]), remote: remote)
        #expect(actions == [
            .appInfoLocUnchanged(locale: "en-US"),
            .versionLocUnchanged(locale: "en-US"),
            .categoriesUnchanged,
        ])
    }

    @Test("appInfo field drift (subtitle) → updateAppInfoLoc")
    internal func appInfoDriftUpdates() {
        let listing = Self.listing()
        var remote = MetadataRemoteState(appInfoId: "ai-1", versionId: "v-1")
        remote.appInfoLocalizations["en-US"] = MetadataRemoteState.AppInfoLocRemote(
            id: "ail-en", name: listing.name, subtitle: "STALE",
            privacyPolicyUrl: listing.privacyPolicyUrl
        )
        let actions = MetadataReconciler.plan(config: Self.config(listings: [listing]), remote: remote)
        #expect(actions.contains { if case .updateAppInfoLoc(let id, let loc, _) = $0 { return id == "ail-en" && loc == "en-US" } else { return false } })
    }

    @Test("version field drift (keywords) → updateVersionLoc")
    internal func versionDriftUpdates() {
        let listing = Self.listing()
        var remote = MetadataRemoteState(appInfoId: "ai-1", versionId: "v-1")
        remote.versionLocalizations["en-US"] = MetadataRemoteState.VersionLocRemote(
            id: "vl-en", description: listing.description, keywords: "STALE",
            promotionalText: listing.promotionalText, whatsNew: listing.whatsNew,
            marketingUrl: listing.marketingUrl, supportUrl: listing.supportUrl
        )
        let actions = MetadataReconciler.plan(config: Self.config(listings: [listing]), remote: remote)
        #expect(actions.contains { if case .updateVersionLoc(let id, let loc, _) = $0 { return id == "vl-en" && loc == "en-US" } else { return false } })
    }

    @Test("Category match → categoriesUnchanged")
    internal func categoryMatchUnchanged() {
        var remote = MetadataRemoteState(appInfoId: "ai-1", versionId: "v-1")
        remote.primaryCategoryId = "GAMES_PUZZLE"
        remote.secondaryCategoryId = "GAMES_FAMILY"
        let actions = MetadataReconciler.plan(config: Self.config(listings: []), remote: remote)
        #expect(actions == [.categoriesUnchanged])
    }

    @Test("Listing with no appInfo-scoped fields skips appInfo loc but still emits version loc")
    internal func partialFieldsScopeSplit() {
        let listing = Self.listing(name: nil, subtitle: nil, privacyPolicyUrl: nil)
        let remote = MetadataRemoteState(appInfoId: "ai-1", versionId: "v-1")
        let actions = MetadataReconciler.plan(config: Self.config(listings: [listing]), remote: remote)
        #expect(!actions.contains { if case .createAppInfoLoc = $0 { return true } else { return false } })
        #expect(actions.contains { if case .createVersionLoc = $0 { return true } else { return false } })
    }

    @Test("Replan after apply emits all-unchanged (idempotency)")
    internal func idempotencyRoundTrip() {
        let listing = Self.listing()
        let cfg = Self.config(listings: [listing])

        // remote_v1: nothing exists → all create + category update.
        let firstPlan = MetadataReconciler.plan(
            config: cfg, remote: MetadataRemoteState(appInfoId: "ai-1", versionId: "v-1")
        )
        let firstChanged = firstPlan.contains {
            switch $0 {
            case .createAppInfoLoc, .createVersionLoc, .updateCategories: return true
            default: return false
            }
        }
        #expect(firstChanged)

        // remote_v2: post-apply state mirrors config exactly.
        var remoteV2 = MetadataRemoteState(appInfoId: "ai-1", versionId: "v-1")
        remoteV2.appInfoLocalizations["en-US"] = MetadataRemoteState.AppInfoLocRemote(
            id: "ail-en", name: listing.name, subtitle: listing.subtitle,
            privacyPolicyUrl: listing.privacyPolicyUrl
        )
        remoteV2.versionLocalizations["en-US"] = MetadataRemoteState.VersionLocRemote(
            id: "vl-en", description: listing.description, keywords: listing.keywords,
            promotionalText: listing.promotionalText, whatsNew: listing.whatsNew,
            marketingUrl: listing.marketingUrl, supportUrl: listing.supportUrl
        )
        remoteV2.primaryCategoryId = "GAMES_PUZZLE"
        remoteV2.secondaryCategoryId = "GAMES_FAMILY"

        let secondPlan = MetadataReconciler.plan(config: cfg, remote: remoteV2)
        for action in secondPlan {
            switch action {
            case .appInfoLocUnchanged, .versionLocUnchanged, .categoriesUnchanged:
                continue
            default:
                Issue.record("replan emitted non-unchanged action: \(action)")
            }
        }
        #expect(!secondPlan.isEmpty)
    }

    // MARK: - Category id mapping

    @Test("ascCategoryId maps genre + sub to SCREAMING_SNAKE token")
    internal func categoryIdMapping() {
        #expect(MetadataConfig.ascCategoryId(genre: "Games", sub: "Puzzle") == "GAMES_PUZZLE")
        #expect(MetadataConfig.ascCategoryId(genre: "Games", sub: "Board") == "GAMES_BOARD")
        #expect(MetadataConfig.ascCategoryId(genre: "Games", sub: "Family") == "GAMES_FAMILY")
        #expect(MetadataConfig.ascCategoryId(genre: "Games", sub: nil) == "GAMES")
        #expect(MetadataConfig.ascCategoryId(genre: "", sub: nil) == nil)
        // Multi-word sub collapses spaces to underscore.
        #expect(MetadataConfig.ascCategoryId(genre: "Games", sub: "Role Playing") == "GAMES_ROLE_PLAYING")
    }
}
