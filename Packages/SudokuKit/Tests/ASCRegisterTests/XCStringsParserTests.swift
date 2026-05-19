// XCStringsParserTests — feed fixture JSON with mixed keys (gc.* and
// non-gc.*) plus `<TRANSLATE>` / empty placeholders; assert the parser
// keeps only translated `gc.*` entries.

// swiftlint:disable trailing_comma line_length non_optional_string_data_conversion

internal import Foundation
internal import Testing
@testable import ASCRegister

@Suite("XCStringsParser")
internal struct XCStringsParserTests {

    @Test("Filters out non-gc keys, <TRANSLATE>, and empty values")
    internal func filtering() throws {
        let json = """
        {
          "sourceLanguage": "en",
          "version": "1.0",
          "strings": {
            "Welcome": {
              "localizations": {
                "en": { "stringUnit": { "state": "translated", "value": "Welcome" } }
              }
            },
            "gc.leaderboard.easy.daily.title": {
              "localizations": {
                "en":      { "stringUnit": { "state": "translated", "value": "Daily Easy" } },
                "zh-Hant": { "stringUnit": { "state": "translated", "value": "今日簡單" } },
                "ja":      { "stringUnit": { "state": "new",        "value": "<TRANSLATE>" } },
                "ko":      { "stringUnit": { "state": "new",        "value": "" } }
              }
            },
            "gc.achievement.first_puzzle.title": {
              "localizations": {
                "en":      { "stringUnit": { "state": "translated", "value": "First Puzzle" } },
                "zh-Hant": { "stringUnit": { "state": "translated", "value": "首戰告捷" } }
              }
            }
          }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let parsed = try XCStringsParser.parse(data: data)

        // "Welcome" stripped (no gc. prefix).
        #expect(parsed["en"]?["Welcome"] == nil)

        // Leaderboard title: en + zh-Hant kept; ja (<TRANSLATE>) + ko ("") filtered.
        #expect(parsed["en"]?["gc.leaderboard.easy.daily.title"] == "Daily Easy")
        #expect(parsed["zh-Hant"]?["gc.leaderboard.easy.daily.title"] == "今日簡單")
        #expect(parsed["ja"]?["gc.leaderboard.easy.daily.title"] == nil)
        #expect(parsed["ko"]?["gc.leaderboard.easy.daily.title"] == nil)

        // Achievement title kept.
        #expect(parsed["en"]?["gc.achievement.first_puzzle.title"] == "First Puzzle")
        #expect(parsed["zh-Hant"]?["gc.achievement.first_puzzle.title"] == "首戰告捷")
    }

    @Test("Lookup helpers return correct values")
    internal func lookupHelpers() throws {
        let parsed: XCStringsParser.LocalizedKeys = [
            "en": [
                "gc.leaderboard.medium.daily.title": "Daily Medium",
                "gc.achievement.daily.streak_7.title": "7-Day Streak",
                "gc.achievement.daily.streak_7.description": "desc",
                "gc.achievement.daily.streak_7.unearnedDescription": "unearned",
            ],
        ]
        #expect(XCStringsParser.leaderboardTitle(in: parsed, locale: "en", difficulty: "medium") == "Daily Medium")
        #expect(XCStringsParser.achievementTitle(in: parsed, locale: "en", shortId: "daily.streak_7") == "7-Day Streak")
        #expect(XCStringsParser.achievementDescription(in: parsed, locale: "en", shortId: "daily.streak_7") == "desc")
        #expect(XCStringsParser.achievementUnearnedDescription(in: parsed, locale: "en", shortId: "daily.streak_7") == "unearned")
        #expect(XCStringsParser.leaderboardTitle(in: parsed, locale: "ja", difficulty: "medium") == nil)
    }

    @Test("Invalid JSON throws")
    internal func invalidJSON() throws {
        let data = try #require("not json".data(using: .utf8))
        #expect(throws: (any Error).self) {
            try XCStringsParser.parse(data: data)
        }
    }
}
