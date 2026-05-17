// Snapshots for CellView state variants. Covers SnapshotMatrix §4 (7 cases).

import XCTest
import SwiftUI
import SnapshotTesting
@testable import DesignPreviewKit

@MainActor
final class CellStateSnapshotTests: XCTestCase {

    private let side: CGFloat = 80

    private func assertCell(
        _ state: CellState,
        colorScheme: ColorScheme = .light,
        named: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let view = CellView(state: state, side: side)
            .padding()
        let host = hostingView(
            view,
            size: CGSize(width: side + 32, height: side + 32),
            colorScheme: colorScheme
        )
        if let failure = verifySnapshot(
            of: host,
            as: .image(precision: snapshotPrecision, perceptualPrecision: snapshotPerceptualPrecision),
            named: named,
            snapshotDirectory: snapshotDirectory(forTestFile: file),
            file: file,
            testName: "CellStateSnapshots",
            line: line
        ) {
            XCTFail(failure, file: file, line: line)
        }
    }

    func test_cellView_light_empty() { assertCell(.empty, named: "cellView_light_empty") }
    func test_cellView_light_given() { assertCell(.given(5), named: "cellView_light_given") }
    func test_cellView_light_user() { assertCell(.user(7), named: "cellView_light_user") }
    func test_cellView_light_error() { assertCell(.error(7), named: "cellView_light_error") }
    func test_cellView_light_selected() { assertCell(.selected(6), named: "cellView_light_selected") }
    func test_cellView_light_highlighted() { assertCell(.highlighted(nil), named: "cellView_light_highlighted") }
    func test_cellView_dark_error() { assertCell(.error(7), colorScheme: .dark, named: "cellView_dark_error") }
}
