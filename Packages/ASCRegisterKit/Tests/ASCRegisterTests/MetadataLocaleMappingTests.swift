// MetadataLocaleMappingTests — pin the repo listing-folder locale code →
// canonical App Store Connect locale code map (issue #322).
//
// `metadata plan` showed spurious CREATE actions because the listing.yaml
// codes (`es` / `ko` / `th` for Sudoku, `es-ES` / `ko-KR` / `th-TH` for
// Minesweeper) did not match the localizations ASC already holds. The map
// normalizes both authoring styles to the canonical ASC codes.
//
// Canonical codes verified against Apple's "App Store localizations"
// reference (App Store Connect Help, 2026-06-04):
//   https://developer.apple.com/help/app-store-connect/reference/app-store-localizations/
// Crucially: Korean is `ko` (NOT `ko-KR`) and Thai is `th` (NOT `th-TH`),
// while Spanish (Spain) is `es-ES`. This is why the metadata map is kept
// separate from `Config.ascLocaleCode` (issue #31), which maps the Game
// Center catalog's `ko → ko-KR` / `th → th-TH`.

internal import Foundation
internal import Testing
@testable import ASCRegister

@Suite("MetadataConfig.ascLocaleCode")
internal struct MetadataLocaleMappingTests {

    // MARK: - Pass-through (already-canonical codes)

    @Test("en-US passes through unchanged")
    internal func enUS() {
        #expect(MetadataConfig.ascLocaleCode(forRepoCode: "en-US") == "en-US")
    }

    @Test("ja passes through unchanged")
    internal func ja() {
        #expect(MetadataConfig.ascLocaleCode(forRepoCode: "ja") == "ja")
    }

    @Test("zh-Hans passes through unchanged")
    internal func zhHans() {
        #expect(MetadataConfig.ascLocaleCode(forRepoCode: "zh-Hans") == "zh-Hans")
    }

    @Test("zh-Hant passes through unchanged")
    internal func zhHant() {
        #expect(MetadataConfig.ascLocaleCode(forRepoCode: "zh-Hant") == "zh-Hant")
    }

    @Test("es-ES passes through unchanged")
    internal func esES() {
        #expect(MetadataConfig.ascLocaleCode(forRepoCode: "es-ES") == "es-ES")
    }

    // MARK: - Sudoku short codes → canonical

    @Test("es → es-ES")
    internal func esToESES() {
        #expect(MetadataConfig.ascLocaleCode(forRepoCode: "es") == "es-ES")
    }

    @Test("ko → ko (NOT ko-KR; per Apple ASC localizations reference)")
    internal func koStaysKo() {
        #expect(MetadataConfig.ascLocaleCode(forRepoCode: "ko") == "ko")
    }

    @Test("th → th (NOT th-TH; per Apple ASC localizations reference)")
    internal func thStaysTh() {
        #expect(MetadataConfig.ascLocaleCode(forRepoCode: "th") == "th")
    }

    // MARK: - Minesweeper region-qualified codes → canonical

    @Test("ko-KR → ko (ASC has no ko-KR)")
    internal func koKRToKo() {
        #expect(MetadataConfig.ascLocaleCode(forRepoCode: "ko-KR") == "ko")
    }

    @Test("th-TH → th (ASC has no th-TH)")
    internal func thTHToTh() {
        #expect(MetadataConfig.ascLocaleCode(forRepoCode: "th-TH") == "th")
    }

    // MARK: - Unknown code fails loudly (no silent drop / pass-through)

    @Test("Unknown code returns nil")
    internal func unknownReturnsNil() {
        #expect(MetadataConfig.ascLocaleCode(forRepoCode: "fr") == nil)
        #expect(MetadataConfig.ascLocaleCode(forRepoCode: "xx-YY") == nil)
    }

    @Test("Loading a listing with an unknown locale throws unknownLocale")
    internal func loadThrowsOnUnknownLocale() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-meta-locale-\(UUID().uuidString)")
        let localeDir = tmp.appendingPathComponent("qq")
        try FileManager.default.createDirectory(at: localeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Minimal app-meta + one listing with an unsupported locale code.
        try "app: tmp\n".write(
            to: tmp.appendingPathComponent("app-meta.yaml"), atomically: true, encoding: .utf8
        )
        try "locale: qq\nname: Test\n".write(
            to: localeDir.appendingPathComponent("listing.yaml"), atomically: true, encoding: .utf8
        )

        #expect {
            try MetadataConfig.load(app: .sudoku, metadataDir: tmp.path)
        } throws: { error in
            guard case MetadataConfigError.unknownLocale(let code, _) = error else { return false }
            return code == "qq"
        }
    }
}
