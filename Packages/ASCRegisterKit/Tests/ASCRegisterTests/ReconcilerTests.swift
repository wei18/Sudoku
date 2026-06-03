// ReconcilerTests — given fixture remote state (empty / partial / full),
// assert the right ordered sequence of Actions emerges.

internal import Foundation
internal import Testing
@testable import ASCRegister

// swiftlint:disable identifier_name

@Suite("Reconciler")
internal struct ReconcilerTests {

    // MARK: - Fixtures

    private static let onlyEasy = ConfigSnapshot(
        leaderboards: [
            LeaderboardConfig(
                id: "com.wei18.sudoku.leaderboard.easy.daily.v1",
                referenceName: "Daily Easy v1",
                difficulty: "easy"
            ),
        ],
        achievements: [
            AchievementConfig(shortId: "first_puzzle", points: 10, isHidden: false),
        ]
    )

    private static let enOnly: XCStringsParser.LocalizedKeys = [
        "en": [
            "gc.leaderboard.easy.daily.title": "Daily Easy",
            "gc.achievement.first_puzzle.title": "First Puzzle",
            "gc.achievement.first_puzzle.description": "Done.",
            "gc.achievement.first_puzzle.unearnedDescription": "Do it.",
        ],
    ]

    // MARK: - Tests

    @Test("Empty remote state: create everything")
    internal func emptyRemote() {
        let actions = Reconciler.plan(
            config: Self.onlyEasy,
            strings: Self.enOnly,
            remote: RemoteState()
        )
        // Expect: createLeaderboard, createLeaderboardLocalization(en),
        //         createAchievement, createAchievementLocalization(en).
        #expect(actions.count == 4)
        switch actions[0] {
        case .createLeaderboard(let c):
            #expect(c.id == "com.wei18.sudoku.leaderboard.easy.daily.v1")
        default:
            Issue.record("expected createLeaderboard first")
        }
        switch actions[1] {
        case .createLeaderboardLocalization(let vendorId, let locale, let title):
            #expect(vendorId == "com.wei18.sudoku.leaderboard.easy.daily.v1")
            // ASC code, not xcstrings `"en"` — issue #31.
            #expect(locale == "en-US")
            #expect(title == "Daily Easy")
        default:
            Issue.record("expected createLeaderboardLocalization second")
        }
        switch actions[2] {
        case .createAchievement(let c):
            #expect(c.shortId == "first_puzzle")
        default:
            Issue.record("expected createAchievement third")
        }
        switch actions[3] {
        case .createAchievementLocalization(let vendorId, let locale, let title, let desc, let unearned):
            #expect(vendorId == "com.wei18.sudoku.achievement.first_puzzle")
            // ASC code, not xcstrings `"en"` — issue #31.
            #expect(locale == "en-US")
            #expect(title == "First Puzzle")
            #expect(desc == "Done.")
            #expect(unearned == "Do it.")
        default:
            Issue.record("expected createAchievementLocalization fourth")
        }
    }

    @Test("Full remote state: everything unchanged, localizations get update calls")
    internal func fullRemote() {
        var remote = RemoteState()
        remote.leaderboards["com.wei18.sudoku.leaderboard.easy.daily.v1"] = "lb-asc-1"
        // RemoteState mirrors what main.swift populates from ASC GET
        // responses — ASC returns regional locale codes (issue #31).
        remote.leaderboardLocalizations[
            RemoteState.LocalizationKey(vendorId: "com.wei18.sudoku.leaderboard.easy.daily.v1", locale: "en-US")
        ] = "lb-loc-en"
        remote.achievements["com.wei18.sudoku.achievement.first_puzzle"] = "ach-asc-1"
        remote.achievementLocalizations[
            RemoteState.LocalizationKey(vendorId: "com.wei18.sudoku.achievement.first_puzzle", locale: "en-US")
        ] = "ach-loc-en"

        let actions = Reconciler.plan(
            config: Self.onlyEasy,
            strings: Self.enOnly,
            remote: remote
        )
        #expect(actions.count == 4)
        switch actions[0] {
        case .leaderboardUnchanged(let id):
            #expect(id == "lb-asc-1")
        default:
            Issue.record("expected leaderboardUnchanged")
        }
        switch actions[1] {
        case .updateLeaderboardLocalization(let locId, let locale, let title):
            #expect(locId == "lb-loc-en")
            #expect(locale == "en-US")
            #expect(title == "Daily Easy")
        default:
            Issue.record("expected updateLeaderboardLocalization")
        }
        switch actions[2] {
        case .achievementUnchanged(let id):
            #expect(id == "ach-asc-1")
        default:
            Issue.record("expected achievementUnchanged")
        }
        switch actions[3] {
        case .updateAchievementLocalization(let locId, let locale, _, _, _):
            #expect(locId == "ach-loc-en")
            #expect(locale == "en-US")
        default:
            Issue.record("expected updateAchievementLocalization")
        }
    }

    @Test("Partial remote: leaderboard exists, achievement missing")
    internal func partialRemote() {
        var remote = RemoteState()
        remote.leaderboards["com.wei18.sudoku.leaderboard.easy.daily.v1"] = "lb-asc-1"

        let actions = Reconciler.plan(
            config: Self.onlyEasy,
            strings: Self.enOnly,
            remote: remote
        )
        #expect(actions.count == 4)
        if case .leaderboardUnchanged = actions[0] {} else {
            Issue.record("expected leaderboardUnchanged")
        }
        if case .createLeaderboardLocalization = actions[1] {} else {
            Issue.record("expected createLeaderboardLocalization (missing on remote)")
        }
        if case .createAchievement = actions[2] {} else {
            Issue.record("expected createAchievement")
        }
        if case .createAchievementLocalization = actions[3] {} else {
            Issue.record("expected createAchievementLocalization")
        }
    }

    @Test("Locale without translation is skipped (no Action emitted for it)")
    internal func partialLocaleCoverage() {
        let actions = Reconciler.plan(
            config: Self.onlyEasy,
            strings: Self.enOnly, // only `en` filled
            remote: RemoteState()
        )
        // 1 leaderboard create + 1 leaderboard loc (en only) +
        // 1 achievement create + 1 achievement loc (en only) = 4
        #expect(actions.count == 4)
        let localesEmitted = actions.compactMap { action -> String? in
            switch action {
            case .createLeaderboardLocalization(_, let l, _): return l
            case .createAchievementLocalization(_, let l, _, _, _): return l
            default: return nil
            }
        }
        // ASC code, not xcstrings — issue #31.
        #expect(Set(localesEmitted) == ["en-US"])
    }

    @Test("Full live config produces leaderboards first, then achievements")
    internal func phaseOrdering() {
        let actions = Reconciler.plan(
            config: .live,
            strings: [:], // no localizations
            remote: RemoteState()
        )
        // With empty strings: 3 leaderboard creates + 8 achievement creates = 11.
        #expect(actions.count == 11)
        // First 3 must all be leaderboard-related.
        for i in 0..<3 {
            switch actions[i] {
            case .createLeaderboard, .updateLeaderboard, .leaderboardUnchanged,
                 .createLeaderboardLocalization, .updateLeaderboardLocalization,
                 .leaderboardLocalizationUnchanged:
                break
            default:
                Issue.record("expected leaderboard action at index \(i)")
            }
        }
        // Remaining must be achievement-related.
        for i in 3..<actions.count {
            switch actions[i] {
            case .createAchievement, .updateAchievement, .achievementUnchanged,
                 .createAchievementLocalization, .updateAchievementLocalization,
                 .achievementLocalizationUnchanged:
                break
            default:
                Issue.record("expected achievement action at index \(i)")
            }
        }
    }
}
// swiftlint:enable identifier_name
