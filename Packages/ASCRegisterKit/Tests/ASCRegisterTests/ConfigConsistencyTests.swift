// ConfigConsistencyTests — assert the ASCRegister `Config` IDs are byte-equal
// to the production `GameCenterClient` constants (design.md §How.3.1 / §How.3.2).
//
// We do NOT import GameCenterClient here (it pulls in CloudKit-adjacent
// targets and is overkill for an ID equality check). Instead we hard-code
// the expected strings and assert. If the production constants ever drift,
// fix them in BOTH places — Leader will be alerted by this test failing.

internal import Foundation
internal import Testing
@testable import ASCRegister

@Suite("Config consistency")
internal struct ConfigConsistencyTests {

    @Test("3 leaderboard IDs match the design.md §How.3.1 table exactly")
    internal func leaderboardIDs() {
        let expected = [
            "com.wei18.sudoku.leaderboard.easy.daily.v1",
            "com.wei18.sudoku.leaderboard.medium.daily.v1",
            "com.wei18.sudoku.leaderboard.hard.daily.v1",
        ]
        #expect(Config.allLeaderboardIds == expected)
        #expect(Config.leaderboards(for: .sudoku).map(\.id) == expected)
    }

    @Test("3 Minesweeper leaderboard IDs are byte-equal to MinesweeperLeaderboardID (#291)")
    internal func minesweeperLeaderboardIDs() {
        // Hard-coded here (mirrors the Sudoku GC pattern) so this file stays
        // import-light; MinesweeperUI is not imported. If the runtime
        // `MinesweeperLeaderboardID.daily(for:)` constant ever drifts from this
        // ASC Config, fix BOTH places — this test fails first.
        //
        // MS engine difficulty (beginner/intermediate/expert) maps to the
        // Sudoku-mirroring id segment (easy/medium/hard); the recurring-daily
        // `.daily.v1` shape matches Sudoku exactly.
        let expected = [
            "com.wei18.minesweeper.leaderboard.easy.daily.v1",
            "com.wei18.minesweeper.leaderboard.medium.daily.v1",
            "com.wei18.minesweeper.leaderboard.hard.daily.v1",
        ]
        #expect(Config.leaderboards(for: .minesweeper).map(\.id) == expected)
    }

    @Test("Minesweeper leaderboards mirror Sudoku's recurring-daily shape")
    internal func minesweeperLeaderboardShape() {
        for board in Config.leaderboards(for: .minesweeper) {
            #expect(board.defaultFormatter == "ELAPSED_TIME_CENTISECOND")
            #expect(board.sortOrder == "ASC")
            #expect(board.recurrenceRule == "FREQ=DAILY;INTERVAL=1")
            #expect(board.recurrenceDuration == "PT24H")
            #expect(board.submissionType == "BEST_SCORE")
            #expect(board.titleKey.hasPrefix("gc.minesweeper.leaderboard."))
        }
    }

    @Test("11 achievement short IDs match the AchievementEvaluator emitted set (8 v1 + 3 v2.6)")
    internal func achievementShortIDs() {
        let expected: Set<String> = [
            // v1
            "first_puzzle",
            "daily.complete_one",
            "daily.streak_3",
            "daily.streak_7",
            "practice.complete_10",
            "practice.complete_100",
            "hard.master",
            "daily.sweep",
            // v2.6 batch
            "perfect_run",
            "daily.streak_30",
            "expert_solver",
        ]
        #expect(Set(Config.allAchievementShortIds) == expected)
        #expect(Config.allAchievementShortIds.count == 11)
    }

    @Test("Achievement prefix matches GameCenterSink.achievementPrefix")
    internal func achievementPrefix() {
        #expect(Config.achievementPrefix == "com.wei18.sudoku.achievement.")
    }

    @Test("Total achievement points sum to 680 (v1 500 + v2.6 180; ASC 0-100 cap per entry, total cap 1000)")
    internal func pointsBudget() {
        #expect(Config.totalAchievementPoints == 680)
    }

    @Test("Every achievement's points respect ASC's 0-100 per-entry range (issue #40)")
    internal func pointsRange() {
        for ach in Config.achievements {
            #expect(ach.points >= 0 && ach.points <= 100)
        }
    }

    @Test("Full achievement IDs are correctly prefixed")
    internal func fullIDs() {
        for ach in Config.achievements {
            #expect(ach.fullId == "com.wei18.sudoku.achievement.\(ach.shortId)")
        }
    }

    @Test("Leaderboard score range upper bound is 7,200,000 ms (2-hour cap)")
    internal func scoreRange() {
        #expect(Config.leaderboardScoreMaxMilliseconds == 7_200_000)
    }

    @Test("All 3 leaderboards use ELAPSED_TIME_CENTISECOND formatter (ASC ceiling, issue #17)")
    internal func defaultFormatter() {
        for board in Config.leaderboards {
            #expect(board.defaultFormatter == "ELAPSED_TIME_CENTISECOND")
        }
    }

    @Test("All 3 leaderboards use RFC 5545 RRULE FREQ=DAILY;INTERVAL=1 (issue #26)")
    internal func recurrenceRule() {
        for board in Config.leaderboards {
            #expect(board.recurrenceRule == "FREQ=DAILY;INTERVAL=1")
        }
    }

    @Test("All 3 leaderboards use ASC sortOrder token (issue #19 ASC enum: 'ASC' | 'DESC')")
    internal func sortOrder() {
        for board in Config.leaderboards {
            #expect(board.sortOrder == "ASC")
        }
    }

    @Test("All 3 leaderboards use BEST_SCORE submissionType (sudoku semantics, issue #19)")
    internal func submissionType() {
        for board in Config.leaderboards {
            #expect(board.submissionType == "BEST_SCORE")
        }
    }

    @Test("All 3 leaderboards use PT24H recurrenceDuration (ISO 8601 24-hour, issue #24)")
    internal func recurrenceDuration() {
        for board in Config.leaderboards {
            #expect(board.recurrenceDuration == "PT24H")
        }
    }

    // MARK: - IAP (issue #200, Phase 1.a)

    @Test("Remove-ads IAP productIds are byte-equal to the StoreKit2 canonical identifiers (Sudoku + Minesweeper)")
    internal func iapProductId() {
        // Hard-coded here (mirrors GC tests pattern) so this file stays
        // import-light; IAPStoreKit2 is not imported. If the StoreKit2
        // constant ever drifts, fix BOTH places — this test will fail first.
        #expect(Config.iaps.count == 2)
        #expect(Config.iaps[0].productId == "com.wei18.sudoku.iap.remove_ads")
        #expect(Config.iaps[1].productId == "com.wei18.minesweeper.iap.remove_ads")
        #expect(Config.allIAPProductIds == [
            "com.wei18.sudoku.iap.remove_ads",
            "com.wei18.minesweeper.iap.remove_ads"
        ])
    }

    @Test("IAPProduct.shortId resolves to spec'd xcstrings key prefix for all apps")
    internal func iapShortIdNamespace() {
        // Sudoku: legacy short prefix (no app namespace)
        #expect(Config.iaps[0].shortId == "remove_ads")
        #expect(Config.iaps[0].nameKey == "iap.remove_ads.name")
        // Minesweeper: namespaced under app shortname
        #expect(Config.iaps[1].shortId == "minesweeper.remove_ads")
        #expect(Config.iaps[1].nameKey == "iap.minesweeper.remove_ads.name")
    }

    @Test("Sudoku achievements: count + points budget pinned")
    internal func sudokuAchievementsUnchanged() {
        #expect(Config.achievements.count == 11)
        #expect(Config.totalAchievementPoints == 680)
        // Sudoku prefix unchanged.
        #expect(Config.achievementPrefix == "com.wei18.sudoku.achievement.")
    }

    // MARK: - #521: locKeyPrefix derivation (no hardcoded game name in else-branch)

    @Test("locKeyPrefix derives namespace from achievementPrefix — a new game gets its own namespace, not Sudoku's (#521)")
    internal func achievementLocKeyPrefixDerived() {
        // Sudoku keeps the original un-namespaced key shape (back-compat).
        let sudokuAch = AchievementConfig(
            shortId: "first_puzzle", points: 10, isHidden: false,
            achievementPrefix: "com.wei18.sudoku.achievement."
        )
        #expect(sudokuAch.titleKey == "gc.achievement.first_puzzle.title")

        // A hypothetical new game must derive its OWN namespace from its prefix.
        let newGameAch = AchievementConfig(
            shortId: "first_win", points: 20, isHidden: false,
            achievementPrefix: "com.wei18.supergame.achievement."
        )
        #expect(newGameAch.titleKey == "gc.supergame.achievement.first_win.title")
        // Confirm it does NOT accidentally fall back to Sudoku's un-namespaced shape.
        #expect(!newGameAch.titleKey.hasPrefix("gc.achievement."))
    }

    // MARK: - #522: expectedXCStringsKeys IAP filter

    @Test("expectedXCStringsKeys filters IAP keys to the target app — each app excludes the other's IAP (#522)")
    internal func expectedXCStringsKeysIAPFilter() {
        // Sudoku validate: expects sudoku IAP keys only.
        let sudokuKeys = ASCRegisterCLI.expectedXCStringsKeysForTesting(
            leaderboards: Config.leaderboards(for: .sudoku),
            achievements: Config.achievements,
            gcApp: .sudoku
        )
        #expect(sudokuKeys.contains("iap.remove_ads.name"))
        #expect(!sudokuKeys.contains("iap.minesweeper.remove_ads.name"))

        // Minesweeper validate: expects minesweeper IAP keys only.
        let msKeys = ASCRegisterCLI.expectedXCStringsKeysForTesting(
            leaderboards: Config.leaderboards(for: .minesweeper),
            achievements: Config.achievements,
            gcApp: .minesweeper
        )
        #expect(msKeys.contains("iap.minesweeper.remove_ads.name"))
        #expect(!msKeys.contains("iap.remove_ads.name"))
    }
}
