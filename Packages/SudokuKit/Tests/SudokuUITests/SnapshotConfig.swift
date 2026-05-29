// SnapshotConfig — shared layouts, NSHostingView wrapper, and record mode.
//
// `swift test` on the host can only run macOS tests; we render SwiftUI
// Views through `NSHostingView` (size-pinned to one of the canonical
// `SnapshotLayouts`) and snapshot as an NSView. The dimensions mirror
// the canonical device sizes from design.md §How.5.8.
//
// Two appearance/layout concerns the host doesn't honor automatically:
//   1. `.preferredColorScheme(...)` on a SwiftUI subtree does NOT change
//      the `NSAppearance` of the surrounding `NSHostingView`, so dynamic
//      colors built with `NSColor(name:dynamicProvider:)` (which is how
//      `Color(light:dark:)` resolves on AppKit) keep the *system*
//      appearance. We mirror the requested scheme onto `host.appearance`.
//   2. `NSHostingView`'s default `sizingOptions` adapt the view's frame
//      to the SwiftUI subtree's preferred size, which can blow past the
//      device-sized box for views that declare `maxWidth: .infinity`.
//      We pin the SwiftUI subtree to the device frame with an explicit
//      `.frame(width:height:)` so the snapshot matches the requested box.
//
// macOS `horizontalSizeClass` is always treated as `.regular` by SwiftUI
// host views unless overridden, which forces iPhone-shaped snapshots into
// `NavigationSplitView` / two-column grids. The wrapper accepts a
// `sizeClass` so iPhone fixtures get `.compact` and Mac fixtures stay
// `.regular`.

#if canImport(AppKit)
import AppKit
import Foundation
import SnapshotTesting
import SwiftUI
import Testing

enum SnapshotLayouts {
    /// iPhone 16 / 15 canonical compact size class.
    static let iPhone = CGSize(width: 393, height: 852)
    /// Mac regular size class — matches the design preview frame
    /// (`#Preview` width 900 × height 600).
    static let mac = CGSize(width: 900, height: 600)
}

/// Default record mode. Set to `.missing` so first runs record baselines;
/// subsequent runs diff. Flip to `.all` locally to force re-record.
enum SnapshotMode {
    static let recordMode: SnapshotTestingConfiguration.Record = .missing
}

/// Environment detection for snapshot tests. Xcode Cloud's distributed
/// test runner cannot reliably access baseline PNG resources via the
/// library's default `#filePath`-walk (the source tree isn't on the test
/// machine). Issue #188 fixes that by bundling `__Snapshots__/` as a
/// test-target resource and resolving via `Bundle.module` at runtime;
/// see `SnapshotPaths.directory(forTestFile:)` and `assertUISnapshot(...)`.
/// Set `CI_XCODE_CLOUD=1` in `ci_scripts/ci_pre_xcodebuild.sh` (or any
/// Xcode Cloud lifecycle script) to activate the bundle-based lookup.
enum SnapshotEnv {
    static let isXcodeCloud = ProcessInfo.processInfo.environment["CI_XCODE_CLOUD"] != nil
}

/// Resolves the per-test-class snapshot directory for swift-snapshot-testing.
///
/// On Xcode Cloud the test runner machine doesn't have the source tree, so
/// the library's default `<filePath dir>/__Snapshots__/<fileName>` lookup
/// returns a missing path. With `__Snapshots__/` declared as a test-target
/// resource in `Package.swift`, `Bundle.module.resourceURL` exposes the
/// bundled copy. We compute `<resourceURL>/__Snapshots__/<TestClass>` to
/// match the library's appended-`fileName` convention.
///
/// Locally we return `nil` so the library's `#filePath`-walk default kicks
/// in — preserving `--record` mode's ability to write baselines back into
/// the source tree at `Tests/SudokuUITests/__Snapshots__/`.
enum SnapshotPaths {
    /// - Parameter filePath: pass `#filePath` from the calling test. Used
    ///   to compute the per-test-class subdirectory (the file's base name
    ///   sans `.swift`), matching swift-snapshot-testing's default layout.
    /// - Returns: an absolute path string on Xcode Cloud, or `nil`
    ///   locally (signalling the caller to omit `snapshotDirectory:` and
    ///   let the library use its default).
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

/// Cross-machine-tolerant image snapshot strategy.
///
/// Default `.image` (precision 1.0, perceptualPrecision 1.0) demands
/// bit-exact pixel equality, which holds locally but fails on Xcode Cloud
/// because the runner machine renders AppKit text/strokes with slightly
/// different font hinting, AA thresholds, and ICC profile rounding from
/// the dev Mac that recorded the baseline. Issue #188 probe (PR #199)
/// confirmed the baseline is now correctly found on XCC; the residual
/// failure is rendering drift.
///
/// Calibration:
/// - `precision: 0.99` — at least 99% of pixels must match exactly
/// - `perceptualPrecision: 0.98` — the remaining ≤1% can differ by up
///   to ~2% in HSL perception space
///
/// Tune in this file (single source of truth) if cross-machine drift
/// grows; do NOT pass overrides at call sites — a per-test threshold
/// hides regressions from view-level changes that should fail every test.
extension Snapshotting where Value == NSView, Format == NSImage {
    static var tolerantImage: Snapshotting<NSView, NSImage> {
        .image(precision: 0.99, perceptualPrecision: 0.98)
    }
}

/// Snapshot-assertion wrapper that redirects baseline lookups to
/// `Bundle.module` on Xcode Cloud while preserving the default
/// `#filePath`-walk locally (so `--record` mode still writes back to the
/// source tree).
///
/// The public top-level `assertSnapshot(...)` does NOT expose
/// `snapshotDirectory:` — only the lower-level `verifySnapshot(...)`
/// does. We mirror what `assertSnapshot` itself does internally (see
/// `swift-snapshot-testing` `AssertSnapshot.swift:110-142`): call
/// `verifySnapshot(...)` with our redirected directory, then forward any
/// failure through `recordIssue(...)`.
///
/// Call sites pass `#filePath` implicitly via the default argument, so
/// switching `assertSnapshot(...)` → `assertUISnapshot(...)` is a
/// one-token rename.
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
    // Mirror swift-snapshot-testing's internal `recordIssue` behavior for
    // the swift-testing path (the library's `recordIssue` is `@_spi(Internals)`
    // so not reachable from here without an `@_spi` import). All our tests
    // are swift-testing — no XCTest path needed.
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
///
/// - Parameters:
///   - view:        the SwiftUI subtree under test.
///   - size:        device-pixel box (in points) the snapshot should fill.
///   - colorScheme: applied via `.preferredColorScheme` AND mirrored onto
///                  `host.appearance` so AppKit dynamic colors resolve.
///   - locale:      injected via `.environment(\.locale, ...)` when supplied.
///   - sizeClass:   horizontal size class for the SwiftUI subtree. Defaults
///                  to `.compact` (iPhone). Mac fixtures should pass `.regular`.
@MainActor
func hostingView<V: SwiftUI.View>(
    _ view: V,
    size: CGSize,
    colorScheme: ColorScheme = .light,
    locale: Locale? = nil,
    sizeClass: UserInterfaceSizeClass = .compact
) -> NSView {
    let wrapped = view
        .environment(\.horizontalSizeClass, Optional(sizeClass))
        .environment(\.locale, locale ?? .current)
        .preferredColorScheme(colorScheme)
        .frame(width: size.width, height: size.height)
    let host = NSHostingView(rootView: wrapped)
    // Disable the default `.standardBounds` so the SwiftUI subtree can
    // never grow the host past our requested device frame.
    host.sizingOptions = []
    host.frame = CGRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    host.layoutSubtreeIfNeeded()
    return host
}
#endif
