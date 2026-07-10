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
@testable import SudokuUI
import Testing

enum SnapshotLayouts {
    /// iPhone 16 / 15 canonical compact size class.
    static let iPhone = CGSize(width: 393, height: 852)
    /// iPad 13" regular size class — 1032×1376 pt @2x → 2064×2752 px (ASC iPad 13").
    /// Keep in sync with MinesweeperKit/Tests/.../SnapshotConfig.swift (separate
    /// packages, no shared test-helper target).
    static let iPad = CGSize(width: 1032, height: 1376)
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
/// Calibration history:
/// - 2026-05-28: tried 0.99 / 0.98 — still failed on Sudoku board view.
///   Suspected cause: 81 grid cells with small antialiased digits
///   accumulate enough pixel-edge variance to blow past 1% slack.
/// - 2026-05-29: relaxed to 0.95 / 0.95 — wider window for AA / hinting
///   drift on text-heavy AppKit-hosted SwiftUI subtrees.
///
/// Current values:
/// - `precision: 0.95` — at least 95% of pixels must match exactly
/// - `perceptualPrecision: 0.95` — the remaining ≤5% can differ by up
///   to ~5% in HSL perception space
///
/// Tune in this file (single source of truth) if cross-machine drift
/// grows; do NOT pass overrides at call sites — a per-test threshold
/// hides regressions from view-level changes that should fail every test.
/// If 0.95 / 0.95 still fails, the next move is to re-record baselines
/// on an XCC runner (rather than weaken tolerance further), since
/// weakening past ~5% starts blanketing real visual regressions.
/// SCOPE (#487/#517): `tolerantImage` is BOARD-only (`BoardViewTests`); CONTENT
/// suites use strict `.image` (precision 1.0) so a new visible element fails
/// without re-record (loose tolerance absorbed whole labels; structure gate is
/// vacuous for scroll-hosted content).
extension Snapshotting where Value == NSView, Format == NSImage {
    static var tolerantImage: Snapshotting<NSView, NSImage> {
        .image(precision: 0.95, perceptualPrecision: 0.95)
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
        // #278 Tier-1 Phase 1: the `@Environment(\.theme)` key moved to
        // GameShellUI with a palette-neutral default. Snapshot fixtures
        // previously relied on that default being Sudoku's `DefaultTheme`;
        // inject it explicitly here (mirroring SudokuAppComposition's root
        // injection) so baselines stay byte-identical.
        .environment(\.theme, DefaultTheme())
        // #278 Tier-1 Phase 2a: cell tokens moved to SudokuUI's `\.sudokuCell`
        // env key (out of the generic `Theme`). Inject the concrete palette
        // here, mirroring the live root, so baselines stay byte-identical.
        .environment(\.sudokuCell, DefaultTheme().cell)
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

// MARK: - NSWindow-hosted harness (issue #209)
//
// WHY a second harness: the `hostingView(...)` path above wraps the SwiftUI
// subtree in a bare `NSHostingView`. That view has NO surrounding window, so
// the macOS `Form` / `NavigationSplitView` layout pipeline — which inspects
// the *window* (split-view ancestry, `.formStyle(.grouped)` section chrome,
// per-primitive row treatment, sidebar/detail column sizing) — never runs.
// The subtree renders in an "iOS-shape" host and Mac-only Form regressions
// (#197, #208) stay invisible to the test (false-positive green).
//
// `windowSnapshotView(...)` instead mounts the subtree as an
// `NSHostingController` set as the `contentViewController` of a real (but
// offscreen, never ordered-front) `NSWindow`. The controller participates in
// the genuine AppKit view-controller-in-window containment chain, so SwiftUI
// resolves `Form`/`NavigationSplitView` against a real window environment and
// emits the production Mac chrome. We then snapshot the window's `contentView`
// (an `NSView`), so the existing `Snapshotting<NSView, NSImage>` strategy
// (`.image` / `.tolerantImage`) and the `assertUISnapshot(...)` baseline
// lookup apply unchanged.
//
// Determinism: the window is created at a fixed content size, given a fixed
// `NSAppearance`, and forced through a synchronous layout pass
// (`layoutIfNeeded` on the content view) before capture. It is never ordered
// on screen and never animated, so there is no async layout race. The window
// is closed at the end so each test gets a fresh lifecycle.
//
// CI caveat (see issue #199 history): like every other snapshot test in this
// suite, NSWindow-based tests are gated `.enabled(if: !SnapshotEnv.isXcodeCloud)`.
// A real `NSWindow` requires a window-server connection; Xcode Cloud's
// headless runner cannot guarantee one, and cross-machine AA/hinting drift
// already pushed this suite off XCC. Baselines are recorded + verified on the
// dev Mac only.

/// Mount a SwiftUI View as the `contentViewController` of an offscreen
/// `NSWindow` and return the window's `contentView` for snapshotting.
///
/// Unlike `hostingView(...)`, this exercises the real macOS Form /
/// NavigationSplitView layout pipeline because the subtree lives inside a
/// genuine window via `NSHostingController` containment.
///
/// - Parameters:
///   - view:        the SwiftUI subtree under test.
///   - size:        content size (in points) of the hosting window.
///   - colorScheme: applied via `.preferredColorScheme` AND mirrored onto the
///                  window's `appearance` so AppKit dynamic colors resolve.
///   - locale:      injected via `.environment(\.locale, ...)` when supplied.
///   - sizeClass:   horizontal size class. Defaults to `.regular` (Mac), the
///                  whole point of this harness; iPhone fixtures pass `.compact`.
/// - Returns: the window's `contentView`, plus the owning `NSWindow` the caller
///   must keep alive until after the snapshot is captured (release closes it).
@MainActor
func windowSnapshotView<V: SwiftUI.View>(
    _ view: V,
    size: CGSize,
    colorScheme: ColorScheme = .light,
    locale: Locale? = nil,
    sizeClass: UserInterfaceSizeClass = .regular
) -> (view: NSView, window: NSWindow) {
    let wrapped = view
        // Mirror `hostingView`'s explicit environment injection so the two
        // harnesses agree on theme / cell tokens / size class / locale and
        // any cross-harness diff is purely the Form/window-chrome delta.
        .environment(\.theme, DefaultTheme())
        .environment(\.sudokuCell, DefaultTheme().cell)
        .environment(\.horizontalSizeClass, Optional(sizeClass))
        .environment(\.locale, locale ?? .current)
        .preferredColorScheme(colorScheme)

    let controller = NSHostingController(rootView: wrapped)
    controller.sizingOptions = []

    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: size),
        styleMask: [.titled, .closable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    window.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    window.contentViewController = controller
    // Pin the content size after assigning the controller so the hosting
    // controller's preferred size can't grow the window past our box.
    window.setContentSize(size)
    // Position far offscreen (below the visible coordinate space) so the
    // window gets a real window-server backing store + display pass WITHOUT
    // ever flashing on a visible screen. A never-ordered window has no backing
    // store, so `bitmapImageRepForCachingDisplay` / layer rendering capture a
    // blank image — ordering it front (offscreen) forces the SwiftUI layer
    // tree to actually draw. This is what makes Form/SplitView chrome appear.
    window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
    window.orderFrontRegardless()

    guard let contentView = window.contentView else {
        // `contentViewController` always materialises a contentView; this
        // branch is defensive only.
        return (controller.view, window)
    }
    contentView.frame = CGRect(origin: .zero, size: size)
    // Force a synchronous layout + display pass so capture is deterministic
    // (no async layout race). `layoutSubtreeIfNeeded` drives AppKit + embedded
    // SwiftUI layout to completion; `displayIfNeeded` flushes the draw into the
    // now-existing backing store.
    contentView.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    return (contentView, window)
}

/// Snapshot a SwiftUI View through the NSWindow harness as an `NSImage`.
///
/// CAPTURE PATH — why `displayIgnoringOpacity(_:in:)` and not `cacheDisplay`:
/// an offscreen `NSWindow` under headless `swift test` never connects to a
/// window-server display, so its backing store stays uninitialised. The usual
/// capture paths read that backing store and return solid black:
///   - `NSView.cacheDisplay(in:to:)` → black
///   - `CALayer.render(in:)` on the content view's layer → black
/// `displayIgnoringOpacity(_:in:)` instead drives AppKit's *synchronous draw*
/// directly into a bitmap-backed `NSGraphicsContext`, bypassing the missing
/// window backing store, so it captures the real rendered content. (Verified
/// empirically against the standalone-`NSHostingView` baseline — see issue
/// #209 investigation notes.)
///
/// SCOPE — what this harness CAN and CANNOT render headlessly:
///   - macOS grouped `Form` (`.formStyle(.grouped)`): renders correctly. Form
///     chrome is plain layout, drawn synchronously, so the window-hosted
///     render matches production. THIS is the regression surface from #197 /
///     #208 (Settings Form rows) the harness targets.
///   - `NavigationSplitView` *sidebar* `List`: does NOT populate headlessly —
///     `List` is `NSTableView`-backed and needs a live run-loop / display
///     cycle to materialise cells, which headless `swift test` does not
///     provide. The split frame + detail pane render; the sidebar rows stay
///     blank. Exercising the populated sidebar needs an interactive
///     `xcodebuild test` on a logged-in GUI session (out of scope for the
///     local `swift test` gate; tracked as the CI caveat below).
///
/// Returns an `NSImage` so callers snapshot with `Snapshotting<NSImage, NSImage>`
/// `.image`. The caller owns the returned window and must `window.close()`
/// after the snapshot assertion.
@MainActor
func windowSnapshotImage<V: SwiftUI.View>(
    _ view: V,
    size: CGSize,
    colorScheme: ColorScheme = .light,
    locale: Locale? = nil,
    sizeClass: UserInterfaceSizeClass = .regular
) -> (image: NSImage, window: NSWindow) {
    let (contentView, window) = windowSnapshotView(
        view,
        size: size,
        colorScheme: colorScheme,
        locale: locale,
        sizeClass: sizeClass
    )
    let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds)!
    if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        contentView.displayIgnoringOpacity(contentView.bounds, in: ctx)
        NSGraphicsContext.restoreGraphicsState()
    }
    let image = NSImage(size: contentView.bounds.size)
    image.addRepresentation(rep)
    return (image, window)
}
#endif
