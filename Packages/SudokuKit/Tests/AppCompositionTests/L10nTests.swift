// L10nTests — Phase 9.4.
//
// Asserts the Localizable.xcstrings catalog has en + zh-Hant values for
// every declared key, and that error vocabulary keys follow the
// `error.<source>.<case>.{title|body|action}` shape (§How.6.9).

import Foundation
import Testing

@Suite("Localizable.xcstrings — en + zh-Hant seed (Phase 9.4)")
struct L10nTests {

    private static func catalogURL() throws -> URL {
        // Resolves to a symlink at `Resources/Localizable.xcstrings`
        // pointing at `Sudoku/Resources/Localizable.xcstrings` (declared as a
        // test target resource in `Package.swift`). Bundle.module finds it
        // wherever the test bundle is installed — including Xcode Cloud's
        // distributed Build/Test split where the source tree isn't on the
        // test runner.
        guard let url = Bundle.module.url(forResource: "Localizable.xcstrings", withExtension: "json") else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return url
    }

    private static func decode() throws -> [String: Any] {
        let data = try Data(contentsOf: try catalogURL())
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json ?? [:]
    }

    @Test
    func allUserFacingStringsHaveEnAndZhTW() throws {
        let catalog = try Self.decode()
        let strings = catalog["strings"] as? [String: [String: Any]] ?? [:]
        for (key, entry) in strings {
            // Keys flagged shouldTranslate=false are skipped (e.g. "—").
            if let flag = entry["shouldTranslate"] as? Bool, flag == false { continue }
            guard let localizations = entry["localizations"] as? [String: Any] else {
                Issue.record("Key '\(key)' has no localizations dict")
                continue
            }
            #expect(localizations["en"] != nil, "Key '\(key)' missing en")
            #expect(localizations["zh-Hant"] != nil, "Key '\(key)' missing zh-Hant")
        }
    }

    @Test
    func errorKeysFollowConvention() throws {
        let catalog = try Self.decode()
        let strings = catalog["strings"] as? [String: Any] ?? [:]
        let errorKeys = strings.keys.filter { $0.hasPrefix("error.") }
        #expect(!errorKeys.isEmpty, "Error vocabulary should have seed entries")
        // <case> may be snake_case (older keys: `not_authenticated`,
        // `icloud_unavailable`) OR lowerCamelCase (newer userFacing/* keys:
        // `gameCenterUnauthenticated`, `iCloudSignedOut`). Both accepted.
        let pattern = #"^error\.[a-zA-Z]+\.[a-zA-Z_]+\.(title|body|action)$"#
        let regex = try NSRegularExpression(pattern: pattern)
        for key in errorKeys {
            let range = NSRange(key.startIndex..<key.endIndex, in: key)
            let matched = regex.firstMatch(in: key, range: range) != nil
            #expect(matched, "Error key '\(key)' violates error.<source>.<case>.{title|body|action}")
        }
    }
}
