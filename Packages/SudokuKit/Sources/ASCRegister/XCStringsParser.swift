// XCStringsParser — read `Localizable.xcstrings` and extract `gc.*` keys
// grouped per leaderboard/achievement, per locale. Filters `<TRANSLATE>`
// and empty entries.
//
// xcstrings JSON shape (simplified):
// {
//   "sourceLanguage": "en",
//   "strings": {
//     "gc.leaderboard.easy.daily.title": {
//       "localizations": {
//         "en":      { "stringUnit": { "state": "translated", "value": "Daily Easy" } },
//         "zh-Hant": { "stringUnit": { "state": "translated", "value": "今日簡單" } },
//         "ja":      { "stringUnit": { "state": "new",        "value": "<TRANSLATE>" } }
//       }
//     },
//     ...
//   }
// }
//
// We treat `<TRANSLATE>` and empty string as "not yet translated" and omit.

// swiftlint:disable identifier_name

import Foundation

internal struct XCStringsParser: Sendable {

    internal enum ParseError: Error, Equatable {
        case invalidJSON
        case missingStrings
    }

    /// Parsed output: `[locale: [key: value]]`. Untranslated entries are filtered.
    internal typealias LocalizedKeys = [String: [String: String]]

    internal static func parse(data: Data) throws -> LocalizedKeys {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalidJSON
        }
        guard let strings = root["strings"] as? [String: Any] else {
            throw ParseError.missingStrings
        }
        var out: LocalizedKeys = [:]
        for (key, value) in strings {
            // Keep both Game Center (`gc.*`) and IAP (`iap.*`) prefixes — IAP
            // localizations share the same xcstrings catalog shape but live
            // under their own namespace (issue #200, Phase 1.a).
            guard key.hasPrefix("gc.") || key.hasPrefix("iap.") else { continue }
            guard let entry = value as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any]
            else { continue }
            for (locale, locValue) in localizations {
                guard let locDict = locValue as? [String: Any],
                      let unit = locDict["stringUnit"] as? [String: Any],
                      let s = unit["value"] as? String
                else { continue }
                if s.isEmpty || s == "<TRANSLATE>" { continue }
                out[locale, default: [:]][key] = s
            }
        }
        return out
    }

    /// Convenience: parse from a file URL.
    internal static func parse(fileURL: URL) throws -> LocalizedKeys {
        let data = try Data(contentsOf: fileURL)
        return try parse(data: data)
    }

    // MARK: - Lookup helpers

    /// `gc.leaderboard.<difficulty>.daily.title`.
    internal static func leaderboardTitle(
        in data: LocalizedKeys,
        locale: String,
        difficulty: String
    ) -> String? {
        data[locale]?["gc.leaderboard.\(difficulty).daily.title"]
    }

    /// `gc.achievement.<shortId>.title`.
    internal static func achievementTitle(
        in data: LocalizedKeys,
        locale: String,
        shortId: String
    ) -> String? {
        data[locale]?["gc.achievement.\(shortId).title"]
    }

    internal static func achievementDescription(
        in data: LocalizedKeys,
        locale: String,
        shortId: String
    ) -> String? {
        data[locale]?["gc.achievement.\(shortId).description"]
    }

    internal static func achievementUnearnedDescription(
        in data: LocalizedKeys,
        locale: String,
        shortId: String
    ) -> String? {
        data[locale]?["gc.achievement.\(shortId).unearnedDescription"]
    }

    /// `iap.<shortId>.name` — ASC `inAppPurchaseLocalizations.name`.
    internal static func iapName(
        in data: LocalizedKeys,
        locale: String,
        shortId: String
    ) -> String? {
        data[locale]?["iap.\(shortId).name"]
    }

    /// `iap.<shortId>.description` — ASC `inAppPurchaseLocalizations.description`.
    internal static func iapDescription(
        in data: LocalizedKeys,
        locale: String,
        shortId: String
    ) -> String? {
        data[locale]?["iap.\(shortId).description"]
    }
}
