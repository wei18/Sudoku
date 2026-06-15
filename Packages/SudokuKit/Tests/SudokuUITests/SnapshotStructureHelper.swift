// SnapshotStructureHelper — view-tree text assertion gate (#487).
//
// Extracted from SnapshotConfig.swift to keep that file under the 400-line
// SwiftLint threshold. Records NSHostingView `_subtreeDescription` as a `.txt`
// baseline alongside the PNG. The mangled generic type name encodes the SwiftUI
// node tree, so adding/removing an interactive list/grid row fails the baseline
// independently of the 0.95/0.95 pixel tolerance.
//
// SCOPE: COVERS interactive list/grid rows that surface as distinct AppKit
// nodes (DailyHub / Home cards render as `_FocusRingView` children). DOES NOT
// COVER scroll-hosted content views (CompletionView) — their content collapses
// into an empty `DocumentView f=(0,0,0,0)`, so the baseline is identical across
// states and the gate is vacuous. Those suites are deliberately NOT wired; that
// gap is tracked in #517. See MinesweeperKit's SnapshotConfig SCOPE note for
// the full rationale. Keep in sync with that file (no shared test-helper target).

#if canImport(AppKit)
import AppKit
import SnapshotTesting
import Testing

/// Assert that the SwiftUI view-tree structure of `host` matches a recorded
/// `.txt` baseline. Call alongside `assertUISnapshot(... as: .tolerantImage)`.
/// Only wire suites whose content surfaces as distinct AppKit nodes (DailyHub /
/// Home cards); do NOT wire scroll-hosted views (CompletionView) — see #517.
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
        of: sanitised, as: .lines, named: name, record: record,
        snapshotDirectory: SnapshotPaths.directory(forTestFile: filePath),
        timeout: 5, fileID: fileID, file: filePath,
        testName: testName, line: line, column: column
    )
    guard let message = failure else { return }
    Issue.record(
        Comment(rawValue: message),
        sourceLocation: SourceLocation(
            fileID: "\(fileID)", filePath: "\(filePath)",
            line: Int(line), column: Int(column)
        )
    )
}
#endif
