// ASCScreenshotRender — render real SwiftUI screens at EXACT App Store Connect
// pixel dimensions, opaque (no alpha), and write submission-ready PNGs.
//
// WHY this exists (the #311b approach): the snapshot harness already renders the
// real screens through `NSHostingView`. If we render at the EXACT ASC device
// pixel size onto an OPAQUE bitmap, the captured PNG *is* a submission-ready App
// Store screenshot — crisp, native, no upscale, no alpha-stripping. This
// supersedes the abandoned composite/upscale pass and fixes the #311 iPad gap
// (iPad can be rendered fresh — no baseline needed).
//
// HOW the exact pixel size is set:
//   The default `.image` snapshot strategy captures through
//   `bitmapImageRepForCachingDisplay(in:)`, which produces a rep at the NSScreen
//   *backing scale* (≈2x on a Retina dev Mac) — uncontrollable per-test. Here we
//   instead host the view at the ASC POINT size and build an `NSBitmapImageRep`
//   with EXPLICIT `pixelsWide`/`pixelsHigh` = the exact ASC pixel target, then set
//   the rep's `.size` (in points) to the ASC point size. The pixel/point ratio is
//   the effective scale, so:
//     iPhone 6.9" : 430×932 pt, 1290×2796 px  (scale 3)
//     iPad 13"    : 1032×1376 pt, 2064×2752 px (scale 2)
//     Mac         : 1440×900 pt, 2880×1800 px  (scale 2)
//   `cacheDisplay(in:to:)` rasterises the AppKit-hosted SwiftUI subtree into that
//   rep at the requested scale.
//
// HOW opacity (no alpha) is guaranteed:
//   1. The rep is created with `hasAlpha: false` — the emitted PNG carries NO
//      alpha channel (ASC rejects alpha).
//   2. The view is composited over an opaque, full-frame theme-background ZStack
//      before capture, so any transparent view region resolves to the opaque app
//      background instead of black.
//
// Test-only / additive: this path does NOT touch production rendering and does
// NOT use snapshot baselines (no record/diff). It writes REAL PNG files under
// docs/app-store/screenshots/ — gated behind `ASC_EMIT_SCREENSHOTS=1` so a normal
// `swift test` never rewrites the committed assets.
//
// #750: shared by SudokuUITests + MinesweeperUITests (previously two
// byte-drifting copies, see #713). Nothing here names a Sudoku/Minesweeper
// type — the per-app seam is the `hostingView(...)` helper each UI-test target
// still defines locally (SnapshotConfig.swift), which is where the
// `@testable import SudokuUI` / `MinesweeperUI` theme wiring actually lives.

#if canImport(AppKit)
public import AppKit
import Foundation
public import SwiftUI

/// An App Store Connect screenshot device profile: the point size we host the
/// SwiftUI subtree at, plus the EXACT pixel size ASC requires for that device
/// family. `pixels / points` is an integer scale (3 for 6.9" iPhone, 2 for iPad
/// 13" and Mac).
public struct ASCProfile: Sendable {
    let pointSize: CGSize
    let pixelSize: CGSize
    /// `default` size-class for this device family in the snapshot harness.
    let sizeClass: UserInterfaceSizeClass

    /// iPhone 6.9" — ASC 1290×2796 (430×932 pt @3x).
    public static let iPhone69 = ASCProfile(
        pointSize: CGSize(width: 430, height: 932),
        pixelSize: CGSize(width: 1290, height: 2796),
        sizeClass: .compact
    )
    /// iPad 13" — ASC 2064×2752 (1032×1376 pt @2x).
    public static let iPad13 = ASCProfile(
        pointSize: CGSize(width: 1032, height: 1376),
        pixelSize: CGSize(width: 2064, height: 2752),
        sizeClass: .regular
    )
    /// Mac — a valid ASC Mac size 2880×1800 (1440×900 pt @2x, ≥1280×800).
    public static let mac = ASCProfile(
        pointSize: CGSize(width: 1440, height: 900),
        pixelSize: CGSize(width: 2880, height: 1800),
        sizeClass: .regular
    )
}

/// `true` only when explicitly regenerating ASC screenshots. Keeps a normal
/// `swift test` from rewriting the committed PNGs.
public enum ASCScreenshotEmit {
    public static let isEnabled = ProcessInfo.processInfo.environment["ASC_EMIT_SCREENSHOTS"] != nil
}

/// Render `view` at the ASC profile's exact pixel size, opaque, and write a PNG
/// to `docs/app-store/screenshots/<app>/<device>/<locale>/<slot>.png`.
///
/// - Parameters:
///   - view:        the SwiftUI screen under capture.
///   - profile:     ASC device profile (point + pixel size).
///   - app:         output app folder (e.g. "sudoku").
///   - device:      output device folder (e.g. "iphone-6.9").
///   - locale:      output locale folder (e.g. "en").
///   - slot:        output file stem (e.g. "01-home").
///   - background:  opaque fill composited behind the view.
///   - colorScheme: light/dark; mirrored onto the host appearance.
///   - localeID:    optional `Locale` injected into the SwiftUI environment.
///   - host:        builds the AppKit host for the composited view — each
///                   UI-test target passes its own `hostingView(...)` helper
///                   here (type-erased to `AnyView`, since a closure type
///                   cannot itself be generic), as that is where the per-app
///                   theme/size-class wiring lives.
/// - Returns: the written file URL, or `nil` if capture produced no bitmap.
@MainActor
@discardableResult
public func emitASCScreenshot<V: SwiftUI.View>(
    _ view: V,
    profile: ASCProfile,
    app: String,
    device: String,
    locale: String,
    slot: String,
    background: Color,
    colorScheme: ColorScheme = .light,
    localeID: Locale? = nil,
    host: (AnyView, CGSize, ColorScheme, Locale?, UserInterfaceSizeClass) -> NSView
) throws -> URL? {
    let composited = AnyView(
        ZStack {
            background.ignoresSafeArea()
            view
        }
    )
    let hostView = host(
        composited,
        profile.pointSize,
        colorScheme,
        localeID,
        profile.sizeClass
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
    // Set the rep's logical size to the POINT size so AppKit maps the
    // point-sized host into the larger pixel buffer at the implied scale.
    rep.size = profile.pointSize
    hostView.cacheDisplay(in: hostView.bounds, to: rep)

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

/// Locate `docs/app-store/screenshots` by walking up from this source file to
/// the repo root (the dir that contains `docs/`). Used only by the emit path.
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
    // Fallback: alongside this file (never expected to hit in-repo).
    return URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
}
#endif
