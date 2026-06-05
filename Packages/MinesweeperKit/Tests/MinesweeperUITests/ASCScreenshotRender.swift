// ASCScreenshotRender — MS mirror of SudokuKit's ASC-screenshot render path
// (#311b). Identical machinery; differs only in `@testable import MinesweeperUI`
// (so the MS theme injected by `hostingView` carries the MS palette).
//
// See the SudokuKit copy's header for the full rationale: render real screens at
// EXACT ASC pixel size, opaque (no alpha), write submission-ready PNGs. Gated
// behind `ASC_EMIT_SCREENSHOTS=1` so a normal `swift test` never rewrites the
// committed assets.

#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI
@testable import MinesweeperUI

/// An App Store Connect screenshot device profile: the point size we host the
/// SwiftUI subtree at, plus the EXACT pixel size ASC requires. `pixels / points`
/// is an integer scale (3 for 6.9" iPhone, 2 for iPad 13" and Mac).
struct ASCProfile {
    let pointSize: CGSize
    let pixelSize: CGSize
    let sizeClass: UserInterfaceSizeClass

    /// iPhone 6.9" — ASC 1290×2796 (430×932 pt @3x).
    static let iPhone69 = ASCProfile(
        pointSize: CGSize(width: 430, height: 932),
        pixelSize: CGSize(width: 1290, height: 2796),
        sizeClass: .compact
    )
    /// iPad 13" — ASC 2064×2752 (1032×1376 pt @2x).
    static let iPad13 = ASCProfile(
        pointSize: CGSize(width: 1032, height: 1376),
        pixelSize: CGSize(width: 2064, height: 2752),
        sizeClass: .regular
    )
    /// Mac — a valid ASC Mac size 2880×1800 (1440×900 pt @2x, ≥1280×800).
    static let mac = ASCProfile(
        pointSize: CGSize(width: 1440, height: 900),
        pixelSize: CGSize(width: 2880, height: 1800),
        sizeClass: .regular
    )
}

/// `true` only when explicitly regenerating ASC screenshots.
enum ASCScreenshotEmit {
    static let isEnabled = ProcessInfo.processInfo.environment["ASC_EMIT_SCREENSHOTS"] != nil
}

/// Render `view` at the ASC profile's exact pixel size, opaque, and write a PNG
/// to `docs/app-store/screenshots/<app>/<device>/<locale>/<slot>.png`.
@MainActor
@discardableResult
func emitASCScreenshot<V: SwiftUI.View>(
    _ view: V,
    profile: ASCProfile,
    app: String,
    device: String,
    locale: String,
    slot: String,
    background: Color,
    colorScheme: ColorScheme = .light,
    localeID: Locale? = nil
) throws -> URL? {
    let composited = ZStack {
        background.ignoresSafeArea()
        view
    }
    let host = hostingView(
        composited,
        size: profile.pointSize,
        colorScheme: colorScheme,
        locale: localeID,
        sizeClass: profile.sizeClass
    )

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(profile.pixelSize.width),
        pixelsHigh: Int(profile.pixelSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 3,             // RGB, no alpha sample → no alpha channel
        hasAlpha: false,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }
    rep.size = profile.pointSize
    host.cacheDisplay(in: host.bounds, to: rep)

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        return nil
    }

    let outDir = ascScreenshotsRoot()
        .appendingPathComponent(app, isDirectory: true)
        .appendingPathComponent(device, isDirectory: true)
        .appendingPathComponent(locale, isDirectory: true)
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let outURL = outDir.appendingPathComponent("\(slot).png", isDirectory: false)
    try pngData.write(to: outURL)
    return outURL
}

/// Locate `docs/app-store/screenshots` by walking up from this source file.
private func ascScreenshotsRoot(file: StaticString = #filePath) -> URL {
    var dir = URL(fileURLWithPath: "\(file)", isDirectory: false).deletingLastPathComponent()
    let fileManager = FileManager.default
    while dir.path != "/" {
        let candidate = dir
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("app-store", isDirectory: true)
            .appendingPathComponent("screenshots", isDirectory: true)
        if fileManager.fileExists(atPath: candidate.path) { return candidate }
        dir = dir.deletingLastPathComponent()
    }
    return URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
}
#endif
