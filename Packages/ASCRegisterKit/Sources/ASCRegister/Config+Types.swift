// Config+Types — value types used by Config and Reconciler.
//
// Extracted from Config.swift to keep that file under the 400-line SwiftLint
// `file_length` limit. All types here are `internal` within ASCRegister.

import Foundation

// MARK: - LeaderboardConfig

internal struct LeaderboardConfig: Sendable, Equatable {
    internal let id: String
    /// Internal reference name (not localized; visible only in ASC).
    internal let referenceName: String
    /// "easy" / "medium" / "hard" — kept for back-compat / diagnostics.
    internal let difficulty: String
    /// Full xcstrings key for this leaderboard's localized title. App-scoped
    /// so Sudoku (`gc.leaderboard.<d>.daily.title`) and Minesweeper
    /// (`gc.minesweeper.leaderboard.<d>.daily.title`) coexist in one catalog.
    internal let titleKey: String
    /// ASC score formatter. Defaults to `"ELAPSED_TIME_CENTISECOND"` (Sudoku/MS).
    /// A score-based game can pass `"INTEGER"` (raw integer score, not time).
    internal let scoreFormat: String
    /// ASC `scoreSortType` token. Defaults to `"ASC"` (lower elapsed-time = better).
    /// A high-score-wins game passes `"DESC"`. Confirmed tokens: "ASC" / "DESC"
    /// (round-2 409 2026-05-20, issue #19).
    internal let sortOrder: String

    /// Back-compat initializer defaulting `titleKey` to the original
    /// un-namespaced Sudoku key, `scoreFormat` to elapsed-time, and `sortOrder`
    /// to ascending. Used by tests that build synthetic configs.
    internal init(
        id: String,
        referenceName: String,
        difficulty: String,
        titleKey: String? = nil,
        scoreFormat: String = "ELAPSED_TIME_CENTISECOND",
        sortOrder: String = "ASC"
    ) {
        self.id = id
        self.referenceName = referenceName
        self.difficulty = difficulty
        self.titleKey = titleKey ?? "gc.leaderboard.\(difficulty).daily.title"
        self.scoreFormat = scoreFormat
        self.sortOrder = sortOrder
    }

    /// ASC score formatter (plain string attribute on `gameCenterLeaderboards`).
    /// `ELAPSED_TIME_CENTISECOND` is Apple's highest-precision elapsed-time formatter
    /// (`mm:ss.SS`, 2 decimals). Confirmed by ASC 409 response 2026-05-20, issue #17.
    internal var defaultFormatter: String { scoreFormat }

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

// MARK: - AchievementConfig

internal struct AchievementConfig: Sendable, Equatable {
    /// Short ID emitted by `AchievementEvaluator` (no prefix).
    internal let shortId: String
    /// GC points (sum across all 8 = 500; ASC caps each entry at 0-100, issue #40).
    internal let points: Int
    /// All v1 achievements are visible (§How.3.2: "皆 visible").
    internal let isHidden: Bool
    /// Per-instance achievement prefix. Defaults to `Config.achievementPrefix`
    /// (Sudoku). A new game can pass its own bundle-id-rooted prefix so multiple
    /// games' achievements coexist without a per-app config struct split.
    private let achievementPrefix: String

    internal init(
        shortId: String,
        points: Int,
        isHidden: Bool,
        achievementPrefix: String = Config.achievementPrefix
    ) {
        self.shortId = shortId
        self.points = points
        self.isHidden = isHidden
        self.achievementPrefix = achievementPrefix
    }

    /// Full ASC achievement ID (bundle-id-rooted, with prefix).
    internal var fullId: String { achievementPrefix + shortId }

    /// Localization key namespace. Derived from the `achievementPrefix` itself
    /// (mirrors how `GCApp.leaderboardTitleKeyPrefix` derives the leaderboard
    /// key namespace). Sudoku (`com.wei18.sudoku.achievement.`) keeps the
    /// original un-namespaced `gc.achievement` for back-compat with shipped
    /// xcstrings keys. Any other app (e.g. a new game →
    /// `com.wei18.<game>.achievement.`) gets a scoped namespace
    /// `gc.<app>.achievement` — no hardcoded game name in the else-branch.
    private var locKeyPrefix: String {
        let vendorPrefix = "com.wei18."
        let achievementInfix = ".achievement."
        guard achievementPrefix.hasPrefix(vendorPrefix),
              let infixRange = achievementPrefix.range(of: achievementInfix)
        else { return "gc.achievement" }
        let appSegment = String(achievementPrefix[vendorPrefix.endIndex..<infixRange.lowerBound])
        if appSegment == "sudoku" { return "gc.achievement" }
        return "gc.\(appSegment).achievement"
    }

    internal var titleKey: String { "\(locKeyPrefix).\(shortId).title" }
    internal var descriptionKey: String { "\(locKeyPrefix).\(shortId).description" }
    internal var unearnedDescriptionKey: String { "\(locKeyPrefix).\(shortId).unearnedDescription" }
}

// MARK: - IAPProduct

/// One ASC in-app purchase product. Phase 1.a fields only (no pricing).
internal struct IAPProduct: Sendable, Equatable {
    /// Bundle-id-rooted product identifier (e.g.
    /// `"com.wei18.sudoku.iap.remove_ads"`). Must equal the StoreKit2
    /// constant in `IAPStoreKit2`.
    internal let productId: String
    /// Internal reference name (visible only in ASC; not localized).
    internal let referenceName: String
    /// `familySharable` attribute on the ASC `inAppPurchases` resource.
    internal let familyShareable: Bool
    /// `reviewNote` attribute on the ASC `inAppPurchases` resource — guides
    /// App Review during IAP screening.
    internal let reviewNote: String

    /// Short identifier used to derive xcstrings keys
    /// (`iap.<shortId>.name` / `iap.<shortId>.description`).
    ///
    /// Two namespaces are supported (MS Phase 2):
    ///   - Sudoku products (`com.wei18.sudoku.iap.<x>`) → `<x>`
    ///     (preserves the shipped Sudoku key shape e.g. `iap.remove_ads.name`).
    ///   - Other-app products (`com.wei18.<app>.iap.<x>`) → `<app>.<x>`
    ///     (e.g. MS → `minesweeper.remove_ads`, yielding the spec'd key
    ///     `iap.minesweeper.remove_ads.name`).
    /// Anything not matching either pattern returns the productId unchanged
    /// — the resulting xcstrings lookup will simply miss and the locale
    /// be skipped, surfacing the gap rather than silently corrupting a key.
    internal var shortId: String {
        let sudokuPrefix = "com.wei18.sudoku.iap."
        if productId.hasPrefix(sudokuPrefix) {
            return String(productId.dropFirst(sudokuPrefix.count))
        }
        let vendorPrefix = "com.wei18."
        guard productId.hasPrefix(vendorPrefix) else { return productId }
        let trimmed = String(productId.dropFirst(vendorPrefix.count))
        // Collapse the `.iap.` infix to a single dot, leaving `<app>.<x>`.
        return trimmed.replacingOccurrences(of: ".iap.", with: ".")
    }

    internal var nameKey: String { "iap.\(shortId).name" }
    internal var descriptionKey: String { "iap.\(shortId).description" }
}
