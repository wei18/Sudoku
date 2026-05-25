// UserFacingError — user-presentable error projection (issue #67 / M10).
//
// The design.md §How.6.2 per-source taxonomy (NetworkError / AccountError /
// CloudKitOpError / PersistenceError / GeneratorError / GameCenterError)
// stays internal — call sites still throw / catch those typed errors when
// available. `UserFacingError` is the *collapsed* projection that the UI
// renders and that the user-facing copy in `Localizable.xcstrings` keys to.
//
// Five buckets per issue spec:
//   - `networkUnavailable`        — offline / timeout / transient network
//   - `iCloudSignedOut`           — not signed in / signed out mid-session
//   - `persistencePermanent`      — disk-full / cache corrupt / schema drift
//   - `gameCenterUnauthenticated` — GameKit auth missing or denied
//   - `unknown`                   — safety net for unclassified throws
//
// Underlying error details (CKError codes, NSError domains, stack-relevant
// payloads) do NOT travel on this type — they go through `ErrorReporter`'s
// `underlying` parameter into OSLog / Telemetry where engineers can see
// them. UI never strings-interpolates a raw `Error`; it switches on this
// enum and pulls a localized key per case.

public import Foundation

public enum UserFacingError: Sendable, Equatable, Hashable {
    case networkUnavailable
    case iCloudSignedOut
    case persistencePermanent
    case gameCenterUnauthenticated
    case unknown

    /// Short stable identifier used as the `code` field on the routed
    /// `TelemetryEvent.errorOccurred(...)`. Distinct from the localized
    /// `messageKey` — engineering OSLog filtering uses this token, while
    /// the UI renders `messageKey`.
    public var rawCode: String {
        switch self {
        case .networkUnavailable: return "networkUnavailable"
        case .iCloudSignedOut: return "iCloudSignedOut"
        case .persistencePermanent: return "persistencePermanent"
        case .gameCenterUnauthenticated: return "gameCenterUnauthenticated"
        case .unknown: return "unknown"
        }
    }

    /// `Localizable.xcstrings` key for the user-visible body copy. Keys
    /// follow design.md §How.6.9: `error.<source>.<case>.body` family. We
    /// collapse `<source>` to `userFacing` since the enum has already
    /// projected the source dimension away.
    public var messageKey: String {
        "error.userFacing.\(rawCode).body"
    }

    /// Best-effort classifier — maps a caught `any Error` into the closest
    /// user-facing bucket. Conservative by default: anything unrecognised
    /// returns `.unknown` rather than mis-classifying. Inspect by NSError
    /// domain + code to avoid hard-importing CloudKit / GameKit here
    /// (AppComposition already brings them transitively, but keeping the
    /// classifier domain-string based makes it portable to test fakes that
    /// throw plain `NSError`s).
    public static func classify(_ error: any Error) -> UserFacingError {
        // Already-classified errors pass through.
        if let alreadyFacing = error as? UserFacingError {
            return alreadyFacing
        }
        let nsError = error as NSError
        switch nsError.domain {
        case "CKErrorDomain":
            return classifyCKError(code: nsError.code)
        case "GKErrorDomain":
            // Per GameKit: 6 = .notAuthenticated; treat every GKError as
            // unauthenticated for UI purposes (engineering OSLog carries
            // the specific code).
            return .gameCenterUnauthenticated
        case NSURLErrorDomain:
            return .networkUnavailable
        case NSCocoaErrorDomain:
            // 640 = NSFileWriteOutOfSpaceError; 259/260/261 = read corrupt
            // / not-found family. All map to persistencePermanent for UX.
            return .persistencePermanent
        default:
            return .unknown
        }
    }

    /// CKError code → UserFacingError. Codes taken from
    /// `CKError.Code` raw values (Apple-stable since iOS 8).
    private static func classifyCKError(code: Int) -> UserFacingError {
        switch code {
        case 4 /* .networkUnavailable */,
             3 /* .networkFailure */,
             14 /* .serviceUnavailable */,
             7 /* .requestRateLimited */:
            return .networkUnavailable
        case 9 /* .notAuthenticated */,
             25 /* .accountTemporarilyUnavailable */:
            return .iCloudSignedOut
        case 27 /* .zoneNotFound */,
             16 /* .unknownItem */,
             26 /* .quotaExceeded */:
            return .persistencePermanent
        default:
            return .unknown
        }
    }
}
