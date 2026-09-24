// RegularBoardContainer — #1101.
//
// `MinesweeperBoardView.macLayout` (#298 #6) was written for exactly one
// regular-width host: the Mac detail pane, capped to a 900pt outer column /
// 600pt board square (locked 2026-05-30). iPad also reports `.regular`
// horizontal size class and was inheriting those same Mac caps, so the board
// viewport was stuck in a 600pt square with ~540pt of blank space below it in
// portrait. PM ruling on #1101: iPad's board viewport should fill the whole
// board column (both width AND height), leaving cell sizing to the existing
// #764 `cellSizing` ladder — Mac's capped detail-pane behavior is unchanged.
//
// This is an `EnvironmentValue` rather than a `#if os(iOS)` constant because
// `swift test` only runs on macOS: the only way to exercise "the iPad rule"
// in a snapshot test or an ASC store-frame render on that host is to inject
// it explicitly. Production code still gets the right default for free via
// `platformDefault`.
public import SwiftUI

/// Which sizing rule a regular-width (iPad / Mac) host applies to the board
/// viewport in `MinesweeperBoardView.macLayout`.
public enum RegularBoardContainer: Sendable, Equatable {
    /// iPad: the board viewport receives the full board column's width AND
    /// height; `MinesweeperBoardView.cellSizing` (#764) picks the cell size
    /// from whatever rect it is offered. See #1101.
    case fillsColumn

    /// Mac detail pane: outer column capped to `macOuterMaxWidth` (900pt) and
    /// centered, board viewport capped to a `macBoardMaxSide` (600pt) square.
    /// Locked 2026-05-30 (#298 #6).
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
