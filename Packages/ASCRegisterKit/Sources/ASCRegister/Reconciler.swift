// Reconciler — compare desired Config against observed ASC state and
// emit an ordered, idempotent action list.
//
// Order matters:
//   1. Leaderboards: create-or-update each → then per-locale localizations.
//   2. Achievements: create-or-update each → then per-locale localizations.
//
// Leaderboards/achievements must exist before their localizations can
// reference them, so the two phases are sequential. Within a phase,
// order matches `Config.leaderboards` / `Config.achievements` (stable).

import Foundation

internal enum Action: Sendable, Equatable {

    // Leaderboard-level
    case createLeaderboard(LeaderboardConfig)
    case updateLeaderboard(existingId: String, LeaderboardConfig)
    case leaderboardUnchanged(id: String)

    // Leaderboard localization
    case createLeaderboardLocalization(leaderboardVendorId: String, locale: String, title: String)
    case updateLeaderboardLocalization(localizationId: String, locale: String, title: String)
    case leaderboardLocalizationUnchanged(leaderboardVendorId: String, locale: String)

    // Achievement-level
    case createAchievement(AchievementConfig)
    case updateAchievement(existingId: String, AchievementConfig)
    case achievementUnchanged(id: String)

    // Achievement localization
    case createAchievementLocalization(
        achievementVendorId: String,
        locale: String,
        title: String,
        description: String,
        unearnedDescription: String
    )
    case updateAchievementLocalization(
        localizationId: String,
        locale: String,
        title: String,
        description: String,
        unearnedDescription: String
    )
    case achievementLocalizationUnchanged(achievementVendorId: String, locale: String)

    // IAP-level (Phase 1.a — PATCH only; we never CREATE IAP products,
    // the user already created them in ASC web UI per issue #200).
    case updateIAP(existingId: String, IAPProduct)
    case iapUnchanged(productId: String, id: String)

    // IAP localization
    case createIAPLocalization(
        iapId: String,
        iapProductId: String,
        locale: String,
        name: String,
        description: String
    )
    case updateIAPLocalization(
        localizationId: String,
        locale: String,
        name: String,
        description: String
    )
    case iapLocalizationUnchanged(iapProductId: String, locale: String)
}

/// Observed remote state — what's already in ASC. Indexed by vendor ID
/// (the stable, design-supplied identifier).
internal struct RemoteState: Sendable, Equatable {
    /// vendorId → existing ASC resource id
    internal var leaderboards: [String: String]
    /// (leaderboardVendorId, locale) → existing localization resource id
    internal var leaderboardLocalizations: [LocalizationKey: String]
    /// vendorId → existing ASC resource id
    internal var achievements: [String: String]
    /// (achievementVendorId, locale) → existing localization resource id
    internal var achievementLocalizations: [LocalizationKey: String]

    /// productId → existing ASC `inAppPurchases` id (Phase 1.a, issue #200).
    internal var iaps: [String: IAPRemoteAttributes]
    /// (iapProductId, ascLocale) → existing localization id + current attrs.
    internal var iapLocalizations: [LocalizationKey: IAPLocalizationRemoteAttributes]

    internal init(
        leaderboards: [String: String] = [:],
        leaderboardLocalizations: [LocalizationKey: String] = [:],
        achievements: [String: String] = [:],
        achievementLocalizations: [LocalizationKey: String] = [:],
        iaps: [String: IAPRemoteAttributes] = [:],
        iapLocalizations: [LocalizationKey: IAPLocalizationRemoteAttributes] = [:]
    ) {
        self.leaderboards = leaderboards
        self.leaderboardLocalizations = leaderboardLocalizations
        self.achievements = achievements
        self.achievementLocalizations = achievementLocalizations
        self.iaps = iaps
        self.iapLocalizations = iapLocalizations
    }

    internal struct LocalizationKey: Sendable, Hashable {
        internal let vendorId: String
        internal let locale: String
    }

    /// Snapshot of the mutable root-attribute subset on an ASC
    /// `inAppPurchases` resource — enough to decide `updateIAP` vs
    /// `iapUnchanged` without re-fetching. `name` here is the ASC
    /// `referenceName` (internal label), distinct from the per-locale
    /// localization `name`.
    internal struct IAPRemoteAttributes: Sendable, Equatable {
        internal let id: String
        internal let referenceName: String?
        internal let reviewNote: String?
        internal let familyShareable: Bool?

        internal init(
            id: String,
            referenceName: String? = nil,
            reviewNote: String? = nil,
            familyShareable: Bool? = nil
        ) {
            self.id = id
            self.referenceName = referenceName
            self.reviewNote = reviewNote
            self.familyShareable = familyShareable
        }
    }

    /// Snapshot of an ASC `inAppPurchaseLocalizations` resource for diffing.
    internal struct IAPLocalizationRemoteAttributes: Sendable, Equatable {
        internal let id: String
        internal let name: String?
        internal let description: String?

        internal init(id: String, name: String? = nil, description: String? = nil) {
            self.id = id
            self.name = name
            self.description = description
        }
    }
}

internal struct Reconciler: Sendable {

    /// Locales we attempt to push. Subset of the App's 7 locales — those
    /// without a translated string in xcstrings are simply skipped per
    /// locale per resource (idempotent: re-running after translation
    /// fills in the gaps).
    internal static let targetLocales = ["en", "zh-Hant", "ja", "zh-Hans", "es", "th", "ko"]

    internal static func plan(
        config: ConfigSnapshot,
        strings: XCStringsParser.LocalizedKeys,
        remote: RemoteState
    ) -> [Action] {
        var actions: [Action] = []
        actions.append(contentsOf: planLeaderboards(config: config, strings: strings, remote: remote))
        actions.append(contentsOf: planAchievements(config: config, strings: strings, remote: remote))
        actions.append(contentsOf: planIAPs(config: config, strings: strings, remote: remote))
        return actions
    }

    // MARK: - Leaderboards

    private static func planLeaderboards(
        config: ConfigSnapshot,
        strings: XCStringsParser.LocalizedKeys,
        remote: RemoteState
    ) -> [Action] {
        var out: [Action] = []
        // swiftlint:disable:next identifier_name
        for lb in config.leaderboards {
            if let existingId = remote.leaderboards[lb.id] {
                // We don't introspect attributes — treat existence as unchanged.
                // Real-world updates would compare scoreFormat / sortOrder; for
                // v1 those are configured-once and reconciler only fixes new IDs.
                out.append(.leaderboardUnchanged(id: existingId))
            } else {
                out.append(.createLeaderboard(lb))
            }

            for locale in targetLocales {
                guard let title = XCStringsParser.leaderboardTitle(
                    in: strings, locale: locale, key: lb.titleKey
                ) else { continue }
                // ASC requires its own locale codes (issue #31, #37).
                // xcstrings uses the bare form (`"en"`, `"zh-Hant"`); map
                // via `Config.ascLocaleCode` (e.g. `"en"` → `"en-US"`;
                // `"zh-Hant"` stays `"zh-Hant"` for Game Center) before
                // lookup + emission so the POST body and the RemoteState
                // key are in the same space ASC returns from GET.
                let ascLocale = Config.ascLocaleCode(for: locale)
                let key = RemoteState.LocalizationKey(vendorId: lb.id, locale: ascLocale)
                if let locId = remote.leaderboardLocalizations[key] {
                    // Always emit an update — title may have changed. In a
                    // future revision we could store the last-pushed value
                    // for true diffing.
                    out.append(.updateLeaderboardLocalization(
                        localizationId: locId, locale: ascLocale, title: title
                    ))
                } else {
                    out.append(.createLeaderboardLocalization(
                        leaderboardVendorId: lb.id, locale: ascLocale, title: title
                    ))
                }
            }
        }
        return out
    }

    // MARK: - Achievements

    private static func planAchievements(
        config: ConfigSnapshot,
        strings: XCStringsParser.LocalizedKeys,
        remote: RemoteState
    ) -> [Action] {
        var out: [Action] = []
        for ach in config.achievements {
            if let existingId = remote.achievements[ach.fullId] {
                out.append(.achievementUnchanged(id: existingId))
            } else {
                out.append(.createAchievement(ach))
            }

            for locale in targetLocales {
                guard let title = XCStringsParser.achievementTitle(
                    in: strings, locale: locale, shortId: ach.shortId
                ),
                let desc = XCStringsParser.achievementDescription(
                    in: strings, locale: locale, shortId: ach.shortId
                ),
                let unearned = XCStringsParser.achievementUnearnedDescription(
                    in: strings, locale: locale, shortId: ach.shortId
                ) else { continue }
                // xcstrings → ASC code mapping; see leaderboard branch
                // above. Same rationale (issue #31).
                let ascLocale = Config.ascLocaleCode(for: locale)
                let key = RemoteState.LocalizationKey(vendorId: ach.fullId, locale: ascLocale)
                if let locId = remote.achievementLocalizations[key] {
                    out.append(.updateAchievementLocalization(
                        localizationId: locId,
                        locale: ascLocale,
                        title: title,
                        description: desc,
                        unearnedDescription: unearned
                    ))
                } else {
                    out.append(.createAchievementLocalization(
                        achievementVendorId: ach.fullId,
                        locale: ascLocale,
                        title: title,
                        description: desc,
                        unearnedDescription: unearned
                    ))
                }
            }
        }
        return out
    }

    // MARK: - IAPs (Phase 1.a, issue #200)

    /// Plan IAP root-attribute + per-locale mutations. Phase 1.a does NOT
    /// create IAP products: if the product is absent from `remote.iaps`
    /// the reconciler emits nothing for it (apply-time error surfaces the
    /// gap via ASC `IAP_NOT_FOUND` — caller already created it in ASC web
    /// UI per issue #200 §"Phase 1 assumes the IAP product itself already
    /// exists").
    private static func planIAPs(
        config: ConfigSnapshot,
        strings: XCStringsParser.LocalizedKeys,
        remote: RemoteState
    ) -> [Action] {
        var out: [Action] = []
        for product in config.iaps {
            guard let existing = remote.iaps[product.productId] else {
                // No-op: product missing on ASC. `apply` will surface this
                // when it tries to PATCH and 404s. We intentionally do not
                // emit a Create action — Phase 1.a is metadata-only.
                continue
            }

            if iapRootDrift(product: product, remote: existing) {
                out.append(.updateIAP(existingId: existing.id, product))
            } else {
                out.append(.iapUnchanged(productId: product.productId, id: existing.id))
            }

            for locale in targetLocales {
                guard let name = XCStringsParser.iapName(
                    in: strings, locale: locale, shortId: product.shortId
                ),
                let description = XCStringsParser.iapDescription(
                    in: strings, locale: locale, shortId: product.shortId
                ) else { continue }

                let ascLocale = Config.ascLocaleCode(for: locale)
                let key = RemoteState.LocalizationKey(
                    vendorId: product.productId, locale: ascLocale
                )
                if let remoteLoc = remote.iapLocalizations[key] {
                    if remoteLoc.name == name && remoteLoc.description == description {
                        out.append(.iapLocalizationUnchanged(
                            iapProductId: product.productId, locale: ascLocale
                        ))
                    } else {
                        out.append(.updateIAPLocalization(
                            localizationId: remoteLoc.id,
                            locale: ascLocale,
                            name: name,
                            description: description
                        ))
                    }
                } else {
                    out.append(.createIAPLocalization(
                        iapId: existing.id,
                        iapProductId: product.productId,
                        locale: ascLocale,
                        name: name,
                        description: description
                    ))
                }
            }
        }
        return out
    }

    /// True if any of the three Phase 1.a root attributes
    /// (`referenceName`, `reviewNote`, `familyShareable`) on the remote
    /// resource diverges from the local config. A `nil` remote field is
    /// treated as drift (forces an initial PATCH).
    private static func iapRootDrift(
        product: IAPProduct,
        remote: RemoteState.IAPRemoteAttributes
    ) -> Bool {
        if remote.referenceName != product.referenceName { return true }
        if remote.reviewNote != product.reviewNote { return true }
        if remote.familyShareable != product.familyShareable { return true }
        return false
    }
}

/// Injection seam so tests can pass synthetic configs without touching
/// the static `Config` enum.
internal struct ConfigSnapshot: Sendable, Equatable {
    internal let leaderboards: [LeaderboardConfig]
    internal let achievements: [AchievementConfig]
    internal let iaps: [IAPProduct]

    internal init(
        leaderboards: [LeaderboardConfig],
        achievements: [AchievementConfig],
        iaps: [IAPProduct] = []
    ) {
        self.leaderboards = leaderboards
        self.achievements = achievements
        self.iaps = iaps
    }

    internal static var live: ConfigSnapshot {
        live(for: .sudoku)
    }

    /// App-scoped live snapshot (#310 `--app` precedent). Only the leaderboard
    /// set varies by app; achievements are Sudoku-only for v1, and IAPs already
    /// coexist multi-app via productId match — both carried unchanged so a
    /// single Reconciler pass still drives every resource type.
    internal static func live(for app: Config.GCApp) -> ConfigSnapshot {
        ConfigSnapshot(
            leaderboards: Config.leaderboards(for: app),
            achievements: Config.achievements,
            iaps: Config.iaps
        )
    }
}
