// Config — single-source-of-truth for ASCRegister content.
//
// Mirrors design.md §How.3.1 (3 leaderboards) and §How.3.2 (8 achievements,
// 550 total points). IDs MUST stay byte-equal to:
//   - GameCenterClient/LeaderboardIDs.swift  (leaderboard IDs)
//   - GameCenterClient/GameCenterSink.swift  (achievement prefix)
//   - GameCenterClient/AchievementEvaluator.swift (8 short IDs emitted)
//
// ConfigConsistencyTests enforces that equality. If you change an ID here
// you MUST change it in the production target — and bump the leaderboard
// `.v1` suffix per §How.4.5 if the generator version changed.

// swiftlint:disable orphaned_doc_comment trailing_comma

import Foundation

internal enum Config {

    // MARK: - Leaderboards (§How.3.1)

    /// Bundle-id-rooted prefix shared by all 3 daily leaderboards.
    /// Must equal `LeaderboardIDs.dailyPrefix`.
    internal static let leaderboardPrefix = "com.wei18.sudoku.leaderboard"
    /// Generator family suffix. Must equal `LeaderboardIDs.versionSuffix`.
    internal static let leaderboardVersionSuffix = "v1"

    /// 2-hour upper bound for valid completion times, per §How.3.1 score range.
    internal static let leaderboardScoreMaxMilliseconds: Int64 = 7_200_000

    internal static let leaderboards: [LeaderboardConfig] = [
        LeaderboardConfig(
            id: "\(leaderboardPrefix).easy.daily.\(leaderboardVersionSuffix)",
            referenceName: "Daily Easy v1",
            difficulty: "easy"
        ),
        LeaderboardConfig(
            id: "\(leaderboardPrefix).medium.daily.\(leaderboardVersionSuffix)",
            referenceName: "Daily Medium v1",
            difficulty: "medium"
        ),
        LeaderboardConfig(
            id: "\(leaderboardPrefix).hard.daily.\(leaderboardVersionSuffix)",
            referenceName: "Daily Hard v1",
            difficulty: "hard"
        )
    ]

    internal static var allLeaderboardIds: [String] {
        leaderboards.map(\.id)
    }

    // MARK: - Achievements (§How.3.2)

    /// Prefix applied at submission time by `GameCenterSink`. Must equal
    /// the `achievementPrefix` literal in GameCenterSink.swift.
    internal static let achievementPrefix = "com.wei18.sudoku.achievement."

    /// 8 v1 achievements, total = 550 points (§How.3.2). Order matches
    /// the design.md table top-to-bottom for review readability.
    internal static let achievements: [AchievementConfig] = [
        AchievementConfig(shortId: "first_puzzle", points: 10, isHidden: false),
        AchievementConfig(shortId: "daily.complete_one", points: 20, isHidden: false),
        AchievementConfig(shortId: "daily.streak_3", points: 50, isHidden: false),
        AchievementConfig(shortId: "daily.streak_7", points: 100, isHidden: false),
        AchievementConfig(shortId: "practice.complete_10", points: 30, isHidden: false),
        AchievementConfig(shortId: "practice.complete_100", points: 100, isHidden: false),
        AchievementConfig(shortId: "hard.master", points: 150, isHidden: false),
        AchievementConfig(shortId: "daily.sweep", points: 90, isHidden: false)
    ]

    internal static var allAchievementShortIds: [String] {
        achievements.map(\.shortId)
    }

    internal static var allAchievementFullIds: [String] {
        achievements.map { achievementPrefix + $0.shortId }
    }

    internal static var totalAchievementPoints: Int {
        achievements.reduce(0) { $0 + $1.points }
    }
}

// MARK: - Value types

internal struct LeaderboardConfig: Sendable, Equatable {
    internal let id: String
    /// Internal reference name (not localized; visible only in ASC).
    internal let referenceName: String
    /// "easy" / "medium" / "hard" — used to look up `gc.leaderboard.<d>.daily.title`.
    internal let difficulty: String

    /// ASC score formatter (plain string attribute on `gameCenterLeaderboards`).
    /// `ELAPSED_TIME_CENTISECOND` is Apple's highest-precision elapsed-time formatter
    /// (`mm:ss.SS`, 2 decimals). Confirmed by ASC 409 response 2026-05-20, issue #17.
    internal var defaultFormatter: String { "ELAPSED_TIME_CENTISECOND" }

    /// Low-to-high (ascending = better), per §How.3.1. ASC's `scoreSortType` enum
    /// expects the short token `"ASC"` (confirmed by round-2 409 response 2026-05-20,
    /// issue #19: "Expected one of: 'ASC', 'DESC'").
    internal var sortOrder: String { "ASC" }

    /// ASC recurrence cadence (plain string). Round-5 409 response 2026-05-20
    /// (issue #26) revealed the attribute is an iCalendar RFC 5545 RRULE string
    /// of the form `FREQ=[MINUTELY,HOURLY,DAILY];INTERVAL=$INT`. Daily ⇒
    /// `"FREQ=DAILY;INTERVAL=1"`.
    internal var recurrenceRule: String { "FREQ=DAILY;INTERVAL=1" }

    /// Score submission policy. `BEST_SCORE` keeps each player's lowest (best)
    /// completion time per daily cycle — required by §How.3.1 semantics
    /// ("保留每位玩家當日最佳完成時間"). The alternative `MOST_RECENT_SCORE`
    /// would overwrite stored records on every submit and is wrong for our domain.
    /// `submissionType` attribute was flagged REQUIRED by round-2 409 (issue #19).
    internal var submissionType: String { "BEST_SCORE" }

    /// ISO 8601 duration of one recurrence cycle. `"PT24H"` = 24 hours,
    /// matching the `DAILY` `recurrenceRule`. ASC requires the form with
    /// time components (the date-only `"P1D"` was rejected by round-4 with
    /// "Expected an ISO 8601 duration with time components", issue #24).
    /// Flagged REQUIRED by round-3 409 (issue #22).
    internal var recurrenceDuration: String { "PT24H" }

    /// Returns the next future UTC midnight as an ISO 8601 datetime string
    /// (`yyyy-MM-dd'T'00:00:00Z`) — the anchor instant for ASC's
    /// `recurrenceStartDate` attribute per §How.3.1.
    ///
    /// ASC requires `recurrenceStartDate` to be **strictly in the future**
    /// (round-5 409 response 2026-05-20, issue #26 — past-dated values were
    /// rejected). The algorithm:
    ///   1. Compute today's UTC midnight from `now`.
    ///   2. If that midnight is ≤ `now` (i.e. now is past 00:00 UTC today, or
    ///      exactly at 00:00 UTC), add 86400s to get tomorrow's UTC midnight.
    ///   3. Otherwise (the rare case `now` precedes today's UTC midnight —
    ///      e.g. an injected pre-epoch test date), return today's midnight.
    /// In practice every real-clock call returns tomorrow's UTC 00:00.
    ///
    /// Implemented with an explicit POSIX `DateFormatter` (not
    /// `ISO8601DateFormatter`) so the literal shape is deterministic across
    /// platforms — no fractional seconds, no `+00:00` offset variants.
    internal static func nextRecurrenceStartDateUTC(at now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let comps = calendar.dateComponents([.year, .month, .day], from: now)
        // swiftlint:disable:next force_unwrapping
        let todayMidnight = calendar.date(from: comps)!
        let target: Date = (todayMidnight <= now)
            ? todayMidnight.addingTimeInterval(86_400)
            : todayMidnight
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // swiftlint:disable:next force_unwrapping
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.dateFormat = "yyyy-MM-dd'T'00:00:00'Z'"
        return formatter.string(from: target)
    }
}

internal struct AchievementConfig: Sendable, Equatable {
    /// Short ID emitted by `AchievementEvaluator` (no prefix).
    internal let shortId: String
    /// GC points (sum across all 8 = 550).
    internal let points: Int
    /// All v1 achievements are visible (§How.3.2: "皆 visible").
    internal let isHidden: Bool

    /// Full ASC achievement ID (with prefix).
    internal var fullId: String { Config.achievementPrefix + shortId }

    /// Localization keys (mirrored in `Strings/gc-strings.xcstrings.patch`).
    internal var titleKey: String { "gc.achievement.\(shortId).title" }
    internal var descriptionKey: String { "gc.achievement.\(shortId).description" }
    internal var unearnedDescriptionKey: String { "gc.achievement.\(shortId).unearnedDescription" }

    /// Progress percent step (1 = report whole percents; 100 = boolean).
    /// Per §How.3.2: quantitative ones report percent; streak/sweep are boolean.
    internal var stepCount: Int {
        switch shortId {
        case "practice.complete_10", "practice.complete_100", "hard.master":
            return 100
        default:
            return 1 // boolean: 0 or 100
        }
    }
}
