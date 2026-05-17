// Shared helpers for snapshot tests.
//
// Strategy:
// - Tests run on macOS; `swift-snapshot-testing` ships `.image` strategies
//   for `NSView`. We wrap each SwiftUI view in an `NSHostingView` of a fixed
//   size (iPhone 393×852 or Mac 900×700) and snapshot the resulting NSView.
// - All snapshots are placed on a `DesignTokens.surfaceBackground` host so
//   `.glassEffect` composites against a stable background.

import SwiftUI
import SnapshotTesting
import XCTest
@testable import DesignPreviewKit

#if canImport(AppKit)
import AppKit
#endif

enum DeviceSize {
    static let iPhone = CGSize(width: 393, height: 852)
    static let mac = CGSize(width: 900, height: 700)
    static let component = CGSize(width: 393, height: 200)
    static let smallComponent = CGSize(width: 240, height: 120)
}

@MainActor
func hostingView<V: View>(
    _ view: V,
    size: CGSize,
    colorScheme: ColorScheme = .light,
    locale: Locale = Locale(identifier: "en"),
    dynamicTypeSize: DynamicTypeSize = .large
) -> NSView {
    let wrapped = view
        .environment(\.locale, locale)
        .environment(\.colorScheme, colorScheme)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .frame(width: size.width, height: size.height)
        .background(DesignTokens.surfaceBackground)
        .colorScheme(colorScheme)
    let host = NSHostingView(rootView: wrapped)
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    return host
}

/// Default precision tolerance to avoid spurious flake on font-rendering
/// micro-differences across Xcode patch versions.
let snapshotPrecision: Float = 0.98
let snapshotPerceptualPrecision: Float = 0.98

/// Pin the snapshot directory under `Tests/DesignPreviewSnapshotTests/__Snapshots__/<TestClass>/`
/// rather than relying on `#file`-relative placement (SwiftPM reports a
/// stripped path that would land snapshots alongside the wrong directory).
func snapshotDirectory(forTestFile testFile: StaticString = #file) -> String {
    let url = URL(fileURLWithPath: "\(testFile)")
    let testName = url.deletingPathExtension().lastPathComponent
    // Walk upward for `code` directory.
    var dir = url.deletingLastPathComponent()
    while dir.path != "/" && dir.lastPathComponent != "code" {
        dir = dir.deletingLastPathComponent()
    }
    return dir
        .appendingPathComponent("Tests")
        .appendingPathComponent("DesignPreviewSnapshotTests")
        .appendingPathComponent("__Snapshots__")
        .appendingPathComponent(testName)
        .path
}
