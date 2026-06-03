// SnapshotConfig — MS snapshot harness (#278 Tier-1 Phase 2b).
//
// A 1:1 mirror of SudokuKit's `Tests/SudokuUITests/SnapshotConfig.swift`,
// differing only in the injected theme: MS fixtures get `MinesweeperTheme()`
// + `\.minesweeperCell` instead of Sudoku's `DefaultTheme()` + `\.sudokuCell`.
//
// `swift test` on the host can only run macOS tests; we render SwiftUI Views
// through `NSHostingView` (size-pinned to a canonical device size) and snapshot
// as an NSView. See the Sudoku original for the two appearance/layout caveats
// (NSAppearance mirroring + sizingOptions pinning) and the Xcode Cloud
// bundle-resource baseline-lookup rationale (issue #188).

#if canImport(AppKit)
import AppKit
import Foundation
import SnapshotTesting
import SwiftUI
@testable import MinesweeperUI
import Testing

enum SnapshotLayouts {
    /// iPhone 16 / 15 canonical compact size class.
    static let iPhone = CGSize(width: 393, height: 852)
    /// Mac regular size class.
    static let mac = CGSize(width: 900, height: 600)
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

/// Resolves the per-test-class snapshot directory. Returns an absolute path on
/// Xcode Cloud (via `Bundle.module`), or `nil` locally so the library's
/// `#filePath`-walk default kicks in (preserving `--record` write-back).
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

/// Cross-machine-tolerant image strategy. Same calibration as Sudoku's
/// (precision 0.95 / perceptualPrecision 0.95) — single source of truth here,
/// do NOT override at call sites.
extension Snapshotting where Value == NSView, Format == NSImage {
    static var tolerantImage: Snapshotting<NSView, NSImage> {
        .image(precision: 0.95, perceptualPrecision: 0.95)
    }
}

/// Snapshot-assertion wrapper that redirects baseline lookups to
/// `Bundle.module` on Xcode Cloud while preserving the default `#filePath`-walk
/// locally. Mirrors Sudoku's `assertUISnapshot`.
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

/// Wrap a SwiftUI View in an `NSHostingView` sized to `size` for snapshot,
/// injecting the MS theme + cell tokens to mirror the live root.
@MainActor
func hostingView<V: SwiftUI.View>(
    _ view: V,
    size: CGSize,
    colorScheme: ColorScheme = .light,
    locale: Locale? = nil,
    sizeClass: UserInterfaceSizeClass = .compact
) -> NSView {
    let wrapped = view
        // #278 Tier-1 Phase 2b: inject MS's concrete theme + MS-shaped cell
        // tokens here, mirroring `MinesweeperAppComposition.rootView`, so the
        // baselines render the themed board exactly as the live app does.
        .environment(\.theme, MinesweeperTheme())
        .environment(\.minesweeperCell, MinesweeperTheme().cell)
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
