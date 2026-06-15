// SnapshotConfig — 2048 snapshot harness for Game2048UITests.
//
// A 1:1 mirror of MinesweeperKit's SnapshotConfig.swift, differing only in
// the injected theme: 2048 fixtures get `Game2048Theme()` (M4 warm-tile
// palette, landed in SDD-004 M4).
//
// `swift test` on the host runs macOS tests; we render SwiftUI Views through
// `NSHostingView` (size-pinned to a canonical device size) and snapshot as
// an NSView. See MinesweeperKit's SnapshotConfig for the two appearance/
// layout caveats (NSAppearance mirroring + sizingOptions pinning) and the
// Xcode Cloud bundle-resource baseline-lookup rationale.

#if canImport(AppKit)
import AppKit
import Foundation
import SnapshotTesting
import SwiftUI
@testable import Game2048UI
import GameShellUI
import Testing

enum SnapshotLayouts {
    /// iPhone 16 / 15 canonical compact size class.
    static let iPhone = CGSize(width: 393, height: 852)
}

/// Default record mode. `.missing` records baselines on first run; subsequent
/// runs diff. Flip to `.all` locally to force re-record.
enum SnapshotMode {
    static let recordMode: SnapshotTestingConfiguration.Record = .missing
}

/// Xcode Cloud detection — its distributed runner can't reach baseline PNGs
/// via the library's `#filePath`-walk, so we resolve via `Bundle.module`.
enum SnapshotEnv {
    static let isXcodeCloud = ProcessInfo.processInfo.environment["CI_XCODE_CLOUD"] != nil
}

/// Resolves the per-test-class snapshot directory.
enum SnapshotPaths {
    static func directory(forTestFile filePath: StaticString = #filePath) -> String? {
        guard SnapshotEnv.isXcodeCloud else { return nil }
        guard let resourceURL = Bundle.module.resourceURL else { return nil }
        let fileURL = URL(fileURLWithPath: "\(filePath)", isDirectory: false)
        let testClass = fileURL.deletingPathExtension().lastPathComponent
        return resourceURL
            .appendingPathComponent("__Snapshots__", isDirectory: true)
            .appendingPathComponent(testClass, isDirectory: true)
            .path
    }
}

/// Cross-machine-tolerant image strategy (precision 0.95 / perceptualPrecision 0.95).
extension Snapshotting where Value == NSView, Format == NSImage {
    static var tolerantImage: Snapshotting<NSView, NSImage> {
        .image(precision: 0.95, perceptualPrecision: 0.95)
    }
}

/// Snapshot-assertion wrapper that redirects baseline lookups to
/// `Bundle.module` on Xcode Cloud while preserving the default `#filePath`-walk
/// locally. Mirrors MinesweeperKit's `assertUISnapshot`.
@MainActor
func assertUISnapshot<Value, Format>(
    of value: @autoclosure () throws -> Value,
    as snapshotting: Snapshotting<Value, Format>,
    named name: String? = nil,
    record: SnapshotTestingConfiguration.Record? = nil,
    timeout: TimeInterval = 5,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    let failure = verifySnapshot(
        of: try value(),
        as: snapshotting,
        named: name,
        record: record,
        snapshotDirectory: SnapshotPaths.directory(forTestFile: filePath),
        timeout: timeout,
        fileID: fileID,
        file: filePath,
        testName: testName,
        line: line,
        column: column
    )
    guard let message = failure else { return }
    Issue.record(
        Comment(rawValue: message),
        sourceLocation: SourceLocation(
            fileID: "\(fileID)",
            filePath: "\(filePath)",
            line: Int(line),
            column: Int(column)
        )
    )
}

/// Wrap a SwiftUI View in an `NSHostingView` sized to `size` for snapshot.
/// Injects `Game2048Theme()` (M4 warm-tile palette) so board baselines
/// reflect the shipped brand rather than the neutral fallback.
@MainActor
func hostingView<ViewType: SwiftUI.View>(
    _ view: ViewType,
    size: CGSize,
    colorScheme: ColorScheme = .light,
    locale: Locale? = nil,
    sizeClass: UserInterfaceSizeClass = .compact
) -> NSView {
    let wrapped = view
        .environment(\.theme, Game2048Theme())
        .environment(\.horizontalSizeClass, Optional(sizeClass))
        .environment(\.locale, locale ?? .current)
        .preferredColorScheme(colorScheme)
        .frame(width: size.width, height: size.height)
    let host = NSHostingView(rootView: wrapped)
    host.sizingOptions = []
    host.frame = CGRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    host.layoutSubtreeIfNeeded()
    return host
}
#endif
