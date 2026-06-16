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

    @Test("Remove-ads IAP productIds are byte-equal to the StoreKit2 canonical identifiers (Sudoku + Minesweeper + Tiles2048)")
    internal func iapProductId() {
        // Hard-coded here (mirrors GC tests pattern) so this file stays
        // import-light; IAPStoreKit2 is not imported. If the StoreKit2
        // constant ever drifts, fix BOTH places — this test will fail first.
        #expect(Config.iaps.count == 3)
        #expect(Config.iaps[0].productId == "com.wei18.sudoku.iap.remove_ads")
        #expect(Config.iaps[1].productId == "com.wei18.minesweeper.iap.remove_ads")
        #expect(Config.iaps[2].productId == "com.wei18.tiles2048.iap.remove_ads")
        #expect(Config.allIAPProductIds == [
            "com.wei18.sudoku.iap.remove_ads",
            "com.wei18.minesweeper.iap.remove_ads",
            "com.wei18.tiles2048.iap.remove_ads"
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
        // Tiles2048: namespaced under app shortname
        #expect(Config.iaps[2].shortId == "tiles2048.remove_ads")
        #expect(Config.iaps[2].nameKey == "iap.tiles2048.remove_ads.name")
    }

    // MARK: - Tiles2048 (SDD-004 M5, OQ-GC-2048-1)

    @Test("Tiles2048: 1 leaderboard ID matches Game2048LeaderboardID.daily exactly")
    internal func tiles2048LeaderboardID() {
        // Hard-coded (mirrors MS pattern) so this file stays import-light;
        // Game2048UI is not imported. If Game2048LeaderboardID.daily drifts,
        // this test fails first — fix BOTH places.
        let expected = ["com.wei18.tiles2048.leaderboard.daily.v1"]
        #expect(Config.leaderboards(for: .tiles2048).map(\.id) == expected)
    }

    @Test("Tiles2048: leaderboard uses INTEGER format + DESC sort (OQ-GC-2048-1: higher score = better)")
    internal func tiles2048LeaderboardShape() {
        let boards = Config.leaderboards(for: .tiles2048)
        #expect(boards.count == 1)
        let board = boards[0]
        // INTEGER formatter — score is a raw integer, NOT elapsed time.
        #expect(board.defaultFormatter == "INTEGER")
        // DESC — higher score ranks first.
        #expect(board.sortOrder == "DESC")
        // Recurring daily shape mirrors Sudoku/MS exactly.
        #expect(board.recurrenceRule == "FREQ=DAILY;INTERVAL=1")
        #expect(board.recurrenceDuration == "PT24H")
        #expect(board.submissionType == "BEST_SCORE")
        #expect(board.titleKey == "gc.tiles2048.leaderboard.daily.title")
    }

    @Test("Tiles2048: achievement prefix matches expected bundle-id-rooted value")
    internal func tiles2048AchievementPrefix() {
        #expect(Config.tiles2048AchievementPrefix == "com.wei18.tiles2048.achievement.")
    }

    @Test("Tiles2048: exactly 1 achievement (reached_2048), the sole M4 signal")
    internal func tiles2048AchievementIds() {
        #expect(Config.tiles2048Achievements.count == 1)
        #expect(Config.tiles2048Achievements[0].shortId == "reached_2048")
        #expect(Config.tiles2048Achievements[0].fullId
            == "com.wei18.tiles2048.achievement.reached_2048")
    }

    @Test("Tiles2048: achievement points respect 0–100 cap (issue #40)")
    internal func tiles2048AchievementPoints() {
        #expect(Config.totalTiles2048AchievementPoints == 50)
        for ach in Config.tiles2048Achievements {
            #expect(ach.points >= 0 && ach.points <= 100)
        }
    }

    @Test("Tiles2048: achievement localization keys use gc.tiles2048.achievement namespace")
    internal func tiles2048AchievementLocKeys() {
        let ach = Config.tiles2048Achievements[0]
        #expect(ach.titleKey == "gc.tiles2048.achievement.reached_2048.title")
        #expect(ach.descriptionKey == "gc.tiles2048.achievement.reached_2048.description")
        #expect(ach.unearnedDescriptionKey
            == "gc.tiles2048.achievement.reached_2048.unearnedDescription")
    }

    @Test("Sudoku achievements are unaffected by Tiles2048 additions")
    internal func sudokuAchievementsUnchanged() {
        #expect(Config.achievements.count == 11)
        #expect(Config.totalAchievementPoints == 680)
        // Sudoku prefix unchanged.
        #expect(Config.achievementPrefix == "com.wei18.sudoku.achievement.")
    }
}
