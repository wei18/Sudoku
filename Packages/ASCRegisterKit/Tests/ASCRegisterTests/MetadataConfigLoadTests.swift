// MetadataConfigLoadTests — exercises the Yams-backed YAML loader against
// the real committed `docs/app-store/metadata` tree (issue #310). Verifies
// the `|` block scalars (with embedded blank lines), nested
// `review_information:` map, `null` coercion, and the per-app subtree split
// all decode without a hand-rolled parser.
//
// The repo root is located by walking up from this test file's path
// (#filePath) so the test is independent of the process working directory.

internal import Foundation
internal import Testing
@testable import ASCRegister

@Suite("MetadataConfig load")
internal struct MetadataConfigLoadTests {

    /// Repo root = four levels up from
    /// Packages/ASCRegisterKit/Tests/ASCRegisterTests/<thisFile>.
    private static func metadataDir() -> String {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent()  // ASCRegisterTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // ASCRegisterKit
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repo root
        return repoRoot.appendingPathComponent("docs/app-store/metadata").path
    }

    @Test("Sudoku tree loads app-meta + 7 locale listings")
    internal func loadsSudoku() throws {
        let config = try MetadataConfig.load(app: .sudoku, metadataDir: Self.metadataDir())
        #expect(config.appMeta.app == "sudoku")
        #expect(config.appMeta.appleId == "6771248206")
        #expect(config.appMeta.categories.primary == "Games")
        #expect(config.appMeta.categories.primaryFirstSub == "Puzzle")
        // 7 locale dirs (en, zh-Hant, zh-Hans, ja, es, th, ko); the
        // `minesweeper/` + `iap/` siblings are skipped.
        let locales = Set(config.listings.map(\.locale))
        #expect(locales.contains("en-US"))
        #expect(locales.contains("zh-Hant"))
        #expect(config.listings.count == 7)
    }

    @Test("Block scalar with embedded blank lines decodes fully (en description)")
    internal func decodesBlockScalar() throws {
        let config = try MetadataConfig.load(app: .sudoku, metadataDir: Self.metadataDir())
        let enListing = try #require(config.listings.first { $0.locale == "en-US" })
        let desc = try #require(enListing.description)
        // The description has multiple paragraphs separated by blank lines.
        #expect(desc.contains("Sudoku, made for thinking"))
        #expect(desc.contains("Truly cross-platform"))
        #expect(desc.contains("\n\n"))  // blank-line paragraph break preserved
        #expect(enListing.name == "Sudoku — Daily & Practice")
        #expect(enListing.subtitle == "Calm logic for iPhone and Mac")
    }

    @Test("YAML null coerces to nil (marketing_url)")
    internal func nullCoercesToNil() throws {
        let config = try MetadataConfig.load(app: .sudoku, metadataDir: Self.metadataDir())
        let enListing = try #require(config.listings.first { $0.locale == "en-US" })
        #expect(enListing.marketingUrl == nil)
        #expect(enListing.supportUrl == "https://github.com/wei18/Sudoku/issues")
    }

    @Test("Minesweeper subtree loads with its apple_id")
    internal func loadsMinesweeper() throws {
        let config = try MetadataConfig.load(app: .minesweeper, metadataDir: Self.metadataDir())
        #expect(config.appMeta.app == "minesweeper")
        #expect(config.appMeta.appleId == "6775733519")  // MS ASC app id (#309)
        #expect(config.appMeta.categories.primaryFirstSub == "Board")
        #expect(!config.listings.isEmpty)
    }
}
