// RegularBoardContainer — #1101, shared by both games (#1105).
//
// Each game's `macLayout` (e.g. `MinesweeperBoardView.macLayout`, #298 #6)
// was written for exactly one regular-width host: the Mac detail pane,
// capped to an outer-column / board-square pair of its own (Minesweeper:
// 900pt / 600pt, locked 2026-05-30; Sudoku's `BoardView.macLayout` caps the
// same way at 960pt / 640pt). iPad also reports `.regular` horizontal size
// class and was inheriting those same Mac caps, so the board viewport was
// stuck in a capped square with a lot of blank space below it in portrait.
// PM ruling on #1101: iPad's board viewport should fill the whole board
// column (both width AND height), leaving cell sizing to each game's own
// cell-sizing ladder (MS: #764 `cellSizing`) — Mac's capped detail-pane
// behavior is unchanged. #1105 moved the seam here so Sudoku's `BoardView`
// can read the same rule instead of growing a second copy (mirror
// principle).
//
// This is an `EnvironmentValue` rather than a `#if os(iOS)` constant because
// `swift test` only runs on macOS: the only way to exercise "the iPad rule"
// in a snapshot test or an ASC store-frame render on that host is to inject
// it explicitly. Production code still gets the right default for free via
// `platformDefault`.
public import SwiftUI

/// Which sizing rule a regular-width (iPad / Mac) host applies to the board
/// viewport in a game's `macLayout` (Minesweeper and Sudoku both apply it,
/// #1105).
public enum RegularBoardContainer: Sendable, Equatable {
    /// iPad: the board viewport receives the full board column's width AND
    /// height; the game's own cell-sizing ladder (MS: `cellSizing`, #764)
    /// picks the cell size from whatever rect it is offered. See #1101.
    case fillsColumn

    /// Mac detail pane: outer column capped to the app's Mac detail-pane
    /// width and centered, board viewport capped to the app's Mac
    /// detail-pane board-square side (Minesweeper: 900pt / 600pt, locked
    /// 2026-05-30, #298 #6; Sudoku: 960pt / 640pt).
    case cappedDetailPane

    /// The default rule for the current platform. iOS's only regular-width
    /// host is iPad (`horizontalSizeClass` alone can't distinguish it from
    /// Mac, which is also `.regular`), so iOS defaults to `.fillsColumn`;
    /// every other platform (macOS) keeps the capped Mac detail-pane rule.
    public static var platformDefault: RegularBoardContainer {
        #if os(iOS)
        .fillsColumn
        #else
        .cappedDetailPane
        #endif
    }
}

// MARK: - Environment key

private struct RegularBoardContainerKey: EnvironmentKey {
    static let defaultValue = RegularBoardContainer.platformDefault
}

public extension EnvironmentValues {
    var regularBoardContainer: RegularBoardContainer {
        get { self[RegularBoardContainerKey.self] }
        set { self[RegularBoardContainerKey.self] = newValue }
    }
}
