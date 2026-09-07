// BoardControlClusterLayout — the pure vertical-band algebra behind the board
// screen's compact arrangement, extracted so design.md §7's hard rule can be
// ASSERTED rather than eyeballed.
//
// §7, verbatim: "**G4 不得覆蓋任何可互動格子** —— 這是版面規則,幾何不隨開關改變,
// **必須以最壞情況(IC+RT)為設計基準**". Two claims, and they need different
// kinds of proof:
//
//   1. G4 never covers an interactive cell.
//   2. That is a LAYOUT rule whose geometry does not shift with the
//      accessibility switches, so it must hold at the worst case.
//
// Claim 1 is structural in the view: the board square and the cluster are
// siblings in one `VStack`, and SwiftUI never overlaps stack siblings. This
// type does not re-implement SwiftUI's layout — it states the same top-down
// band assignment the view builds (margin / header / board / flexible gap /
// cluster) so the consequence can be checked numerically at every width and
// every cluster height, instead of trusting a screenshot at one size.
//
// Claim 2 is why `bands(...)` takes NO accessibility parameter. Increase
// Contrast and Reduce Transparency change how the glass is PAINTED, never how
// much room it occupies, so there is no switch for them to read. What can
// legitimately change the cluster's height is Dynamic Type — capped at
// `.xLarge` for these compact controls (#540) — so the worst case is simply a
// taller cluster, and the property the tests pin is that the rule survives
// ANY cluster height: the board yields the space, the cluster never encroaches.
//
// Deliberately NOT a fixed metrics table. Freezing the groups' heights here
// and rendering them with `.frame(height:)` would make the numbers true by
// force and hide a real overflow behind a clip; taking the heights as INPUTS
// keeps the check honest at whatever height the controls actually render.

public import CoreGraphics

public enum BoardControlClusterLayout {

    /// Where the board square and each glass group land inside the offered box.
    ///
    /// `editGroup` is `nil` for a single-group cluster — Minesweeper today,
    /// which has no edit-group controls (see #1052).
    public struct Bands: Equatable, Sendable {
        public let board: CGRect
        public let editGroup: CGRect?
        public let inputGroup: CGRect

        public init(board: CGRect, editGroup: CGRect?, inputGroup: CGRect) {
            self.board = board
            self.editGroup = editGroup
            self.inputGroup = inputGroup
        }

        /// Every glass group present, in render order.
        public var glassGroups: [CGRect] {
            [editGroup, inputGroup].compactMap(\.self)
        }
    }

    /// Assign vertical bands for the compact board screen.
    ///
    /// Mirrors the `VStack` the boards build, top-down: vertical margin,
    /// header, the full-bleed board square, a flexible gap, then the cluster's
    /// groups. The board is full-bleed horizontally (no inset at all, #1022)
    /// and therefore square at `min(width, whatever height is left)` — the
    /// chrome is subtracted FIRST, which is what makes the non-overlap
    /// structural: whatever the cluster needs, the board is what gives way.
    ///
    /// - Parameters:
    ///   - offered: the screen box the board scene is laid out in.
    ///   - verticalMargin: the screen margin above the header and below the
    ///     cluster.
    ///   - headerHeight: the board header's rendered height.
    ///   - stackSpacing: the gap the outer `VStack` puts between its children.
    ///   - editGroupHeight: rendered height of the edit group, or `nil` when
    ///     the game has no edit-group controls.
    ///   - inputGroupHeight: rendered height of the input group.
    ///   - groupSpacing: the gap between the two groups inside the cluster.
    public static func bands(
        offered: CGSize,
        verticalMargin: CGFloat,
        headerHeight: CGFloat,
        stackSpacing: CGFloat,
        editGroupHeight: CGFloat?,
        inputGroupHeight: CGFloat,
        groupSpacing: CGFloat
    ) -> Bands {
        let clusterHeight = (editGroupHeight.map { $0 + groupSpacing } ?? 0) + inputGroupHeight
        // Children in the stack: header, board, cluster (+ the flexible gap,
        // which contributes no spacing of its own beyond the stack's).
        let chrome = verticalMargin * 2 + headerHeight + clusterHeight + stackSpacing * 3
        let boardSide = max(0, min(offered.width, offered.height - chrome))

        // The cluster is bottom-anchored; everything between the header and it
        // is the board's band, and the square centres inside that band (both
        // games do: Minesweeper's grid centres in its fitted branch, #764, and
        // Sudoku's square centres in a `.frame(maxHeight: .infinity)`).
        // Centring can only move the square further from the header, never
        // past the band's bottom edge — which is what keeps the rule below
        // true no matter how tall the band gets.
        let clusterTop = offered.height - verticalMargin - clusterHeight
        let bandTop = verticalMargin + headerHeight + stackSpacing
        let bandHeight = max(0, clusterTop - stackSpacing - bandTop)
        let board = CGRect(
            x: (offered.width - boardSide) / 2,
            y: bandTop + (bandHeight - boardSide) / 2,
            width: boardSide,
            height: boardSide
        )
        var cursor = clusterTop
        var edit: CGRect?
        if let editGroupHeight {
            edit = CGRect(x: 0, y: cursor, width: offered.width, height: editGroupHeight)
            cursor += editGroupHeight + groupSpacing
        }
        let input = CGRect(x: 0, y: cursor, width: offered.width, height: inputGroupHeight)

        return Bands(board: board, editGroup: edit, inputGroup: input)
    }

    /// The interactive cell rects of a `rows` × `columns` board filling `board`.
    ///
    /// Cells tile the square exactly (the grid's own seams are cell geometry,
    /// not spacing — design.md §3.4 retracted "zero gap" as a sizing
    /// mitigation but the seams themselves were never padding), so this is the
    /// full hit-test area §7 says G4 must stay clear of.
    public static func cellRects(in board: CGRect, rows: Int, columns: Int) -> [CGRect] {
        guard rows > 0, columns > 0, board.width > 0, board.height > 0 else { return [] }
        let cellWidth = board.width / CGFloat(columns)
        let cellHeight = board.height / CGFloat(rows)
        return (0..<rows).flatMap { row in
            (0..<columns).map { column in
                CGRect(
                    x: board.minX + CGFloat(column) * cellWidth,
                    y: board.minY + CGFloat(row) * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                )
            }
        }
    }

    /// The full-bleed cell side design.md §3.4's table is about: the offered
    /// screen width divided by the board's column count, with no inset.
    public static func fullBleedCellSide(screenWidth: CGFloat, columns: Int) -> CGFloat {
        guard columns > 0 else { return 0 }
        return screenWidth / CGFloat(columns)
    }
}
