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

    // appInfos category relationships
    case updateCategories(appInfoId: String, primaryId: String?, secondaryId: String?)
    case categoriesUnchanged
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

    /// Current primary / secondary category relationship ids on the appInfo.
    internal var primaryCategoryId: String?
    internal var secondaryCategoryId: String?

    internal init(
        appInfoId: String? = nil,
        versionId: String? = nil,
        appInfoLocalizations: [String: AppInfoLocRemote] = [:],
        versionLocalizations: [String: VersionLocRemote] = [:],
        primaryCategoryId: String? = nil,
        secondaryCategoryId: String? = nil
    ) {
        self.appInfoId = appInfoId
        self.versionId = versionId
        self.appInfoLocalizations = appInfoLocalizations
        self.versionLocalizations = versionLocalizations
        self.primaryCategoryId = primaryCategoryId
        self.secondaryCategoryId = secondaryCategoryId
    }

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
        for listing in config.listings {
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

    // MARK: - categories

    private static func planCategories(
        config: MetadataConfig,
        remote: MetadataRemoteState
    ) -> MetadataAction {
        guard let appInfoId = remote.appInfoId else { return .categoriesUnchanged }
        let cats = config.appMeta.categories
        // The chosen relationship target is the most-specific id available:
        // the first sub-category if present, else the genre.
        let primaryId = MetadataConfig.ascCategoryId(
            genre: cats.primary ?? "",
            sub: cats.primaryFirstSub
        )
        let secondaryId = MetadataConfig.ascCategoryId(
            genre: cats.secondary ?? "",
            sub: cats.secondaryFirstSub
        )
        if remote.primaryCategoryId == primaryId, remote.secondaryCategoryId == secondaryId {
            return .categoriesUnchanged
        }
        return .updateCategories(appInfoId: appInfoId, primaryId: primaryId, secondaryId: secondaryId)
    }
}
