// SnapshotStructureHelper — view-tree text assertion gate (#487).
//
// Extracted from SnapshotConfig.swift to keep that file under the 400-line
// SwiftLint threshold. This helper records NSHostingView `_subtreeDescription`
// as a `.txt` baseline alongside the PNG. The mangled generic type name encodes
// every SwiftUI node, so adding/removing a Text/Label fails the baseline
// independently of the 0.95/0.95 pixel tolerance.
//
// Keep in sync with MinesweeperKit/Tests/.../SnapshotConfig.swift (separate
// packages, no shared test-helper target).

#if canImport(AppKit)
import AppKit
import SnapshotTesting
import Testing

/// Assert that the SwiftUI view-tree structure of `host` matches a recorded
/// `.txt` baseline. Call alongside `assertUISnapshot(... as: .tolerantImage)`.
/// Adding or removing a content-bearing node (Text, Label, Image) changes the
/// mangled generic type and fails this baseline without touching the PNG.
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
    let raw = host.perform(Selector(("_subtreeDescription")))?.retain()
        .takeUnretainedValue() as? String ?? ""
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
