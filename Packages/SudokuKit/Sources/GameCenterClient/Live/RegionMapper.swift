// RegionMapper — heuristic classification of GameKit errors as "this
// device's region does not support Game Center" rather than a transient
// auth failure (design.md §How.3.4 末段).
//
// Why a heuristic, not an authoritative API: Apple does not publish a
// stable list of GC-unavailable regions, and the underlying `GKError`
// codes overlap with "not authenticated"-style failures. The pattern we
// rely on:
//
//   GKError.gameUnrecognized OR GKError.notSupported, observed in a
//   region we've historically seen reject GC (e.g. mainland China for
//   anonymous accounts), → `.unavailableInRegion`.
//
// Other inputs (e.g. `cancelled`, `notAuthenticated`) are NOT region
// signals — they are returned as their natural mapping.
//
// The mapper is pure: it takes a (rawCode, region) pair and returns a
// classification. The live `GKAuthDriver` calls it after extracting the
// `GKError.Code.rawValue` and the device's `Locale.current.region?.identifier`.

import Foundation

public enum GameCenterRegionClassification: Sendable, Equatable {
    case ok
    case unavailableInRegion
}

public enum RegionMapper {

    /// Region identifiers historically observed to fail GameKit handshake
    /// without sandbox or paid Apple ID — kept narrow on purpose; we
    /// prefer false negatives (showing "retry") over false positives
    /// (hiding the leaderboard from users who could actually use it).
    static let knownRestrictedRegions: Set<String> = ["CN"]

    /// `gkErrorRawValue` mirrors `GKError.Code.rawValue` — using the raw
    /// `Int` rather than the enum keeps RegionMapper free of GameKit
    /// imports (the comparison constants live alongside the doc comments).
    public static func classify(
        gkErrorRawValue: Int?,
        region: String?
    ) -> GameCenterRegionClassification {
        guard let raw = gkErrorRawValue else { return .ok }
        // Per `GKErrorCode`:
        //   gameUnrecognized = 15
        //   notSupported     = 16
        let isRegionSignalCode = (raw == 15 || raw == 16)
        guard isRegionSignalCode else { return .ok }
        guard let region else {
            // No region info → conservatively classify as unavailable,
            // since both the error codes above are themselves "GC will
            // not work" signals; the region check only sharpens which
            // bucket they fall into.
            return .unavailableInRegion
        }
        if knownRestrictedRegions.contains(region) {
            return .unavailableInRegion
        }
        // Outside known-restricted regions, the same error codes most
        // often mean "configuration issue" / "transient": leave as .ok
        // so the auth flow surfaces the underlying error to the user.
        return .ok
    }
}
