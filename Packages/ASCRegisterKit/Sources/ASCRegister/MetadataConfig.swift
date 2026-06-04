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
    /// The YAML `locale:` value, already in ASC form (e.g. `en-US`,
    /// `zh-Hant`). The files were authored with ASC locale codes directly.
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

// MARK: - Loading

internal enum MetadataConfigError: Error, CustomStringConvertible {
    case directoryNotFound(String)
    case appMetaNotFound(String)
    case noListings(String)
    case malformedYAML(file: String, reason: String)

    internal var description: String {
        switch self {
        case .directoryNotFound(let path): return "metadata directory not found: \(path)"
        case .appMetaNotFound(let path): return "app-meta.yaml not found: \(path)"
        case .noListings(let path): return "no <locale>/listing.yaml files under: \(path)"
        case .malformedYAML(let file, let reason): return "malformed YAML in \(file): \(reason)"
        }
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
        return MetadataConfig(appMeta: appMeta, listings: listings)
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
            let locale = str(dict["locale"]) ?? entry.lastPathComponent
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
        return trimmed.isEmpty ? nil : raw
    }
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
