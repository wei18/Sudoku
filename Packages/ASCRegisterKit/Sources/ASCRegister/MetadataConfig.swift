// MetadataConfig — desired App Store listing metadata, loaded from the
// committed YAML files (issue #310).
//
// Source files (docs/app-store/metadata/, see that dir's README for the
// asymmetric multi-app layout):
//   - <subtree>/<locale>/listing.yaml — per-locale storefront copy.
//   - <subtree>/app-meta.yaml         — per-app global fields
//                                       (copyright / categories / review info).
// where <subtree> is "" (top level) for Sudoku and "minesweeper/" for MS.
//
// These map onto the ASC API as (plan §2):
//   listing.name / subtitle / privacy_policy_url → appInfoLocalizations
//   listing.{description,keywords,promotional_text,whats_new,
//            marketing_url,support_url}          → appStoreVersionLocalizations
//   app-meta.{primary,secondary}_category + sub  → appInfos category rels
//
// YAML decoding uses Yams (issue #310 dep) — the `|` block scalars in
// description / whats_new contain embedded blank lines that a hand-rolled
// reader would mishandle.

// swiftlint:disable file_length
// WHY: the field-length validation table + validator (#310) pushed this past
// the 400-line cap. Splitting into a `+Validation` file is the eventual
// cleanup, but the #310 hardening was scoped to not add new source files
// (parallel-agent file-domain isolation). Mirrors ASCClient.swift's directive.

import Foundation
import Yams

// MARK: - App selector

/// Which app's metadata subtree to read. Selected by the `--app` flag.
internal enum MetadataApp: String, Sendable, CaseIterable {
    case sudoku
    case minesweeper

    /// Path component appended to `--metadata-dir` to reach this app's tree.
    /// Sudoku lives at the top level (the original single-app tree);
    /// Minesweeper in a `minesweeper/` subtree (metadata/README asymmetric
    /// layout decision, #236).
    internal var subtreeComponent: String {
        switch self {
        case .sudoku:      return ""
        case .minesweeper: return "minesweeper"
        }
    }
}

// MARK: - Value types

/// One locale's storefront listing — the union of the two ASC localization
/// resources this fans out to. `nil` fields are absent in the YAML and are
/// skipped (not pushed as empty) during reconcile.
internal struct ListingLocale: Sendable, Equatable {
    /// The canonical ASC locale code (e.g. `en-US`, `zh-Hant`, `ko`, `th`).
    /// The YAML `locale:` value is mapped to this at load time via
    /// `MetadataConfig.ascLocaleCode(forRepoCode:)` (issue #322), so repo
    /// codes like `es` / `ko-KR` reach the ASC API as their canonical form.
    internal let locale: String

    // → appInfoLocalizations
    internal let name: String?
    internal let subtitle: String?
    internal let privacyPolicyUrl: String?

    // → appStoreVersionLocalizations
    internal let description: String?
    internal let keywords: String?
    internal let promotionalText: String?
    internal let whatsNew: String?
    internal let marketingUrl: String?
    internal let supportUrl: String?
}

/// Per-app global metadata from `app-meta.yaml`. Only the fields the
/// `metadata` command pushes (categories) are modeled as structured values;
/// the rest (copyright, review_information) are carried opaquely for `plan`
/// display but are out of the v1 push scope (plan §5: review info is
/// per-submission / user-owned; copyright is a single PATCH we include).
internal struct AppMeta: Sendable, Equatable {
    /// `app:` discriminator (`sudoku` / `minesweeper`).
    internal let app: String
    /// Numeric ASC App ID, if the app exists in ASC (`apple_id:`). MS omits
    /// it (no ASC record yet) → `nil`.
    internal let appleId: String?
    internal let copyright: String?
    internal let categories: Categories

    /// ASC App Information categories. Each is a top-level genre plus up to
    /// two sub-categories. The human labels ("Games", "Puzzle") map to ASC
    /// `appCategories` id tokens via `MetadataConfig.ascCategoryId`.
    internal struct Categories: Sendable, Equatable {
        internal let primary: String?
        internal let primaryFirstSub: String?
        internal let primarySecondSub: String?
        internal let secondary: String?
        internal let secondaryFirstSub: String?
        internal let secondarySecondSub: String?
    }
}

/// The full desired metadata for one app: its global fields + every locale.
internal struct MetadataConfig: Sendable, Equatable {
    internal let appMeta: AppMeta
    /// Keyed by ASC locale code, in a stable display order.
    internal let listings: [ListingLocale]
}

// MARK: - Field length limits (single source of truth)

/// App Store Connect per-locale character caps for the listing fields the
/// `metadata` command pushes. ASC enforces these server-side: an over-length
/// value is rejected mid-`apply` with
/// `409 ENTITY_ERROR.ATTRIBUTE.INVALID.TOO_LONG`, leaving a PARTIAL apply
/// (issue #310). We pre-flight against this table at `load()` so `plan` fails
/// loud before any mutation.
///
/// Limits verified against Apple's official docs (retrieved 2026-06-04):
///   - "App Store Version Localizations" (App Store Connect API reference)
///     <https://developer.apple.com/documentation/appstoreconnectapi/app-store-version-localizations>
///   - "Creating Your Product Page" (App Store)
///     <https://developer.apple.com/app-store/product-page/>
/// `name` / `subtitle` are `appInfoLocalizations` attributes; the rest are
/// `appStoreVersionLocalizations` attributes. The caps match the App Store
/// product-page limits. Counts are user-perceived characters — Swift
/// `String.count` (grapheme clusters) is the closest match to how ASC counts
/// (mirrors the live `subtitle cannot be longer than 30` rejection).
///
/// Single source of truth; `MetadataConfig.validateFieldLengths` is the only
/// consumer.
internal enum MetadataFieldLimits {
    internal static let name = 30
    internal static let subtitle = 30
    internal static let keywords = 100
    internal static let promotionalText = 170
    internal static let description = 4000
    internal static let whatsNew = 4000
}

// MARK: - Loading

internal enum MetadataConfigError: Error, CustomStringConvertible {
    case directoryNotFound(String)
    case appMetaNotFound(String)
    case noListings(String)
    case malformedYAML(file: String, reason: String)
    case unknownLocale(code: String, file: String)
    /// One or more listing fields exceed the ASC character cap. Carries EVERY
    /// violation (not just the first) so a single `plan` run surfaces them all.
    case fieldsTooLong([FieldLengthViolation])

    internal var description: String {
        switch self {
        case .directoryNotFound(let path): return "metadata directory not found: \(path)"
        case .appMetaNotFound(let path): return "app-meta.yaml not found: \(path)"
        case .noListings(let path): return "no <locale>/listing.yaml files under: \(path)"
        case .malformedYAML(let file, let reason): return "malformed YAML in \(file): \(reason)"
        case .unknownLocale(let code, let file):
            return "locale '\(code)' in \(file) has no known App Store Connect locale code "
                + "(MetadataConfig.ascLocaleCode); add it to the map or fix the YAML"
        case .fieldsTooLong(let violations):
            let lines = violations.map { "  - \($0.description)" }.joined(separator: "\n")
            return "ASC field length validation failed (\(violations.count) "
                + "violation(s)) — fix the YAML before apply:\n\(lines)"
        }
    }
}

/// One over-length listing field, naming app + locale + field + actual length
/// + the limit (issue #310 — fail loud, all at once).
internal struct FieldLengthViolation: Sendable, Equatable, CustomStringConvertible {
    internal let app: String
    internal let locale: String
    internal let field: String
    internal let actual: Int
    internal let limit: Int

    internal var description: String {
        "[\(app)/\(locale)] \(field) is \(actual) characters, limit is \(limit)"
    }
}

extension MetadataConfig {

    /// Load the full metadata config for `app` from `metadataDir`
    /// (default `docs/app-store/metadata`). Reads `app-meta.yaml` + every
    /// `<locale>/listing.yaml` under the app's subtree.
    internal static func load(
        app: MetadataApp,
        metadataDir: String
    ) throws -> MetadataConfig {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: metadataDir)
        let subtree = app.subtreeComponent.isEmpty
            ? root
            : root.appendingPathComponent(app.subtreeComponent)

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: subtree.path, isDirectory: &isDir), isDir.boolValue else {
            throw MetadataConfigError.directoryNotFound(subtree.path)
        }

        let appMeta = try loadAppMeta(subtree: subtree)
        let listings = try loadListings(subtree: subtree)
        guard !listings.isEmpty else {
            throw MetadataConfigError.noListings(subtree.path)
        }
        let config = MetadataConfig(appMeta: appMeta, listings: listings)
        // Pre-flight ASC length caps NOW, at load — which runs during `plan`
        // (main: load@359 → reconcile@402 → apply@409), so an over-length
        // field fails loud before any mutating call instead of leaving a
        // PARTIAL apply (issue #310).
        try config.validateFieldLengths(app: app.rawValue)
        return config
    }

    private static func loadAppMeta(subtree: URL) throws -> AppMeta {
        let file = subtree.appendingPathComponent("app-meta.yaml")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            throw MetadataConfigError.appMetaNotFound(file.path)
        }
        let node: Any?
        do {
            node = try Yams.load(yaml: text)
        } catch {
            throw MetadataConfigError.malformedYAML(file: file.path, reason: "\(error)")
        }
        guard let dict = node as? [String: Any] else {
            throw MetadataConfigError.malformedYAML(file: file.path, reason: "top level is not a mapping")
        }
        let cats = AppMeta.Categories(
            primary: str(dict["primary_category"]),
            primaryFirstSub: str(dict["primary_first_sub_category"]),
            primarySecondSub: str(dict["primary_second_sub_category"]),
            secondary: str(dict["secondary_category"]),
            secondaryFirstSub: str(dict["secondary_first_sub_category"]),
            secondarySecondSub: str(dict["secondary_second_sub_category"])
        )
        return AppMeta(
            app: str(dict["app"]) ?? "",
            appleId: str(dict["apple_id"]),
            copyright: str(dict["copyright"]),
            categories: cats
        )
    }

    private static func loadListings(subtree: URL) throws -> [ListingLocale] {
        let fileManager = FileManager.default
        let entries = (try? fileManager.contentsOfDirectory(
            at: subtree,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var out: [ListingLocale] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else { continue }
            // Skip the sibling app subtree (e.g. `minesweeper/`) so the Sudoku
            // top-level load does not recurse into the MS tree.
            if MetadataApp.allCases.contains(where: { $0.subtreeComponent == entry.lastPathComponent }) {
                continue
            }
            let listingFile = entry.appendingPathComponent("listing.yaml")
            guard let text = try? String(contentsOf: listingFile, encoding: .utf8) else { continue }
            let node: Any?
            do {
                node = try Yams.load(yaml: text)
            } catch {
                throw MetadataConfigError.malformedYAML(file: listingFile.path, reason: "\(error)")
            }
            guard let dict = node as? [String: Any] else {
                throw MetadataConfigError.malformedYAML(
                    file: listingFile.path, reason: "top level is not a mapping"
                )
            }
            // The YAML `locale:` is authoritative; fall back to dir name.
            let repoLocale = str(dict["locale"]) ?? entry.lastPathComponent
            // Map the repo code to the canonical ASC code (issue #322) so
            // reconcile matches the localizations ASC already holds. An
            // unknown code fails loudly rather than mis-mapping.
            guard let locale = ascLocaleCode(forRepoCode: repoLocale) else {
                throw MetadataConfigError.unknownLocale(code: repoLocale, file: listingFile.path)
            }
            out.append(ListingLocale(
                locale: locale,
                name: str(dict["name"]),
                subtitle: str(dict["subtitle"]),
                privacyPolicyUrl: str(dict["privacy_policy_url"]),
                description: str(dict["description"]),
                keywords: str(dict["keywords"]),
                promotionalText: str(dict["promotional_text"]),
                whatsNew: str(dict["whats_new"]),
                marketingUrl: str(dict["marketing_url"]),
                supportUrl: str(dict["support_url"])
            ))
        }
        return out
    }

    /// Coerce a YAML scalar to a non-empty `String?`. YAML `null` (decoded by
    /// Yams as `NSNull` / Swift `nil`) and empty strings collapse to `nil`,
    /// so an absent field is never pushed as empty.
    private static func str(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        let raw: String
        if let stringValue = value as? String {
            raw = stringValue
        } else {
            raw = "\(value)"
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip a SINGLE trailing newline so the SENT payload length matches the
        // validated/counted length. YAML `|` block scalars carry a terminating
        // `\n` that ASC neither counts nor stores; sending it made a 170-char
        // field arrive as 171 → live 409 TOO_LONG (obs 3804 / #333). See
        // ascCharacterCount, which strips the same way for validation.
        return trimmed.isEmpty ? nil : strippingSingleTrailingNewline(raw)
    }
}

// MARK: - Field length validation (issue #310)

extension MetadataConfig {

    /// Pre-flight every listing field against `MetadataFieldLimits`, collecting
    /// ALL violations (never stop at the first) and naming
    /// app+locale+field+actual+limit. Throws `MetadataConfigError.fieldsTooLong`
    /// if any field is over its ASC cap; otherwise returns silently.
    ///
    /// This runs at `load()` time, i.e. during `plan`, before any apply
    /// mutation — so an over-length value is caught here instead of by ASC's
    /// `409 TOO_LONG` mid-apply (which leaves a partial apply).
    internal func validateFieldLengths(app: String) throws {
        var violations: [FieldLengthViolation] = []
        for listing in listings {
            check(listing.name, "name", MetadataFieldLimits.name, app, listing.locale, &violations)
            check(listing.subtitle, "subtitle", MetadataFieldLimits.subtitle, app, listing.locale, &violations)
            check(listing.keywords, "keywords", MetadataFieldLimits.keywords, app, listing.locale, &violations)
            check(
                listing.promotionalText, "promotionalText",
                MetadataFieldLimits.promotionalText, app, listing.locale, &violations
            )
            check(
                listing.description, "description",
                MetadataFieldLimits.description, app, listing.locale, &violations
            )
            check(listing.whatsNew, "whatsNew", MetadataFieldLimits.whatsNew, app, listing.locale, &violations)
        }
        guard violations.isEmpty else {
            throw MetadataConfigError.fieldsTooLong(violations)
        }
    }

    /// Count a field the way ASC counts and append a violation if over limit.
    private func check(
        _ value: String?,
        _ field: String,
        _ limit: Int,
        _ app: String,
        _ locale: String,
        _ violations: inout [FieldLengthViolation]
    ) {
        guard let value else { return }
        let count = Self.ascCharacterCount(value)
        if count > limit {
            violations.append(FieldLengthViolation(
                app: app, locale: locale, field: field, actual: count, limit: limit
            ))
        }
    }

    /// The character count ASC applies to a listing field.
    ///
    /// ASC counts user-perceived characters; Swift `String.count` (grapheme
    /// clusters) is the closest match. We strip a SINGLE trailing newline
    /// first: YAML `|` block scalars (description / whats_new / promotional
    /// text) carry a terminating `\n` that ASC does NOT count — a live apply
    /// rejected `promotional_text` at 171 that was only 170 once the trailing
    /// newline was removed. We trim just the one trailing newline (not all
    /// whitespace) so internal and leading whitespace still count, matching
    /// ASC's own counting.
    internal static func ascCharacterCount(_ value: String) -> Int {
        strippingSingleTrailingNewline(value).count
    }

    /// Strip a SINGLE trailing newline (`\r\n` is one grapheme cluster in Swift,
    /// so one `removeLast()` strips `\n`/`\r`/`\r\n` alike — only the one trailing
    /// terminator, never internal/leading whitespace). YAML `|` block scalars
    /// carry a terminating newline ASC neither counts nor stores; the SAME strip
    /// must apply to both the payload `str(...)` sends and the `ascCharacterCount`
    /// validation so send-length and counted-length agree.
    internal static func strippingSingleTrailingNewline(_ value: String) -> String {
        var text = value
        if let last = text.last, last.isNewline {
            text.removeLast()
        }
        return text
    }
}

// MARK: - Locale code mapping (issue #322)

extension MetadataConfig {

    /// Map a repo listing-folder locale code to the canonical App Store
    /// Connect locale shortcode used by `appInfoLocalizations` /
    /// `appStoreVersionLocalizations` (the `locale` attribute).
    ///
    /// The Sudoku listing.yaml files were authored with short codes
    /// (`es` / `ko` / `th`); the Minesweeper ones with region-qualified codes
    /// (`es-ES` / `ko-KR` / `th-TH`). Neither set fully matches what ASC
    /// already holds, so `plan` showed spurious CREATE actions that would
    /// create duplicate / wrong-locale localizations on `apply` (issue #322).
    ///
    /// Canonical ASC codes verified against Apple's official reference,
    /// "App Store localizations" (App Store Connect Help, retrieved 2026-06-04):
    /// <https://developer.apple.com/help/app-store-connect/reference/app-store-localizations/>
    ///   - Spanish (Spain)        → `es-ES`
    ///   - Korean                 → `ko`     (NOT `ko-KR`)
    ///   - Thai                   → `th`     (NOT `th-TH`)
    ///   - Japanese               → `ja`
    ///   - Chinese (Simplified)   → `zh-Hans`
    ///   - Chinese (Traditional)  → `zh-Hant`
    ///   - English (U.S.)         → `en-US`
    ///
    /// NOTE: this is deliberately separate from `Config.ascLocaleCode`
    /// (issue #31), which serves the Game Center / xcstrings path and maps
    /// `ko → ko-KR` / `th → th-TH`. The App Store metadata catalog uses the
    /// bare `ko` / `th` forms, so the two maps must not be merged.
    ///
    /// The table is restricted to the codes actually present across the
    /// committed listing.yaml files. An unmapped code returns `nil` so the
    /// caller fails loudly (`MetadataConfigError.unknownLocale`) rather than
    /// silently dropping or mis-mapping a localization.
    internal static func ascLocaleCode(forRepoCode repoCode: String) -> String? {
        repoToASCLocale[repoCode]
    }

    /// Repo listing-folder code → canonical ASC locale code. Restricted to the
    /// codes present across the committed listing.yaml files (issue #322).
    private static let repoToASCLocale: [String: String] = [
        // Already-canonical codes (pass through unchanged).
        "en-US": "en-US",
        // The committed screenshots tree (#311) uses the bare `en` segment while
        // listing.yaml uses `en-US`; both resolve to the ASC `en-US` locale.
        "en": "en-US",
        "ja": "ja",
        "zh-Hans": "zh-Hans",
        "zh-Hant": "zh-Hant",
        "es-ES": "es-ES",
        // Sudoku short codes → canonical ASC codes.
        "es": "es-ES",
        "ko": "ko",
        "th": "th",
        // Minesweeper region-qualified codes ASC does NOT use → canonical.
        "ko-KR": "ko",
        "th-TH": "th",
    ]
}

// MARK: - Category id mapping

extension MetadataConfig {

    /// Map a human ASC category label to its ASC `appCategories` id token.
    ///
    /// ASC category ids are SCREAMING_SNAKE enums. Top-level genres are the
    /// genre name (`GAMES`); sub-categories are `GAMES_<SUB>`
    /// (e.g. `GAMES_PUZZLE`, `GAMES_BOARD`, `GAMES_FAMILY`, `GAMES_STRATEGY`).
    /// Verified against the live `listAppCategories()` GET 2026-06-04
    /// (plan §7 — see the run-pass findings).
    ///
    /// The YAML carries either the bare genre+sub split (app-meta.yaml:
    /// `primary_category: "Games"`, `primary_first_sub_category: "Puzzle"`) or,
    /// in the legacy per-listing files, a combined `"Games > Puzzle"`. This
    /// helper accepts a single label component and maps it; the combined form
    /// is split by the caller.
    internal static func ascCategoryId(genre: String, sub: String?) -> String? {
        let genreToken = genre.trimmingCharacters(in: .whitespaces).uppercased()
        guard let sub, !sub.isEmpty else { return genreToken.isEmpty ? nil : genreToken }
        let subToken = sub.trimmingCharacters(in: .whitespaces)
            .uppercased()
            .replacingOccurrences(of: " ", with: "_")
        return "\(genreToken)_\(subToken)"
    }
}
