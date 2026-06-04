// Reconciler+Metadata — diff desired app-listing metadata (MetadataConfig)
// against observed ASC state and emit an ordered, idempotent action list
// (issue #310). Mirrors the IAP reconciler's create-vs-update-vs-unchanged
// per-field shape.
//
// A single `listing.yaml` locale fans out to TWO ASC localization resources
// (plan §2): `appInfoLocalizations` (name / subtitle / privacyPolicyUrl) and
// `appStoreVersionLocalizations` (description / keywords / promotionalText /
// whatsNew / marketingUrl / supportUrl). Plus a one-time category
// relationship PATCH on `appInfos`. The reconciler emits one action per
// (locale × resource) plus one category action.
//
// Pure function: `(config, remote) → [MetadataAction]`. No I/O. The unchanged
// branches give idempotency — a second `apply` with no source change yields
// an all-`*Unchanged` plan.

import Foundation

internal enum MetadataAction: Sendable, Equatable {

    // appInfoLocalizations (name / subtitle / privacyPolicyUrl)
    case createAppInfoLoc(appInfoId: String, locale: String, ListingLocale)
    case updateAppInfoLoc(localizationId: String, locale: String, ListingLocale)
    case appInfoLocUnchanged(locale: String)

    // appStoreVersionLocalizations (description / keywords / ...)
    case createVersionLoc(versionId: String, locale: String, ListingLocale)
    case updateVersionLoc(localizationId: String, locale: String, ListingLocale)
    case versionLocUnchanged(locale: String)

    // appInfos category relationships. ASC `appInfos` exposes SIX category
    // relationship slots: the two top-level genres plus up to two
    // sub-categories each. The genre token (`GAMES`) goes in
    // `primary/secondaryCategory`; each sub (`GAMES_PUZZLE`, …) in its own
    // `…SubcategoryOne/Two` slot. Sending a sub token as the primary genre is
    // what triggered the live `409 ENTITY_ERROR.RELATIONSHIP.INVALID`
    // (issue #310). A `nil` slot is omitted from the PATCH body by the client.
    case updateCategories(appInfoId: String, MetadataCategoryIds)
    case categoriesUnchanged
}

/// The resolved ASC `appCategories` id tokens for all six `appInfos` category
/// relationship slots. `nil` means "no value configured" → the client omits
/// that relationship from the PATCH.
internal struct MetadataCategoryIds: Sendable, Equatable {
    internal let primary: String?
    internal let primarySubOne: String?
    internal let primarySubTwo: String?
    internal let secondary: String?
    internal let secondarySubOne: String?
    internal let secondarySubTwo: String?

    internal init(
        primary: String? = nil,
        primarySubOne: String? = nil,
        primarySubTwo: String? = nil,
        secondary: String? = nil,
        secondarySubOne: String? = nil,
        secondarySubTwo: String? = nil
    ) {
        self.primary = primary
        self.primarySubOne = primarySubOne
        self.primarySubTwo = primarySubTwo
        self.secondary = secondary
        self.secondarySubOne = secondarySubOne
        self.secondarySubTwo = secondarySubTwo
    }
}

/// Observed remote metadata state for one app. Populated by the `metadata`
/// command from the live GETs before reconcile.
internal struct MetadataRemoteState: Sendable, Equatable {
    /// The editable `appInfo` resource id, or `nil` if none found.
    internal var appInfoId: String?
    /// The editable `appStoreVersion` resource id, or `nil`.
    internal var versionId: String?

    /// ASC-locale → existing `appInfoLocalizations` snapshot.
    internal var appInfoLocalizations: [String: AppInfoLocRemote]
    /// ASC-locale → existing `appStoreVersionLocalizations` snapshot.
    internal var versionLocalizations: [String: VersionLocRemote]

    /// Current category relationship ids on the appInfo — all six slots,
    /// side-loaded so drift compares correctly (issue #310). A slot with no
    /// value on ASC is `nil`.
    internal var categoryIds: MetadataCategoryIds

    /// Whether the app has at least one RELEASED / ready-for-sale version in
    /// ASC. `false` means the chosen `appStoreVersion` is a first submission
    /// (e.g. 1.0, PREPARE_FOR_SUBMISSION, no released predecessor): ASC then
    /// FORBIDS setting `whatsNew` (release notes) — a live apply hit
    /// `409 STATE_ERROR — Attribute 'whatsNew' cannot be edited at this time`
    /// (issue #310). When `false` the reconciler omits `whatsNew` from version
    /// create/update actions; when `true` it sends `whatsNew` as before.
    ///
    /// Derived from `appStoreState` across the app's fetched versions (no new
    /// network call). Defaults `true` to preserve the legacy "send whatsNew"
    /// behavior for callers that do not yet populate it.
    internal var hasReleasedVersion: Bool

    internal init(
        appInfoId: String? = nil,
        versionId: String? = nil,
        appInfoLocalizations: [String: AppInfoLocRemote] = [:],
        versionLocalizations: [String: VersionLocRemote] = [:],
        categoryIds: MetadataCategoryIds = MetadataCategoryIds(),
        hasReleasedVersion: Bool = true
    ) {
        self.appInfoId = appInfoId
        self.versionId = versionId
        self.appInfoLocalizations = appInfoLocalizations
        self.versionLocalizations = versionLocalizations
        self.categoryIds = categoryIds
        self.hasReleasedVersion = hasReleasedVersion
    }

    /// ASC `appStoreState` values that mean a version is live / has been
    /// released to the store — the presence of any one means this is NOT a
    /// first submission, so `whatsNew` is editable. Used by the `metadata`
    /// command to compute `hasReleasedVersion` from the fetched version list.
    internal static let releasedAppStoreStates: Set<String> = [
        "READY_FOR_SALE",
        "PENDING_APPLE_RELEASE",
        "PENDING_DEVELOPER_RELEASE",
        "PROCESSING_FOR_APP_STORE",
        "REPLACED_WITH_NEW_VERSION",
        "REMOVED_FROM_SALE",
    ]

    internal struct AppInfoLocRemote: Sendable, Equatable {
        internal let id: String
        internal let name: String?
        internal let subtitle: String?
        internal let privacyPolicyUrl: String?
        internal init(id: String, name: String? = nil, subtitle: String? = nil, privacyPolicyUrl: String? = nil) {
            self.id = id
            self.name = name
            self.subtitle = subtitle
            self.privacyPolicyUrl = privacyPolicyUrl
        }
    }

    internal struct VersionLocRemote: Sendable, Equatable {
        internal let id: String
        internal let description: String?
        internal let keywords: String?
        internal let promotionalText: String?
        internal let whatsNew: String?
        internal let marketingUrl: String?
        internal let supportUrl: String?
        internal init(
            id: String,
            description: String? = nil,
            keywords: String? = nil,
            promotionalText: String? = nil,
            whatsNew: String? = nil,
            marketingUrl: String? = nil,
            supportUrl: String? = nil
        ) {
            self.id = id
            self.description = description
            self.keywords = keywords
            self.promotionalText = promotionalText
            self.whatsNew = whatsNew
            self.marketingUrl = marketingUrl
            self.supportUrl = supportUrl
        }
    }
}

internal enum MetadataReconciler {

    /// Diff `config` against `remote`, emit the ordered action list.
    internal static func plan(
        config: MetadataConfig,
        remote: MetadataRemoteState
    ) -> [MetadataAction] {
        var actions: [MetadataAction] = []
        actions.append(contentsOf: planAppInfoLocalizations(config: config, remote: remote))
        actions.append(contentsOf: planVersionLocalizations(config: config, remote: remote))
        actions.append(planCategories(config: config, remote: remote))
        return actions
    }

    // MARK: - appInfoLocalizations

    private static func planAppInfoLocalizations(
        config: MetadataConfig,
        remote: MetadataRemoteState
    ) -> [MetadataAction] {
        guard let appInfoId = remote.appInfoId else { return [] }
        var out: [MetadataAction] = []
        for listing in config.listings {
            // Only emit if the listing carries at least one appInfo-scoped field.
            guard listing.name != nil || listing.subtitle != nil || listing.privacyPolicyUrl != nil else {
                continue
            }
            if let existing = remote.appInfoLocalizations[listing.locale] {
                let drift = existing.name != listing.name
                    || existing.subtitle != listing.subtitle
                    || existing.privacyPolicyUrl != listing.privacyPolicyUrl
                if drift {
                    out.append(.updateAppInfoLoc(localizationId: existing.id, locale: listing.locale, listing))
                } else {
                    out.append(.appInfoLocUnchanged(locale: listing.locale))
                }
            } else {
                out.append(.createAppInfoLoc(appInfoId: appInfoId, locale: listing.locale, listing))
            }
        }
        return out
    }

    // MARK: - appStoreVersionLocalizations

    private static func planVersionLocalizations(
        config: MetadataConfig,
        remote: MetadataRemoteState
    ) -> [MetadataAction] {
        guard let versionId = remote.versionId else { return [] }
        var out: [MetadataAction] = []
        for rawListing in config.listings {
            // On a first submission (no released predecessor) ASC forbids
            // `whatsNew` (`409 STATE_ERROR ... cannot be edited at this time`,
            // issue #310). Drop it from BOTH the drift comparison and the
            // emitted action so apply never sends it; keep sending it once a
            // released version exists.
            let listing = remote.hasReleasedVersion ? rawListing : Self.droppingWhatsNew(rawListing)
            guard listing.description != nil || listing.keywords != nil
                || listing.promotionalText != nil || listing.whatsNew != nil
                || listing.marketingUrl != nil || listing.supportUrl != nil
            else { continue }
            if let existing = remote.versionLocalizations[listing.locale] {
                let drift = existing.description != listing.description
                    || existing.keywords != listing.keywords
                    || existing.promotionalText != listing.promotionalText
                    || existing.whatsNew != listing.whatsNew
                    || existing.marketingUrl != listing.marketingUrl
                    || existing.supportUrl != listing.supportUrl
                if drift {
                    out.append(.updateVersionLoc(localizationId: existing.id, locale: listing.locale, listing))
                } else {
                    out.append(.versionLocUnchanged(locale: listing.locale))
                }
            } else {
                out.append(.createVersionLoc(versionId: versionId, locale: listing.locale, listing))
            }
        }
        return out
    }

    /// Return `listing` with `whatsNew` forced to `nil` (first-version rule).
    /// All other fields are preserved.
    private static func droppingWhatsNew(_ listing: ListingLocale) -> ListingLocale {
        ListingLocale(
            locale: listing.locale,
            name: listing.name,
            subtitle: listing.subtitle,
            privacyPolicyUrl: listing.privacyPolicyUrl,
            description: listing.description,
            keywords: listing.keywords,
            promotionalText: listing.promotionalText,
            whatsNew: nil,
            marketingUrl: listing.marketingUrl,
            supportUrl: listing.supportUrl
        )
    }

    // MARK: - categories

    private static func planCategories(
        config: MetadataConfig,
        remote: MetadataRemoteState
    ) -> MetadataAction {
        guard let appInfoId = remote.appInfoId else { return .categoriesUnchanged }
        let cats = config.appMeta.categories
        // ASC requires the top-level GENRE in `primary/secondaryCategory`
        // (e.g. `GAMES`) and each sub-category in its own
        // `…SubcategoryOne/Two` slot (e.g. `GAMES_PUZZLE`). Sending a sub as
        // the primary genre was the live `409 RELATIONSHIP.INVALID` cause
        // (issue #310). A genre maps via `ascCategoryId(sub: nil)`; a sub via
        // `ascCategoryId(genre:sub:)`.
        let desired = MetadataCategoryIds(
            primary: MetadataConfig.ascCategoryId(genre: cats.primary ?? "", sub: nil),
            primarySubOne: subId(genre: cats.primary, sub: cats.primaryFirstSub),
            primarySubTwo: subId(genre: cats.primary, sub: cats.primarySecondSub),
            secondary: MetadataConfig.ascCategoryId(genre: cats.secondary ?? "", sub: nil),
            secondarySubOne: subId(genre: cats.secondary, sub: cats.secondaryFirstSub),
            secondarySubTwo: subId(genre: cats.secondary, sub: cats.secondarySecondSub)
        )
        if remote.categoryIds == desired {
            return .categoriesUnchanged
        }
        return .updateCategories(appInfoId: appInfoId, desired)
    }

    /// Resolve a sub-category id token from its genre + sub label, or `nil`
    /// when either is absent (so the slot is omitted from the PATCH).
    private static func subId(genre: String?, sub: String?) -> String? {
        guard let genre, let sub, !sub.isEmpty else { return nil }
        return MetadataConfig.ascCategoryId(genre: genre, sub: sub)
    }
}
