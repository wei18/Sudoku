// SnapshotConfig — MS snapshot harness (#278 Tier-1 Phase 2b).
//
// Mirrors SudokuKit's `Tests/SudokuUITests/SnapshotConfig.swift` in structure,
// but diverges in three intentional ways:
//   1. Injected theme: MS fixtures get `MinesweeperTheme()` + `\.minesweeperCell`
//      instead of Sudoku's `DefaultTheme()` + `\.sudokuCell`.
//   2. Structure-assertion helper: the `#487` structural-baseline helper is
//      inlined here rather than extracted to a separate `SnapshotStructureHelper.swift`
//      (Sudoku extracted it to stay under the 400-line SwiftLint limit; this file
//      remains comfortably below that threshold).
//   3. Mac harness omitted: Sudoku's file contains an `NSWindow` Form/SplitView
//      harness for Mac-specific snapshot coverage; MS has no Mac-layout variants
//      and omits it deliberately.
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
    /// iPad 13" regular size class — 1032×1376 pt @2x → 2064×2752 px (ASC iPad 13").
    /// Keep in sync with SudokuKit/Tests/.../SnapshotConfig.swift (separate
    /// packages, no shared test-helper target).
    static let iPad = CGSize(width: 1032, height: 1376)
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

/// #796: the isolated `UserDefaults` suite every `MinesweeperBoardView(...)`
/// construction in this test target MUST pass as `tapModeDefaults`. The
/// swiftpm-testing-helper host shares one persistent `.standard` domain
/// across every test process on the machine, so a leaked
/// `com.wei18.minesweeper.board.tapMode = flag` from an unrelated run can
/// silently seed the toggle in Flag mode for every board snapshot / ASC
/// screenshot — `.tolerantImage`'s 0.95 precision absorbs the pixel
/// difference, so a polluted recording still passes verification (#786 hit
/// this on a re-record). One suite per process (not per-call — these tests
/// never need cross-test isolation for this single key) reset to the
/// baseline-expected "reveal" value at first access.
@MainActor
enum BoardTestDefaults {
    static let store: UserDefaults = {
        let suiteName = "MinesweeperUITests.tapModeIsolation.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("reveal", forKey: MinesweeperBoardView.tapModeKey)
        return defaults
    }()
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

/// Cross-machine-tolerant image strategy (precision 0.95 / perceptualPrecision
/// 0.95) — single source of truth here, do NOT override at call sites.
///
/// SCOPE (#487/#517): use this ONLY for AA-heavy BOARD/grid suites
/// (`MinesweeperBoard*`), where dozens of antialiased cells accumulate enough
/// cross-machine hinting drift to false-fail strict equality. CONTENT suites
/// (Completion / DailyHub / Home) use the default strict `.image` (precision
/// 1.0) — mirroring Sudoku — so that ADDING a visible element (e.g. the #486
/// "Failed" badge) changes pixels and FAILS the suite without a re-record. The
/// loose tolerance used to absorb whole new labels (#487) and the view-tree
/// structure gate is vacuous for scroll-hosted content (#517); strict pixels on
/// content close both.
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

// MARK: - View-structure text assertion (#487)
//
// WHY a text baseline alongside the image baseline:
// The `tolerantImage` strategy (precision 0.95 / perceptualPrecision 0.95)
// absorbs rendering drift across machines but can also silently absorb
// added/removed content (e.g. a new "Failed" badge that falls within the 5%
// pixel tolerance window). The text baseline guards the *structural* shape of
// the SwiftUI view tree: it records the mangled type name of the `NSHostingView`
// generic, which encodes every visible node (Text, Label, Image, HStack, etc.)
// as part of its generic parameter chain. Adding or removing a content-bearing
// SwiftUI node changes the type name and therefore the baseline.
//
// Mechanism: `NSView._subtreeDescription()` (the same private method that
// SnapshotTesting's `.recursiveDescription` uses) returns a one-line string
// whose class name is the full Swift mangled type — e.g.
//   NSHostingView<ModifiedContent<HStack<TupleView<(Text,Text)>>,…>>
// vs
//   NSHostingView<ModifiedContent<HStack<Text>,…>>
// — different when a node is added. Memory addresses are stripped by
// `purgePointers` (same regex as SnapshotTesting), so the baseline is stable
// across runs on the same OS/Swift toolchain.
//
// SCOPE — what this gate covers and what it does NOT:
// - COVERS: interactive list/grid rows that surface as their own AppKit nodes
//   (DailyHub cards, Home mode cards render as `_FocusRingView` children, so
//   add/remove of a row changes the subtree text). This is the surface #487
//   was filed for, and the gate is genuinely effective there.
// - DOES NOT COVER: scroll-hosted content views (e.g. CompletionView). Their
//   SwiftUI content lives inside `HostingScrollView`'s `DocumentView f=(0,0,0,0)`
//   with NO child nodes in `_subtreeDescription`, so the baseline is identical
//   across states (a new "Failed" badge inside the scroll view does NOT change
//   it). Wiring those suites would record vacuous always-passing baselines —
//   the exact false-confidence anti-pattern #487 targets — so they are NOT
//   wired. That gap is tracked in #517.
//
// Caveats:
// - The mangled type name IS toolchain-version-sensitive. If the Swift ABI
//   mangle changes across a major Xcode upgrade, baselines need re-recording —
//   which is expected and preferable to silent regressions.
// - This check is local-only (gated `.enabled(if: !SnapshotEnv.isXcodeCloud)`)
//   just like the image baselines, for the same reasons (headless XCC doesn't
//   have a window server). It adds no new CI gate requirements.
// - Keep in sync with SudokuKit/Tests/.../SnapshotStructureHelper.swift
//   (separate packages, no shared test-helper target).

/// Snapshot the structural type shape of a hosted SwiftUI view as a text
/// baseline. Call immediately after `assertUISnapshot(... as: .tolerantImage
/// ...)` so adding/removing an interactive list/grid row fails the test
/// independently of pixel tolerance.
///
/// ONLY wire suites whose content surfaces as distinct AppKit nodes (DailyHub /
/// Home cards). Do NOT wire scroll-hosted content views (CompletionView): their
/// content collapses into an empty `DocumentView` and the baseline is vacuous —
/// see the SCOPE note above and #517.
///
/// The baseline file is named `<testName>.<named>.txt` and lives beside the
/// PNG in `__Snapshots__/<TestClass>/`. Pass the same `named` label used for
/// the image snapshot.
@MainActor
func assertViewStructure(
    of host: NSView,
    named name: String,
    record: SnapshotTestingConfiguration.Record? = nil,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    let raw = host.perform(Selector(("_subtreeDescription")))?
        .takeUnretainedValue() as? String ?? ""
    // Strip memory addresses (mirrors SnapshotTesting's purgePointers regex).
    let sanitised = raw.replacingOccurrences(
        of: ":?\\s*0x[\\da-f]+(\\s*)", with: "$1", options: .regularExpression)
    let failure = verifySnapshot(
        of: sanitised,
        as: .lines,
        named: name,
        record: record,
        snapshotDirectory: SnapshotPaths.directory(forTestFile: filePath),
        timeout: 5,
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

/// AX5 / accessibility Dynamic Type variant of `hostingView(...)` (#762 PR1
/// spec item E). Kept as a SEPARATE OVERLOAD — mirrors SudokuKit's
/// `SnapshotConfig.swift` — rather than an added optional parameter, so
/// every existing call site keeps resolving to the function above and its
/// concrete `NSHostingView<...>` generic type stays byte-identical.
@MainActor
func hostingView<V: SwiftUI.View>(
    _ view: V,
    size: CGSize,
    colorScheme: ColorScheme = .light,
    locale: Locale? = nil,
    sizeClass: UserInterfaceSizeClass = .compact,
    dynamicTypeSize: DynamicTypeSize
) -> NSView {
    let wrapped = view
        .environment(\.theme, MinesweeperTheme())
        .environment(\.minesweeperCell, MinesweeperTheme().cell)
        .environment(\.horizontalSizeClass, Optional(sizeClass))
        .environment(\.locale, locale ?? .current)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
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
