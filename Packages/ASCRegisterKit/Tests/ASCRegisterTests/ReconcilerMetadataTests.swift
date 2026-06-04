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
        primarySecondSub: String? = "Board",
        secondary: String? = "Games",
        secondarySub: String? = "Family",
        secondarySecondSub: String? = nil
    ) -> MetadataConfig {
        let cats = AppMeta.Categories(
            primary: primary, primaryFirstSub: primarySub, primarySecondSub: primarySecondSub,
            secondary: secondary, secondaryFirstSub: secondarySub, secondarySecondSub: secondarySecondSub
        )
        return MetadataConfig(
            appMeta: AppMeta(app: "sudoku", appleId: "1", copyright: "2026 Wei18", categories: cats),
            listings: listings
        )
    }

    /// The six-slot ids the default `config()` resolves to: genre `GAMES` in
    /// each `…Category` slot, subs in their `…Sub` slots.
    private static let expectedCategoryIds = MetadataCategoryIds(
        primary: "GAMES", primarySubOne: "GAMES_PUZZLE", primarySubTwo: "GAMES_BOARD",
        secondary: "GAMES", secondarySubOne: "GAMES_FAMILY", secondarySubTwo: nil
    )

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
        // Categories: remote has nil category ids → drift. The genre maps to
        // `GAMES` (NOT the sub `GAMES_PUZZLE` — that was the live 409 bug,
        // issue #310); subs land in their own slots.
        #expect(actions.contains { if case .updateCategories(let id, let cats) = $0 {
            return id == "ai-1" && cats == Self.expectedCategoryIds
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
        remote.categoryIds = Self.expectedCategoryIds

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

    @Test("version-loc differing only by a trailing block-scalar newline → unchanged (#333)")
    internal func versionTrailingNewlineConverges() {
        // The desired config carries the YAML `|` block-scalar terminator on the
        // multi-line fields; ASC stores+returns them with the trailing newline
        // dropped (issue #333 — that mismatch made every replan emit UPDATE).
        let listing = Self.listing(
            description: "Long desc.\n",
            promotionalText: "Promo.\n",
            whatsNew: "v1.\n"
        )
        var remote = MetadataRemoteState(appInfoId: "ai-1", versionId: "v-1")
        remote.appInfoLocalizations["en-US"] = MetadataRemoteState.AppInfoLocRemote(
            id: "ail-en", name: listing.name, subtitle: listing.subtitle,
            privacyPolicyUrl: listing.privacyPolicyUrl
        )
        // Remote mirrors what ASC actually returns: same content, no trailing newline.
        remote.versionLocalizations["en-US"] = MetadataRemoteState.VersionLocRemote(
            id: "vl-en", description: "Long desc.", keywords: listing.keywords,
            promotionalText: "Promo.", whatsNew: "v1.",
            marketingUrl: listing.marketingUrl, supportUrl: listing.supportUrl
        )
        remote.categoryIds = Self.expectedCategoryIds

        let actions = MetadataReconciler.plan(config: Self.config(listings: [listing]), remote: remote)
        #expect(actions.contains { if case .versionLocUnchanged(let loc) = $0 { return loc == "en-US" } else { return false } })
        #expect(!actions.contains { if case .updateVersionLoc = $0 { return true } else { return false } })
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

    @Test("Category match (all six slots) → categoriesUnchanged")
    internal func categoryMatchUnchanged() {
        var remote = MetadataRemoteState(appInfoId: "ai-1", versionId: "v-1")
        remote.categoryIds = Self.expectedCategoryIds
        let actions = MetadataReconciler.plan(config: Self.config(listings: []), remote: remote)
        #expect(actions == [.categoriesUnchanged])
    }

    @Test("Genre maps to GAMES not the sub token (live 409 RELATIONSHIP.INVALID fix)")
    internal func categoryGenreMapsToGamesNotSub() {
        let remote = MetadataRemoteState(appInfoId: "ai-1", versionId: "v-1")
        let actions = MetadataReconciler.plan(config: Self.config(listings: []), remote: remote)
        guard case .updateCategories(_, let cats) = actions.first else {
            Issue.record("expected updateCategories"); return
        }
        // primaryCategory must be the GENRE, never the sub.
        #expect(cats.primary == "GAMES")
        #expect(cats.primary != "GAMES_PUZZLE")
        #expect(cats.primarySubOne == "GAMES_PUZZLE")
        #expect(cats.primarySubTwo == "GAMES_BOARD")
        #expect(cats.secondary == "GAMES")
        #expect(cats.secondarySubOne == "GAMES_FAMILY")
    }

    @Test("Null second-sub slot is omitted (nil), not sent")
    internal func categoryNullSlotOmitted() {
        let remote = MetadataRemoteState(appInfoId: "ai-1", versionId: "v-1")
        // secondary has no second sub in the default config.
        let actions = MetadataReconciler.plan(config: Self.config(listings: []), remote: remote)
        guard case .updateCategories(_, let cats) = actions.first else {
            Issue.record("expected updateCategories"); return
        }
        #expect(cats.secondarySubTwo == nil)
    }

    @Test("Sub-only drift (primarySubTwo differs) → updateCategories")
    internal func categorySubDriftUpdates() {
        var remote = MetadataRemoteState(appInfoId: "ai-1", versionId: "v-1")
        // Genres + first subs match, but primarySubTwo is stale → must drift.
        remote.categoryIds = MetadataCategoryIds(
            primary: "GAMES", primarySubOne: "GAMES_PUZZLE", primarySubTwo: "GAMES_CARD",
            secondary: "GAMES", secondarySubOne: "GAMES_FAMILY", secondarySubTwo: nil
        )
        let actions = MetadataReconciler.plan(config: Self.config(listings: []), remote: remote)
        #expect(actions == [.updateCategories(appInfoId: "ai-1", Self.expectedCategoryIds)])
    }

    @Test("Minesweeper category layout maps to the right six slots")
    internal func minesweeperCategoryLayout() {
        // MS: primary Games/Board/Puzzle, secondary Games/Strategy.
        let cfg = Self.config(
            listings: [],
            primary: "Games", primarySub: "Board", primarySecondSub: "Puzzle",
            secondary: "Games", secondarySub: "Strategy", secondarySecondSub: nil
        )
        let remote = MetadataRemoteState(appInfoId: "ai-1", versionId: "v-1")
        guard case .updateCategories(_, let cats) = MetadataReconciler.plan(config: cfg, remote: remote).first else {
            Issue.record("expected updateCategories"); return
        }
        #expect(cats == MetadataCategoryIds(
            primary: "GAMES", primarySubOne: "GAMES_BOARD", primarySubTwo: "GAMES_PUZZLE",
            secondary: "GAMES", secondarySubOne: "GAMES_STRATEGY", secondarySubTwo: nil
        ))
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
        remoteV2.categoryIds = Self.expectedCategoryIds

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
