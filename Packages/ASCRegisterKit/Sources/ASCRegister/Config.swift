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

        /// Bundle-id-rooted leaderboard prefix for this app. Must equal the
        /// app's runtime constant (`LeaderboardID.dailyPrefix` /
        /// `MinesweeperLeaderboardID.prefix`) — pinned by ConfigConsistencyTests.
        internal var leaderboardPrefix: String {
            switch self {
            case .sudoku:      return "com.wei18.sudoku.leaderboard"
            case .minesweeper: return "com.wei18.minesweeper.leaderboard"
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

    /// The 3 difficulty-based daily leaderboards for `app` (elapsed-time
    /// formatter, low-to-high sort, recurring daily). MS difficulty segments
    /// `easy/medium/hard` mirror Sudoku's id shape — see `MinesweeperLeaderboardID`.
    internal static func leaderboards(for app: GCApp) -> [LeaderboardConfig] {
        let prefix = app.leaderboardPrefix
        let keyPrefix = app.leaderboardTitleKeyPrefix
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
        )
    ]

    internal static var allIAPProductIds: [String] {
        iaps.map(\.productId)
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
        // Game Center rejects the region-suffixed th-TH / ko-KR with
        // ENTITY_ERROR.LOCALE_INVALID (live leaderboard-loc apply 2026-06-15);
        // ASC GC wants the bare th / ko (same as IAP + metadata). es-ES / en-US
        // region forms ARE accepted by GC, so only th / ko are special.
        case "th":      return "th"
        case "ko":      return "ko"
        default:        return xcstringsCode
        }
    }

    /// IAP-localization variant of `ascLocaleCode`. Now identical for all locales
    /// — both GC and IAP use bare `"th"` / `"ko"` (the earlier assumption that GC
    /// used `"th-TH"` / `"ko-KR"` was disproven by a live LOCALE_INVALID on
    /// 2026-06-15; IAP's `IAP_LOCALIZATION_UNSUPPORTED_LOCALE_CODE` for `th-TH`
    /// on 2026-06-09 #432 was the same root cause). Kept as a named alias for
    /// call-site clarity; delegates entirely to `ascLocaleCode`.
    internal static func ascIAPLocaleCode(for xcstringsCode: String) -> String {
        ascLocaleCode(for: xcstringsCode)
    }
}

// Value types (`LeaderboardConfig`, `AchievementConfig`, `IAPProduct`) live in
// `Config+Types.swift` to keep this file under the SwiftLint 400-line limit.
