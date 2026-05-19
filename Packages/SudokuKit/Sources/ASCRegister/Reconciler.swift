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

// swiftlint:disable identifier_name trailing_comma

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

    internal init(
        leaderboards: [String: String] = [:],
        leaderboardLocalizations: [LocalizationKey: String] = [:],
        achievements: [String: String] = [:],
        achievementLocalizations: [LocalizationKey: String] = [:]
    ) {
        self.leaderboards = leaderboards
        self.leaderboardLocalizations = leaderboardLocalizations
        self.achievements = achievements
        self.achievementLocalizations = achievementLocalizations
    }

    internal struct LocalizationKey: Sendable, Hashable {
        internal let vendorId: String
        internal let locale: String
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
        return actions
    }

    // MARK: - Leaderboards

    private static func planLeaderboards(
        config: ConfigSnapshot,
        strings: XCStringsParser.LocalizedKeys,
        remote: RemoteState
    ) -> [Action] {
        var out: [Action] = []
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
                    in: strings, locale: locale, difficulty: lb.difficulty
                ) else { continue }
                let key = RemoteState.LocalizationKey(vendorId: lb.id, locale: locale)
                if let locId = remote.leaderboardLocalizations[key] {
                    // Always emit an update — title may have changed. In a
                    // future revision we could store the last-pushed value
                    // for true diffing.
                    out.append(.updateLeaderboardLocalization(
                        localizationId: locId, locale: locale, title: title
                    ))
                } else {
                    out.append(.createLeaderboardLocalization(
                        leaderboardVendorId: lb.id, locale: locale, title: title
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
                let key = RemoteState.LocalizationKey(vendorId: ach.fullId, locale: locale)
                if let locId = remote.achievementLocalizations[key] {
                    out.append(.updateAchievementLocalization(
                        localizationId: locId,
                        locale: locale,
                        title: title,
                        description: desc,
                        unearnedDescription: unearned
                    ))
                } else {
                    out.append(.createAchievementLocalization(
                        achievementVendorId: ach.fullId,
                        locale: locale,
                        title: title,
                        description: desc,
                        unearnedDescription: unearned
                    ))
                }
            }
        }
        return out
    }
}

/// Injection seam so tests can pass synthetic configs without touching
/// the static `Config` enum.
internal struct ConfigSnapshot: Sendable, Equatable {
    internal let leaderboards: [LeaderboardConfig]
    internal let achievements: [AchievementConfig]

    internal static var live: ConfigSnapshot {
        ConfigSnapshot(leaderboards: Config.leaderboards, achievements: Config.achievements)
    }
}
