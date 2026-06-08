// Screenshot upload orchestration + pure discovery/mapping for the
// `metadata screenshots` command (issue: ASCRegister screenshot upload).
//
// Pure types here (discovery of committed PNGs + device→displayType map) carry
// no I/O so the plan/grouping is unit-testable without a live API. The
// `ASCRegisterCLI.applyScreenshots` orchestration (in main.swift) drives the
// reserve→PUT→commit sequence using these + ASCClient+Screenshots.

import Foundation

// MARK: - device dir → ASC screenshotDisplayType

/// Maps a committed screenshot `<device>` directory segment to the ASC
/// `screenshotDisplayType` enum + the `--platform` family it belongs to.
///
/// DisplayType values verified 2026-06-05 (fastlane spaceship DisplayType +
/// Apple ASC API). NOTE: Apple has not published distinct enums for the newest
/// device sizes, so the API reuses the previous-generation token:
///   - iPhone 6.9" (1290×2796) → `APP_IPHONE_67`        (no 6.9" enum exists)
///   - iPad 13"    (2064×2752) → `APP_IPAD_PRO_3GEN_129` (no 13" enum; reuses 12.9")
///   - Mac                      → `APP_DESKTOP`
internal enum ScreenshotDevice: String, CaseIterable, Sendable {
    case iphone69 = "iphone-6.9"
    case ipad13 = "ipad-13"
    case mac

    /// The ASC `screenshotDisplayType` enum token for this device class.
    internal var displayType: String {
        switch self {
        case .iphone69: return "APP_IPHONE_67"
        case .ipad13:   return "APP_IPAD_PRO_3GEN_129"
        case .mac:      return "APP_DESKTOP"
        }
    }

    /// Which `--platform` family this device belongs to. iPhone + iPad are iOS;
    /// Mac is macOS.
    internal var platform: MetadataPlatform {
        switch self {
        case .iphone69, .ipad13: return .ios
        case .mac:               return .macos
        }
    }

    /// Whether this device is in scope for a `--platform` filter (`all` matches
    /// every device).
    internal func inScope(of filter: MetadataPlatform) -> Bool {
        filter == .all || filter == platform
    }
}

// MARK: - committed PNG discovery (pure)

/// One committed screenshot PNG to upload, with its resolved ASC target.
internal struct ScreenshotAsset: Sendable, Equatable {
    internal let path: String
    internal let fileName: String       // e.g. "01-home.png"
    internal let device: ScreenshotDevice
    internal let locale: String         // repo locale segment, e.g. "en"

    internal var displayType: String { device.displayType }
}

internal enum ScreenshotDiscovery {

    /// Walk `screenshots/<app>/<device>/<locale>/NN-screen.png` under
    /// `screenshotsDir`, returning every PNG in scope for `platform` + `locale`,
    /// sorted by (device, fileName) for a stable plan order. Pure-ish: the only
    /// I/O is the directory listing (so a test can point it at a temp tree). A
    /// device directory whose name is not a known `ScreenshotDevice` is skipped
    /// (forward-compatible — a new device dir doesn't crash the scan).
    ///
    /// `localeFilter` is the REPO locale segment (the committed tree uses `en`,
    /// not `en-US`); matched verbatim against the `<locale>` dir name.
    internal static func discover(
        screenshotsDir: String,
        app: String,
        platform: MetadataPlatform,
        localeFilter: String
    ) -> [ScreenshotAsset] {
        let fileManager = FileManager.default
        let appRoot = URL(fileURLWithPath: screenshotsDir).appendingPathComponent(app)
        var out: [ScreenshotAsset] = []

        for device in ScreenshotDevice.allCases where device.inScope(of: platform) {
            let localeDir = appRoot
                .appendingPathComponent(device.rawValue)
                .appendingPathComponent(localeFilter)
            let entries = (try? fileManager.contentsOfDirectory(
                at: localeDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            for entry in entries where entry.pathExtension.lowercased() == "png" {
                out.append(ScreenshotAsset(
                    path: entry.path,
                    fileName: entry.lastPathComponent,
                    device: device,
                    locale: localeFilter
                ))
            }
        }
        return out.sorted {
            ($0.device.rawValue, $0.fileName) < ($1.device.rawValue, $1.fileName)
        }
    }
}

// MARK: - set/screenshot remote indexing (pure)

/// One remote screenshot already attached to a set, as the orchestration needs
/// it for idempotency decisions (#370). `assetDeliveryState` distinguishes a
/// truly-present COMPLETE asset from a half-finished reservation; the optional
/// `sourceFileChecksum` (ASC's MD5 of the bytes it holds) lets the caller detect
/// content drift against the local file.
internal struct ScreenshotRemoteState: Sendable, Equatable {
    internal let id: String
    internal let assetDeliveryState: String?
    internal let sourceFileChecksum: String?

    /// ASC reports a fully-uploaded, verified asset as `COMPLETE`. Any other
    /// state (AWAITING_UPLOAD, UPLOAD_COMPLETE-but-not-verified, FAILED, or a
    /// missing state) means a prior reserve/PUT/commit did not finish → the
    /// asset must be re-uploaded, not skipped.
    internal var isComplete: Bool { assetDeliveryState == "COMPLETE" }
}

/// Helpers to read the `listScreenshotSets` GET into the lookups the
/// orchestration needs: the set id for a displayType, and per-file remote state
/// (delivery state + checksum) for the idempotency decision. Pure so the logic
/// is unit-testable from a canned response.
internal enum ScreenshotSetIndex {

    /// `appScreenshotSet id → (fileName → remote state)`. Built from the
    /// side-loaded `appScreenshots` plus each set's relationship pointers, so
    /// the orchestration can decide per file: skip (COMPLETE + same checksum),
    /// or evict-and-re-upload (non-COMPLETE, or checksum drift) (#370).
    internal static func screenshotsBySetId(
        _ collection: APICollectionWithIncluded
    ) -> [String: [String: ScreenshotRemoteState]] {
        let shotsById = Dictionary(
            uniqueKeysWithValues: collection.included
                .filter { $0.type == "appScreenshots" }
                .map { ($0.id, $0) }
        )
        var out: [String: [String: ScreenshotRemoteState]] = [:]
        for set in collection.data where set.type == "appScreenshotSets" {
            let shotIds = collection.relationships[set.id]?["appScreenshots"] ?? []
            var byName: [String: ScreenshotRemoteState] = [:]
            for shotId in shotIds {
                guard let shot = shotsById[shotId],
                      let name = shot.attributes["fileName"] else { continue }
                byName[name] = ScreenshotRemoteState(
                    id: shot.id,
                    assetDeliveryState: shot.attributes["assetDeliveryState"],
                    sourceFileChecksum: shot.attributes["sourceFileChecksum"]
                )
            }
            out[set.id] = byName
        }
        return out
    }

    /// `screenshotDisplayType → appScreenshotSet id` from a `listScreenshotSets`
    /// response. The displayType lives in each primary set resource's attributes.
    internal static func setIdsByDisplayType(
        _ collection: APICollectionWithIncluded
    ) -> [String: String] {
        var out: [String: String] = [:]
        for set in collection.data where set.type == "appScreenshotSets" {
            if let displayType = set.attributes["screenshotDisplayType"] {
                out[displayType] = set.id
            }
        }
        return out
    }
}
