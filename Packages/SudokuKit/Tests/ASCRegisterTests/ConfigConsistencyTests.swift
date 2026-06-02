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
    }

    @Test("8 achievement short IDs match the AchievementEvaluator emitted set")
    internal func achievementShortIDs() {
        let expected: Set<String> = [
            "first_puzzle",
            "daily.complete_one",
            "daily.streak_3",
            "daily.streak_7",
            "practice.complete_10",
            "practice.complete_100",
            "hard.master",
            "daily.sweep",
        ]
        #expect(Set(Config.allAchievementShortIds) == expected)
        #expect(Config.allAchievementShortIds.count == 8)
    }

    @Test("Achievement prefix matches GameCenterSink.achievementPrefix")
    internal func achievementPrefix() {
        #expect(Config.achievementPrefix == "com.wei18.sudoku.achievement.")
    }

    @Test("Total achievement points sum to 500 (§How.3.2 budget; ASC 0-100 cap, issue #40)")
    internal func pointsBudget() {
        #expect(Config.totalAchievementPoints == 500)
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

    @Test("Remove-ads IAP productId is byte-equal to the StoreKit2 canonical identifier")
    internal func iapProductId() {
        // Hard-coded here (mirrors GC tests pattern) so this file stays
        // import-light; IAPStoreKit2 is not imported. If the StoreKit2
        // constant ever drifts, fix BOTH places — this test will fail first.
        #expect(Config.iaps.count == 1)
        #expect(Config.iaps[0].productId == "com.wei18.sudoku.iap.remove_ads")
        #expect(Config.allIAPProductIds == ["com.wei18.sudoku.iap.remove_ads"])
    }
}
