// Platform-aware version selection for the `metadata` commands.
//
// One ASC app holds a SEPARATE `appStoreVersion` per platform (IOS + MAC_OS —
// Sudoku has both). The metadata tool previously picked a single editable
// version, so `apply` pushed version-loc copy to only one platform and
// `set-version` renamed only one. These pure types group the fetched versions
// by platform and pick the editable one for each, so the command can fan out
// across every platform in scope.
//
// Pure — no I/O. Fed the decoded version list so the grouping + editable guard
// is unit-testable without a live API. Reuses `SetVersionResolver.choose`
// (ASCClient+Metadata.swift) per platform group, so the single-platform
// disambiguation / locked / none-editable verdicts are unchanged.

import Foundation

// MARK: - `--platform` filter

/// The `--platform` filter for the metadata commands. `all` (the default) makes
/// `apply` / `set-version` reconcile EVERY editable platform version in a single
/// run, fixing the defect where only one platform's version was touched.
internal enum MetadataPlatform: String, CaseIterable, Sendable {
    case ios
    case macos
    case all

    /// The ASC `platform` attribute tokens this filter selects. `all` matches
    /// every known platform token (and, defensively, any unknown token — see
    /// `matches`).
    internal var ascTokens: Set<String> {
        switch self {
        case .ios:   return ["IOS"]
        case .macos: return ["MAC_OS"]
        case .all:   return ["IOS", "MAC_OS", "TV_OS"]
        }
    }

    /// Whether an ASC version with `platformToken` is in scope. `all` accepts
    /// anything (including platforms Apple may add later); `ios`/`macos` match
    /// only their own token.
    internal func matches(platformToken: String) -> Bool {
        if self == .all { return true }
        return ascTokens.contains(platformToken)
    }
}

// MARK: - Per-platform resolver

/// Picks the editable `appStoreVersion` to operate on FOR EACH platform in
/// scope. Reuses `SetVersionResolver.choose` per platform group, so the
/// single-platform verdicts are unchanged; this only adds the per-platform
/// fan-out.
internal enum PlatformVersionResolver {

    /// One platform's resolution outcome.
    internal struct Resolved: Sendable, Equatable {
        internal let platform: String           // ASC token, e.g. "IOS"
        internal let version: SetVersionResolver.Version
    }

    /// One platform that had no editable version (warn, don't crash).
    internal struct Skipped: Sendable, Equatable {
        internal let platform: String
        internal let reason: String
    }

    internal struct Outcome: Sendable, Equatable {
        internal let resolved: [Resolved]
        internal let skipped: [Skipped]
    }

    /// A version carrying its platform token (the decoded ASC shape).
    internal struct PlatformVersion: Sendable, Equatable {
        internal let platform: String
        internal let version: SetVersionResolver.Version
        internal init(platform: String, version: SetVersionResolver.Version) {
            self.platform = platform
            self.version = version
        }
    }

    /// Group `versions` by platform, keep only the platforms `filter` selects,
    /// and run `SetVersionResolver.choose` per group. A platform whose group has
    /// no editable version is reported in `skipped` (warn, not error) so the
    /// other platforms still run — matching the "missing editable version per
    /// platform → warn not crash" requirement.
    ///
    /// `versionFilter` (the optional `--version` *string* used to disambiguate)
    /// is threaded through to each group's `choose`.
    internal static func resolve(
        versions: [PlatformVersion],
        filter: MetadataPlatform,
        versionFilter: String?
    ) -> Outcome {
        // Group by platform token, preserving first-seen order for stable output.
        var order: [String] = []
        var groups: [String: [SetVersionResolver.Version]] = [:]
        for entry in versions where filter.matches(platformToken: entry.platform) {
            if groups[entry.platform] == nil { order.append(entry.platform) }
            groups[entry.platform, default: []].append(entry.version)
        }

        var resolved: [Resolved] = []
        var skipped: [Skipped] = []
        for platform in order {
            let group = groups[platform] ?? []
            switch SetVersionResolver.choose(versions: group, versionFilter: versionFilter) {
            case .success(let chosen):
                resolved.append(Resolved(platform: platform, version: chosen))
            case .failure(let error):
                skipped.append(Skipped(platform: platform, reason: "\(error)"))
            }
        }
        return Outcome(resolved: resolved, skipped: skipped)
    }
}
