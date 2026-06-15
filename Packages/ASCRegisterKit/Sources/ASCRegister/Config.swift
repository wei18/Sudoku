// Config — single-source-of-truth for ASCRegister content.
//
// Mirrors docs/v1/design.md §How.3.1 (3 leaderboards) and §How.3.2 (13 achievements,
// 680 total points (v1 500 + v2.6 batch 180); ASC caps each entry at 0-100, issue #40). IDs MUST stay byte-equal to:
//   - GameCenterClient/LeaderboardIDs.swift  (leaderboard IDs)
//   - GameCenterClient/GameCenterSink.swift  (achievement prefix)
//   - GameCenterClient/AchievementEvaluator.swift (13 short IDs emitted, v2.6)
//
// ConfigConsistencyTests enforces that equality. If you change an ID here
// you MUST change it in the production target — and bump the leaderboard
// `.v1` suffix per §How.4.5 if the generator version changed.

import Foundation

internal enum Config {

    // MARK: - App selector (GC, mirrors `MetadataApp` / `--app`, #310)

    /// Which app's Game Center leaderboard set to reconcile. Selected by the
    /// `--app` flag on `plan` / `apply` / `validate`; defaults to `.sudoku`
    /// so every existing single-app call site keeps working unchanged.
    ///
    /// Achievements + IAPs are NOT app-split here: achievements are Sudoku-only
    /// for v1, and IAPs already coexist multi-app via productId matching
    /// (see `Config.iaps`). Only the leaderboard *set* varies by app.
    internal enum GCApp: String, Sendable, CaseIterable {
        case sudoku
        case minesweeper
        case tiles2048

        /// Bundle-id-rooted leaderboard prefix for this app. Must equal the
        /// app's runtime constant (`LeaderboardID.dailyPrefix` /
        /// `MinesweeperLeaderboardID.prefix` / `Game2048LeaderboardID.prefix`)
        /// — pinned by ConfigConsistencyTests.
        internal var leaderboardPrefix: String {
            switch self {
            case .sudoku:      return "com.wei18.sudoku.leaderboard"
            case .minesweeper: return "com.wei18.minesweeper.leaderboard"
            case .tiles2048:   return "com.wei18.tiles2048.leaderboard"
            }
        }

        /// xcstrings key namespace for this app's leaderboard titles. Sudoku
        /// keeps the original un-namespaced `gc.leaderboard.*` keys (shipped);
        /// other apps get an app-scoped namespace so all titles coexist in one
        /// catalog.
        internal var leaderboardTitleKeyPrefix: String {
            switch self {
            case .sudoku:      return "gc.leaderboard"
            case .minesweeper: return "gc.minesweeper.leaderboard"
            case .tiles2048:   return "gc.tiles2048.leaderboard"
            }
        }
    }

    // MARK: - Leaderboards (§How.3.1)

    /// Bundle-id-rooted prefix shared by all 3 Sudoku daily leaderboards.
    /// Must equal `LeaderboardIDs.dailyPrefix`.
    internal static let leaderboardPrefix = GCApp.sudoku.leaderboardPrefix
    /// Generator family suffix. Must equal `LeaderboardIDs.versionSuffix`.
    internal static let leaderboardVersionSuffix = "v1"

    /// 2-hour upper bound for valid completion times, per §How.3.1 score range.
    internal static let leaderboardScoreMaxMilliseconds: Int64 = 7_200_000

    /// The daily leaderboard(s) for `app`.
    ///
    /// Sudoku + Minesweeper: 3 difficulty-based boards
    /// (elapsed-time formatter, low-to-high sort, recurring daily).
    /// MS difficulty segments `easy/medium/hard` mirror Sudoku's id shape —
    /// see `MinesweeperLeaderboardID`.
    ///
    /// Tiles2048: 1 single daily board (INTEGER formatter, high-to-low sort,
    /// recurring daily). The leaderboard metric is the game score (higher =
    /// better), not elapsed time. OQ-GC-2048-1 resolved: `scoreSortType =
    /// "DESC"`, `scoreFormat = "INTEGER"`. ID must equal
    /// `Game2048LeaderboardID.daily`.
    internal static func leaderboards(for app: GCApp) -> [LeaderboardConfig] {
        let prefix = app.leaderboardPrefix
        let keyPrefix = app.leaderboardTitleKeyPrefix
        switch app {
        case .tiles2048:
            return [
                LeaderboardConfig(
                    id: "\(prefix).daily.\(leaderboardVersionSuffix)",
                    referenceName: "Daily v1",
                    difficulty: "",
                    titleKey: "\(keyPrefix).daily.title",
                    scoreFormat: "INTEGER",
                    sortOrder: "DESC"
                )
            ]
        default:
            let titleCase: (String) -> String = { $0.prefix(1).uppercased() + $0.dropFirst() }
            return ["easy", "medium", "hard"].map { difficulty in
                LeaderboardConfig(
                    id: "\(prefix).\(difficulty).daily.\(leaderboardVersionSuffix)",
                    referenceName: "Daily \(titleCase(difficulty)) v1",
                    difficulty: difficulty,
                    titleKey: "\(keyPrefix).\(difficulty).daily.title"
                )
            }
        }
    }

    /// Sudoku's 3 daily leaderboards. Retained as the default set for every
    /// existing call site (`.live`, `validate` without `--app`); equal to
    /// `leaderboards(for: .sudoku)`.
    internal static let leaderboards: [LeaderboardConfig] = leaderboards(for: .sudoku)

    internal static var allLeaderboardIds: [String] {
        leaderboards.map(\.id)
    }

    // MARK: - Achievements (§How.3.2)

    /// Prefix applied at submission time by `GameCenterSink`. Must equal
    /// the `achievementPrefix` literal in GameCenterSink.swift.
    internal static let achievementPrefix = "com.wei18.sudoku.achievement."

    /// 11 achievements: 8 v1 + 3 v2.6 batch.
    /// v1 total = 500 pts; v2.6 adds 180 pts → grand total = 680 pts.
    /// Apple's per-app GC cap = 1000 pts; 680 is within budget.
    ///
    /// ASC enforces a per-achievement points range of 0-100 (round-8 apply
    /// rejected `hard.master = 150` with `INVALID_POINTS_RANGE: points
    /// between 0 and 100`, issue #40). All entries respect this constraint.
    internal static let achievements: [AchievementConfig] = [
        // v1 (8)
        AchievementConfig(shortId: "first_puzzle", points: 10, isHidden: false),
        AchievementConfig(shortId: "daily.complete_one", points: 20, isHidden: false),
        AchievementConfig(shortId: "daily.streak_3", points: 50, isHidden: false),
        AchievementConfig(shortId: "daily.streak_7", points: 100, isHidden: false),
        AchievementConfig(shortId: "practice.complete_10", points: 30, isHidden: false),
        AchievementConfig(shortId: "practice.complete_100", points: 100, isHidden: false),
        AchievementConfig(shortId: "hard.master", points: 100, isHidden: false),
        AchievementConfig(shortId: "daily.sweep", points: 90, isHidden: false),
        // v2.6 batch (5)
        AchievementConfig(shortId: "perfect_run", points: 50, isHidden: false),
        AchievementConfig(shortId: "daily.streak_30", points: 100, isHidden: false),
        AchievementConfig(shortId: "expert_solver", points: 30, isHidden: false),
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

    // MARK: - In-App Purchases (issue #200, Phase 1.a + MS Phase 2)

    /// v2.5 IAP products driven by ASCRegister. Phase 1.a only mutates
    /// metadata on EXISTING products in ASC (localizations + reviewNote +
    /// familyShareable); it does NOT create products and does NOT manage
    /// pricing (pricing = Phase 1.b, separate PR).
    ///
    /// `productId` must equal the StoreKit2 product identifier shipped in
    /// the App binary (`Packages/AppMonetizationKit/Sources/IAPStoreKit2/`).
    ///
    /// **Multi-app design (MS Phase 2):** both Sudoku and Minesweeper
    /// remove-ads products coexist in this single list. ASCRegister is
    /// invoked once per ASC app via `--app-id <id>`; the IAP reconciler
    /// looks each `Config.iaps` entry up on the targeted app and silently
    /// no-ops on the ones not found (e.g. running against the Sudoku app
    /// skips the Minesweeper product, and vice versa). This avoids the
    /// ceremony of a per-app config struct for only two products. If a
    /// third app or 10+ products land, revisit a per-app split.
    internal static let iaps: [IAPProduct] = [
        IAPProduct(
            productId: "com.wei18.sudoku.iap.remove_ads",
            referenceName: "Remove Ads v1",
            familyShareable: true,
            reviewNote: """
                This non-consumable IAP removes banner and interstitial ads \
                app-wide. Test by purchasing in Settings → Pro → Remove Ads. \
                After purchase, ads should not appear anywhere in the app.
                """
        ),
        IAPProduct(
            productId: "com.wei18.minesweeper.iap.remove_ads",
            referenceName: "Remove Ads v1",
            familyShareable: true,
            reviewNote: """
                This non-consumable IAP removes banner ads app-wide. Test \
                by purchasing in Settings → Pro → Remove Ads. After \
                purchase, ads should not appear anywhere in the app.
                """
        ),
        IAPProduct(
            productId: "com.wei18.tiles2048.iap.remove_ads",
            referenceName: "Remove Ads v1",
            familyShareable: true,
            reviewNote: """
                This non-consumable IAP removes banner ads app-wide. Test \
                by purchasing in Settings → Pro → Remove Ads. After \
                purchase, ads should not appear anywhere in the app.
                """
        )
    ]

    internal static var allIAPProductIds: [String] {
        iaps.map(\.productId)
    }

    // MARK: - Tiles2048 Game Center (OQ-GC-2048-1, SDD-004 M5)

    /// Achievement prefix for Tiles2048. Must equal the runtime constant in
    /// Game2048AppComposition's GameCenterSink (to be wired at M5).
    internal static let tiles2048AchievementPrefix = "com.wei18.tiles2048.achievement."

    /// Tiles2048 achievements: only those M4 code actually reports.
    ///
    /// M4 analysis: `Game2048SessionSnapshot.reachedTarget` is the sole
    /// achievement signal in Game2048Kit (flows through
    /// `Game2048GameViewModel` → `Game2048CompletionViewModel`). No other
    /// achievement shortIds are emitted. Do NOT add achievements the code
    /// does not report.
    ///
    /// `reached_2048`: awarded when the 2048 tile is reached in a run.
    /// Points: 50 (respects ASC 0–100 cap per entry, issue #40).
    internal static let tiles2048Achievements: [AchievementConfig] = [
        AchievementConfig(
            shortId: "reached_2048",
            points: 50,
            isHidden: false,
            achievementPrefix: tiles2048AchievementPrefix
        )
    ]

    internal static var allTiles2048AchievementShortIds: [String] {
        tiles2048Achievements.map(\.shortId)
    }

    internal static var allTiles2048AchievementFullIds: [String] {
        tiles2048Achievements.map(\.fullId)
    }

    internal static var totalTiles2048AchievementPoints: Int {
        tiles2048Achievements.reduce(0) { $0 + $1.points }
    }

    // MARK: - Locale code mapping (issue #31)

    /// Map an xcstrings locale code (the App's source-of-truth, e.g. `"en"`,
    /// `"zh-Hant"`) to the ASC code expected by App Store Connect
    /// (e.g. `"en-US"`, `"zh-Hant"`). Round-6 apply rejected the bare
    /// xcstrings codes with `LOCALE_INVALID`; round-7 then rejected
    /// `"zh-Hant-TW"` for Game Center — ASC's Game Center locale catalog
    /// uses the script-only form `"zh-Hant"` / `"zh-Hans"` (no region) for
    /// Chinese (issue #37).
    ///
    /// Unknown codes pass through unchanged — preserves any locale we add
    /// in the future without re-hardcoding here, at the cost of a
    /// `LOCALE_INVALID` reply ASC-side that surfaces the gap on next apply.
    internal static func ascLocaleCode(for xcstringsCode: String) -> String {
        switch xcstringsCode {
        case "en":      return "en-US"
        case "zh-Hant": return "zh-Hant"
        case "zh-Hans": return "zh-Hans"
        case "ja":      return "ja"
        case "es":      return "es-ES"
        case "th":      return "th-TH"
        case "ko":      return "ko-KR"
        default:        return xcstringsCode
        }
    }

    /// IAP-localization variant of `ascLocaleCode`. ASC's **in-app-purchase**
    /// localization catalog (like App Store *metadata* — see `MetadataConfig`)
    /// uses the bare `"th"` / `"ko"` codes, NOT the region-suffixed
    /// `"th-TH"` / `"ko-KR"` that `ascLocaleCode` returns for Game Center. A
    /// live `iap apply` (2026-06-09, #432) got
    /// `IAP_LOCALIZATION_UNSUPPORTED_LOCALE_CODE` for `th-TH`. All other
    /// locales match `ascLocaleCode` (e.g. `es` → `es-ES`, `en` → `en-US`).
    internal static func ascIAPLocaleCode(for xcstringsCode: String) -> String {
        switch xcstringsCode {
        case "th": return "th"
        case "ko": return "ko"
        default:   return ascLocaleCode(for: xcstringsCode)
        }
    }
}

// MARK: - Value types

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
    /// Tiles2048 passes `"INTEGER"` (OQ-GC-2048-1: score is a raw integer, not time).
    internal let scoreFormat: String
    /// ASC `scoreSortType` token. Defaults to `"ASC"` (lower elapsed-time = better).
    /// Tiles2048 passes `"DESC"` (higher score = better). Confirmed tokens: "ASC" / "DESC"
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

internal struct AchievementConfig: Sendable, Equatable {
    /// Short ID emitted by `AchievementEvaluator` (no prefix).
    internal let shortId: String
    /// GC points (sum across all 8 = 500; ASC caps each entry at 0-100, issue #40).
    internal let points: Int
    /// All v1 achievements are visible (§How.3.2: "皆 visible").
    internal let isHidden: Bool
    /// Per-instance achievement prefix. Defaults to `Config.achievementPrefix`
    /// (Sudoku). Tiles2048 passes `Config.tiles2048AchievementPrefix` so both
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

    /// Localization key namespace. Sudoku uses `gc.achievement.<shortId>.*`;
    /// Tiles2048 uses `gc.tiles2048.achievement.<shortId>.*` so both games'
    /// achievement strings coexist in one xcstrings catalog.
    private var locKeyPrefix: String {
        achievementPrefix == Config.achievementPrefix
            ? "gc.achievement"
            : "gc.tiles2048.achievement"
    }

    internal var titleKey: String { "\(locKeyPrefix).\(shortId).title" }
    internal var descriptionKey: String { "\(locKeyPrefix).\(shortId).description" }
    internal var unearnedDescriptionKey: String { "\(locKeyPrefix).\(shortId).unearnedDescription" }

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
