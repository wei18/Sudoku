// MetadataConfigLoadTests — exercises the Yams-backed YAML loader against
// the real committed `docs/app-store/metadata` tree (issue #310). The loader
// resolves each app's subtree (`sudoku/`, `minesweeper/`) under that root.
// Verifies the `|` block scalars (with embedded blank lines), nested
// `review_information:` map, `null` coercion, and the per-app subtree split
// all decode without a hand-rolled parser.
//
// The repo root is located by walking up from this test file's path
// (#filePath) so the test is independent of the process working directory.
//
// The block-scalar decoder property is verified against a fixture this test
// owns (Fixtures/BlockScalarFixture/), NOT the live app-meta.yaml/listing.yaml
// prose (issue #1004) — the marketing copy overhaul in #986 broke exact-prose
// assertions here even though the decoder and shipping copy were both correct.
// A decoder test should not depend on shipping copy at all; see
// `decodesBlockScalarFixture` below and `Fixtures/BlockScalarFixture/sudoku/`
// for the owned fixture. `liveConfigSmokeParses` keeps a SEPARATE,
// prose-free check that the real files still parse.

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

    /// This test's own fixture tree (`Fixtures/BlockScalarFixture/sudoku/`),
    /// sitting next to this file — independent of the live metadata tree and
    /// of process working directory.
    private static func fixtureMetadataDir() -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ASCRegisterTests
            .appendingPathComponent("Fixtures/BlockScalarFixture")
            .path
    }

    @Test("Sudoku tree loads app-meta + 7 locale listings")
    internal func loadsSudoku() throws {
        let config = try MetadataConfig.load(app: .sudoku, metadataDir: Self.metadataDir())
        #expect(config.appMeta.app == "sudoku")
        #expect(config.appMeta.appleId == "6771248206")
        #expect(config.appMeta.categories.primary == "Games")
        #expect(config.appMeta.categories.primaryFirstSub == "Puzzle")
        // 7 locale dirs (en, zh-Hant, zh-Hans, ja, es, th, ko) under
        // `sudoku/`; the non-locale `iap/` sibling is skipped.
        let locales = Set(config.listings.map(\.locale))
        #expect(locales.contains("en-US"))
        #expect(locales.contains("zh-Hant"))
        #expect(config.listings.count == 7)
    }

    /// Structural decoder test: both block-scalar chomping forms actually
    /// used in production (`|-` strip, `|` clip — inventoried across every
    /// `app-meta.yaml`/`listing.yaml` in `docs/app-store/metadata`; no `>`
    /// folded scalars or explicit indentation indicators appear anywhere)
    /// round-trip to EXACT known strings, with embedded blank-line paragraph
    /// breaks preserved and dedent applied — against a fixture this test
    /// owns, decoupled from shipping copy (issue #1004).
    @Test("Block scalar with embedded blank lines decodes fully (fixture)")
    internal func decodesBlockScalarFixture() throws {
        let config = try MetadataConfig.load(app: .sudoku, metadataDir: Self.fixtureMetadataDir())
        let listing = try #require(config.listings.first { $0.locale == "en-US" })

        // `|-` (strip chomping): three blank-line-separated paragraphs,
        // dedented, with NO trailing newline.
        let desc = try #require(listing.description)
        #expect(desc == """
            Paragraph one line A.
            Paragraph one line B.

            Paragraph two, single line.

            Paragraph three.
            """)
        #expect(desc.components(separatedBy: "\n\n").count == 3)  // 3 paragraphs
        #expect(!desc.hasSuffix("\n"))

        // `|` (clip chomping) with TWO trailing blank lines in the source:
        // the loader normalizes clip's single kept trailing newline away
        // too, so both chomping forms land on the same "no trailing
        // newline" shape (obs 3804 / #333) while the mid-content blank line
        // still survives.
        let promo = try #require(listing.promotionalText)
        #expect(promo == "Promo line one.\n\nPromo line two.")
        #expect(!promo.hasSuffix("\n"))

        #expect(listing.name == "Fixture Listing")
        #expect(listing.subtitle == "Fixture Subtitle")
    }

    /// Separate smoke test: the real committed files still parse and carry
    /// the decoder-relevant structural shape (non-empty, multi-paragraph
    /// description). Deliberately asserts NO specific prose — that coupling
    /// is exactly what made this suite red on every copy edit (issue #1004).
    @Test("Live sudoku metadata parses with paragraph breaks (smoke)")
    internal func liveConfigSmokeParses() throws {
        let config = try MetadataConfig.load(app: .sudoku, metadataDir: Self.metadataDir())
        let enListing = try #require(config.listings.first { $0.locale == "en-US" })
        let desc = try #require(enListing.description)
        #expect(!desc.isEmpty)
        #expect(desc.contains("\n\n"))  // blank-line paragraph break preserved
        #expect(!desc.hasSuffix("\n"))
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
