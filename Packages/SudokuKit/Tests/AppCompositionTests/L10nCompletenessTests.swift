// L10nCompletenessTests — Phase 9.5.
//
// Asserts every key in Localizable.xcstrings carries translations for all
// 7 target locales (en, zh-Hant, zh-Hans, ja, ko, es, th) and that no
// `<TRANSLATE>` placeholder literals remain from the seed pass.

import Foundation
import Testing

@Suite("Localizable.xcstrings — all 7 locales (Phase 9.5)")
struct L10nCompletenessTests {

    private static let allLocales: Set<String> = [
        "en", "zh-Hant", "zh-Hans", "ja", "ko", "es", "th"
    ]

    private static func catalogURL(_ filePath: StaticString = #filePath) -> URL {
        let path = String(describing: filePath)
        let testFile = URL(fileURLWithPath: path)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repoRoot
            .appendingPathComponent("App")
            .appendingPathComponent("Resources")
            .appendingPathComponent("Localizable.xcstrings")
    }

    @Test
    func all7LocalesPresent() throws {
        let data = try Data(contentsOf: Self.catalogURL())
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = json?["strings"] as? [String: [String: Any]] ?? [:]
        for (key, entry) in strings {
            if let flag = entry["shouldTranslate"] as? Bool, flag == false { continue }
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            let present = Set(localizations.keys)
            let missing = Self.allLocales.subtracting(present)
            #expect(missing.isEmpty, "Key '\(key)' missing locales: \(missing.sorted())")
        }
    }

    @Test
    func noUntranslatedMarkers() throws {
        let raw = try String(contentsOf: Self.catalogURL(), encoding: .utf8)
        #expect(!raw.contains("<TRANSLATE>"), "Catalog still contains <TRANSLATE> placeholders")
    }
}
