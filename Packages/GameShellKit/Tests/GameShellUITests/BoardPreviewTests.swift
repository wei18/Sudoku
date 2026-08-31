// BoardPreviewTests — #1017.
//
// `BoardPreview` is the shell's zero-dependency value type; the per-app
// mappers that build one from a real saved payload live in each app's own
// AppComposition target (SudokuKit / MinesweeperKit) and are tested there.
// Here we pin the type's own contract: valid construction, the
// `cells.count == columns * rows` invariant, and — via a fake mapper
// standing in for a real per-app one — the "missing payload → nil" degrade
// path so a caller never needs to special-case a malformed preview.

import Testing
@testable import GameShellUI

@Suite("GameShellUI — BoardPreview")
struct BoardPreviewTests {

    @Test("constructs when cells.count matches columns * rows")
    func validConstruction() throws {
        let preview = try #require(
            BoardPreview(columns: 3, rows: 2, cells: [.given, .filled, .empty, .empty, .marked, .filled])
        )
        #expect(preview.columns == 3)
        #expect(preview.rows == 2)
        #expect(preview.cells.count == 6)
    }

    @Test("fails when cells.count does not match columns * rows")
    func mismatchedCellCountFailsInit() {
        #expect(BoardPreview(columns: 3, rows: 2, cells: [.empty, .empty]) == nil)
    }

    @Test("fails for non-positive dimensions")
    func nonPositiveDimensionsFailInit() {
        #expect(BoardPreview(columns: 0, rows: 2, cells: []) == nil)
        #expect(BoardPreview(columns: 3, rows: 0, cells: []) == nil)
    }

    @Test("two previews with the same shape and marks are equal")
    func equatable() {
        let first = BoardPreview(columns: 2, rows: 1, cells: [.given, .empty])
        let second = BoardPreview(columns: 2, rows: 1, cells: [.given, .empty])
        #expect(first == second)
    }

    // MARK: - Fake per-app mapper: missing payload → nil degrade path

    /// Stands in for a real per-app mapper (e.g. `SudokuBoardPreviewMapper`,
    /// `MinesweeperBoardPreviewMapper`) that turns an optional saved-game
    /// payload string into a `BoardPreview?`. Exercises the shape of the
    /// contract every real mapper must honor: `nil` payload in, `nil`
    /// preview out — never a crash.
    private func fakeMapper(payload: String?) -> BoardPreview? {
        guard let payload, payload.count == 4 else { return nil }
        let marks = payload.map { $0 == "." ? CellMark.empty : .filled }
        return BoardPreview(columns: 2, rows: 2, cells: marks)
    }

    @Test("fake mapper degrades a missing payload to nil")
    func fakeMapperMissingPayloadDegradesToNil() {
        #expect(fakeMapper(payload: nil) == nil)
    }

    @Test("fake mapper degrades a malformed payload to nil")
    func fakeMapperMalformedPayloadDegradesToNil() {
        #expect(fakeMapper(payload: "12") == nil)
    }

    @Test("fake mapper maps a well-formed payload")
    func fakeMapperMapsWellFormedPayload() throws {
        let preview = try #require(fakeMapper(payload: "1.2."))
        #expect(preview.cells == [.filled, .empty, .filled, .empty])
    }
}
