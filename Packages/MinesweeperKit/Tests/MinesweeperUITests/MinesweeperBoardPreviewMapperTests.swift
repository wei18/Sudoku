// MinesweeperBoardPreviewMapperTests — #1017.
//
// Pure mapping tests: no `.live()`, no CloudKit. Covers the happy path
// (hidden/revealed/flagged → empty/filled/marked) and the degrade contract
// (missing/truncated/undecodable blob → nil, never a crash).

import Foundation
import Testing
@testable import MinesweeperAppComposition
import GameShellUI
import MinesweeperEngine
import MinesweeperGameState

@Suite("MinesweeperBoardPreviewMapper")
struct MinesweeperBoardPreviewMapperTests {

    private static func makeSnapshot(cells: [Cell], difficulty: Difficulty = .beginner) -> MinesweeperSessionSnapshot {
        MinesweeperSessionSnapshot(
            difficulty: difficulty,
            seed: 1,
            cells: cells,
            status: .playing,
            elapsedSeconds: 10,
            mineCount: cells.filter(\.isMine).count,
            flagCount: cells.filter { $0.state == .flagged }.count
        )
    }

    @Test("maps hidden/revealed/flagged to empty/filled/marked")
    func mapsCellStatesToMarks() throws {
        let cellCount = Difficulty.beginner.rows * Difficulty.beginner.columns
        var cells = Array(repeating: Cell(state: .hidden), count: cellCount)
        cells[0] = Cell(state: .revealed)
        cells[1] = Cell(state: .flagged)
        let snapshot = Self.makeSnapshot(cells: cells)
        let blob = try JSONEncoder().encode(snapshot)

        let preview = try #require(MinesweeperBoardPreviewMapper.make(stateBlob: blob))

        #expect(preview.columns == Difficulty.beginner.columns)
        #expect(preview.rows == Difficulty.beginner.rows)
        #expect(preview.cells[0] == .filled)
        #expect(preview.cells[1] == .marked)
        #expect(preview.cells[2] == .empty)
    }

    @Test("nil stateBlob degrades to nil preview")
    func nilStateBlobDegradesToNil() {
        #expect(MinesweeperBoardPreviewMapper.make(stateBlob: nil) == nil)
    }

    @Test("truncated stateBlob degrades to nil preview")
    func truncatedStateBlobDegradesToNil() {
        let truncated = Data([0x7B, 0x22]) // `{"` — not valid JSON on its own
        #expect(MinesweeperBoardPreviewMapper.make(stateBlob: truncated) == nil)
    }

    @Test("undecodable (wrong-shape) JSON degrades to nil preview")
    func wrongShapeJSONDegradesToNil() {
        let blob = Data(#"{"unrelated": true}"#.utf8)
        #expect(MinesweeperBoardPreviewMapper.make(stateBlob: blob) == nil)
    }
}
