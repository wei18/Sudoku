// MinesweeperBoardPreviewMapper — MS's `stateBlob` ↔ `BoardPreview` (#1017).
//
// Pure, testable mapping: no CloudKit, no `.live()` construction. `Live.swift`
// hands this mapper the raw `stateBlob` bytes already fetched by
// `latestInProgress()` (#1017 no new round-trip); decoding + cell
// classification happen here so a malformed/truncated blob degrades to `nil`
// without touching `Live.swift`'s wiring.
//
// `CellState` maps directly onto `CellMark` — hidden→empty, revealed→filled,
// flagged→marked (design.md §3.6).

public import Foundation
public import GameShellUI
import MinesweeperEngine
import MinesweeperGameState

public enum MinesweeperBoardPreviewMapper {

    /// `nil` on anything malformed: missing/undecodable blob, or a
    /// cell count that doesn't match the snapshot's own `columns * rows`.
    /// Never throws/crashes — resume must keep working with a text-only pill.
    public static func make(stateBlob: Data?) -> BoardPreview? {
        guard let stateBlob else { return nil }
        guard let snapshot = try? JSONDecoder().decode(MinesweeperSessionSnapshot.self, from: stateBlob) else {
            return nil
        }
        let marks = snapshot.cells.map(Self.mark(for:))
        return BoardPreview(columns: snapshot.columns, rows: snapshot.rows, cells: marks)
    }

    private static func mark(for cell: Cell) -> CellMark {
        switch cell.state {
        case .hidden: return .empty
        case .revealed: return .filled
        case .flagged: return .marked
        }
    }
}
