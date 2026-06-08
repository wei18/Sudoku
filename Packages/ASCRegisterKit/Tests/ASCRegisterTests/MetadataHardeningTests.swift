// MetadataHardeningTests — pre-flight ASC field-length validation + the
// first-version `whatsNew` drop (issue #310). Both are pure / unit-testable:
// the length validator runs over an in-memory `MetadataConfig`, and the
// first-version rule is exercised through the pure `MetadataReconciler.plan`
// payload builder — no live ASC.

internal import Foundation
internal import Testing
@testable import ASCRegister

// MARK: - Helpers

private func listing(
    locale: String = "en-US",
    name: String? = nil,
    subtitle: String? = nil,
    keywords: String? = nil,
    promotionalText: String? = nil,
    description: String? = nil,
    whatsNew: String? = nil
) -> ListingLocale {
    ListingLocale(
        locale: locale,
        name: name,
        subtitle: subtitle,
        privacyPolicyUrl: nil,
        description: description,
        keywords: keywords,
        promotionalText: promotionalText,
        whatsNew: whatsNew,
        marketingUrl: nil,
        supportUrl: nil
    )
}

private func config(_ listings: [ListingLocale]) -> MetadataConfig {
    let meta = AppMeta(
        app: "sudoku",
        appleId: "1",
        copyright: nil,
        categories: AppMeta.Categories(
            primary: nil, primaryFirstSub: nil, primarySecondSub: nil,
            secondary: nil, secondaryFirstSub: nil, secondarySecondSub: nil
        )
    )
    return MetadataConfig(appMeta: meta, listings: listings)
}

private func violations(of error: Error) -> [FieldLengthViolation] {
    guard case let MetadataConfigError.fieldsTooLong(list) = error else { return [] }
    return list
}

// MARK: - Field length validation

@Suite("Metadata field-length validation (#310)")
internal struct MetadataFieldLengthTests {

    @Test("Clean data passes")
    internal func cleanPasses() throws {
        let cfg = config([listing(
            name: String(repeating: "a", count: 30),
            subtitle: String(repeating: "b", count: 30),
            keywords: String(repeating: "k", count: 100),
            promotionalText: String(repeating: "p", count: 170),
            description: String(repeating: "d", count: 4000),
            whatsNew: String(repeating: "w", count: 4000)
        )])
        try cfg.validateFieldLengths(app: "sudoku")  // must not throw
    }

    @Test("Over-limit name is flagged with app+locale+field+actual+limit")
    internal func nameTooLong() {
        let cfg = config([listing(locale: "ja", name: String(repeating: "n", count: 31))])
        #expect(throws: MetadataConfigError.self) { try cfg.validateFieldLengths(app: "sudoku") }
        do {
            try cfg.validateFieldLengths(app: "sudoku")
        } catch {
            let found = violations(of: error)
            #expect(found.count == 1)
            let only = try? #require(found.first)
            #expect(only?.app == "sudoku")
            #expect(only?.locale == "ja")
            #expect(only?.field == "name")
            #expect(only?.actual == 31)
            #expect(only?.limit == 30)
        }
    }

    @Test("Each field type is caught at +1 over its cap")
    internal func eachFieldCaught() {
        let cases: [(String, ListingLocale, Int)] = [
            ("subtitle", listing(subtitle: String(repeating: "s", count: 31)), 30),
            ("keywords", listing(keywords: String(repeating: "k", count: 101)), 100),
            ("promotionalText", listing(promotionalText: String(repeating: "p", count: 171)), 170),
            ("description", listing(description: String(repeating: "d", count: 4001)), 4000),
            ("whatsNew", listing(whatsNew: String(repeating: "w", count: 4001)), 4000),
        ]
        for (field, sample, limit) in cases {
            do {
                try config([sample]).validateFieldLengths(app: "sudoku")
                Issue.record("expected \(field) to be flagged")
            } catch {
                let found = violations(of: error)
                #expect(found.first?.field == field, "\(field)")
                #expect(found.first?.limit == limit, "\(field)")
            }
        }
    }

    @Test("All violations reported at once, not just the first")
    internal func allViolationsAtOnce() {
        let cfg = config([
            listing(locale: "en-US", subtitle: String(repeating: "s", count: 40)),
            listing(locale: "ja", name: String(repeating: "n", count: 50)),
            listing(locale: "th", keywords: String(repeating: "k", count: 200)),
        ])
        do {
            try cfg.validateFieldLengths(app: "sudoku")
            Issue.record("expected throw")
        } catch {
            let found = violations(of: error)
            #expect(found.count == 3)
            #expect(Set(found.map(\.locale)) == ["en-US", "ja", "th"])
        }
    }

    // MARK: trailing-newline counting edge

    @Test("Trailing newline is NOT counted (block-scalar artifact)")
    internal func trailingNewlineNotCounted() {
        // 170 chars + a YAML block-scalar trailing "\n" = 171 raw, but ASC
        // counts 170. Must pass (the live `promotional_text` at 171 case).
        let promo = String(repeating: "p", count: 170) + "\n"
        #expect(MetadataConfig.ascCharacterCount(promo) == 170)
        let cfg = config([listing(promotionalText: promo)])
        #expect(throws: Never.self) { try cfg.validateFieldLengths(app: "sudoku") }
    }

    @Test("CRLF trailing newline also stripped")
    internal func crlfStripped() {
        #expect(MetadataConfig.ascCharacterCount("abc\r\n") == 3)
    }

    @Test("Only ONE trailing newline stripped; internal newlines still count")
    internal func internalNewlinesCount() {
        // "a\n\n" — one paragraph break + a trailing newline. ASC counts the
        // internal blank line: 'a' + '\n' (internal) = 2 after stripping the
        // single trailing '\n'.
        #expect(MetadataConfig.ascCharacterCount("a\n\n") == 2)
        // Leading whitespace counts.
        #expect(MetadataConfig.ascCharacterCount("  ab") == 4)
    }

    @Test("Grapheme clusters counted as single characters")
    internal func graphemeCount() {
        // A flag emoji is one grapheme cluster though several scalars.
        #expect(MetadataConfig.ascCharacterCount("🇹🇭") == 1)
    }
}

// MARK: - First-version whatsNew drop

@Suite("First-version whatsNew drop (#310)")
internal struct FirstVersionWhatsNewTests {

    private func versionActions(hasReleased: Bool, whatsNew: String?) -> [MetadataAction] {
        let cfg = config([listing(description: "desc", whatsNew: whatsNew)])
        let remote = MetadataRemoteState(
            versionId: "v1",
            hasReleasedVersion: hasReleased
        )
        return MetadataReconciler.plan(config: cfg, remote: remote)
    }

    @Test("First version (no released predecessor) omits whatsNew from create")
    internal func firstVersionDropsWhatsNew() throws {
        let actions = versionActions(hasReleased: false, whatsNew: "Bug fixes")
        let create = try #require(actions.compactMap { action -> ListingLocale? in
            if case let .createVersionLoc(_, _, payload) = action { return payload }
            return nil
        }.first)
        #expect(create.whatsNew == nil)
        #expect(create.description == "desc")  // other fields preserved
    }

    @Test("Released-predecessor app keeps sending whatsNew")
    internal func releasedKeepsWhatsNew() throws {
        let actions = versionActions(hasReleased: true, whatsNew: "Bug fixes")
        let create = try #require(actions.compactMap { action -> ListingLocale? in
            if case let .createVersionLoc(_, _, payload) = action { return payload }
            return nil
        }.first)
        #expect(create.whatsNew == "Bug fixes")
    }

    @Test("First version: whatsNew also dropped from UPDATE payload")
    internal func firstVersionDropsWhatsNewOnUpdate() throws {
        let cfg = config([listing(description: "new desc", whatsNew: "notes")])
        let remote = MetadataRemoteState(
            versionId: "v1",
            versionLocalizations: [
                "en-US": MetadataRemoteState.VersionLocRemote(id: "loc1", description: "old desc"),
            ],
            hasReleasedVersion: false
        )
        let actions = MetadataReconciler.plan(config: cfg, remote: remote)
        let update = try #require(actions.compactMap { action -> ListingLocale? in
            if case let .updateVersionLoc(_, _, payload) = action { return payload }
            return nil
        }.first)
        #expect(update.whatsNew == nil)
        #expect(update.description == "new desc")
    }

    @Test("First version + ONLY whatsNew differs ⇒ no spurious version action")
    internal func firstVersionWhatsNewOnlyDriftIsNoOp() {
        // Remote matches config on everything except whatsNew (which ASC holds
        // as nil on a first version). After the drop, desired == remote ⇒
        // versionLocUnchanged, no UPDATE that would 409.
        let cfg = config([listing(description: "same", whatsNew: "would-be notes")])
        let remote = MetadataRemoteState(
            versionId: "v1",
            versionLocalizations: [
                "en-US": MetadataRemoteState.VersionLocRemote(id: "loc1", description: "same", whatsNew: nil),
            ],
            hasReleasedVersion: false
        )
        let actions = MetadataReconciler.plan(config: cfg, remote: remote)
        #expect(actions.contains(.versionLocUnchanged(locale: "en-US")))
        let hasUpdate = actions.contains { if case .updateVersionLoc = $0 { return true } else { return false } }
        #expect(!hasUpdate)
    }

    @Test("releasedAppStoreStates includes READY_FOR_SALE, excludes PREPARE_FOR_SUBMISSION")
    internal func releasedStatesTable() {
        #expect(MetadataRemoteState.releasedAppStoreStates.contains("READY_FOR_SALE"))
        #expect(!MetadataRemoteState.releasedAppStoreStates.contains("PREPARE_FOR_SUBMISSION"))
    }

    @Test("releasedAppStoreStates accepts modern appVersionState tokens (#362)")
    internal func releasedStatesAcceptsModernTokens() {
        // ASC 3.3 renamed `appStoreState` → `appVersionState`, renaming two
        // released tokens (the others are identical in both enums). A released
        // app reporting the MODERN token must still compute hasReleasedVersion.
        #expect(MetadataRemoteState.releasedAppStoreStates.contains("READY_FOR_DISTRIBUTION"))
        #expect(MetadataRemoteState.releasedAppStoreStates.contains("PROCESSING_FOR_DISTRIBUTION"))
        // Unchanged-in-both released tokens stay present.
        #expect(MetadataRemoteState.releasedAppStoreStates.contains("PENDING_APPLE_RELEASE"))
        #expect(MetadataRemoteState.releasedAppStoreStates.contains("PENDING_DEVELOPER_RELEASE"))
        #expect(MetadataRemoteState.releasedAppStoreStates.contains("REPLACED_WITH_NEW_VERSION"))
        // PREPARE_FOR_SUBMISSION is a first-submission state in BOTH enums.
        #expect(!MetadataRemoteState.releasedAppStoreStates.contains("PREPARE_FOR_SUBMISSION"))
    }
}
