// BoardControlClusterLayout — a geometric argument for design.md §7's hard
// rule, in a form a test can check at every width and cluster height.
//
// §7, verbatim: "**G4 不得覆蓋任何可互動格子** —— 這是版面規則,幾何不隨開關改變,
// **必須以最壞情況(IC+RT)為設計基準**".
//
// ## What actually guarantees the rule — and it is not this file
//
// Non-overlap is STRUCTURAL in the views: the board and the cluster are
// siblings in one `VStack`, SwiftUI does not overlap stack siblings, and
// nothing clips. That is the guarantee. This type does not enforce it, is not
// called from production, and deliberately does not try to simulate SwiftUI's
// layout — a model that claimed to would be a second, unverified layout engine
// whose agreement with the real one nobody checks.
//
// What it IS: the same top-down arrangement stated as arithmetic — margin,
// header, board band, cluster — so the CONSEQUENCE of that arrangement can be
// asserted across the whole input space instead of trusted at the one width a
// screenshot happens to show. It answers "given this arrangement, can any cell
// rect ever meet a group rect?" and the answer is no, at every breakpoint and
// every cluster height. Treat a failure here as "the arrangement described in
// the tests is wrong", not "the app overlapped something".
//
// ## What it cannot see
//
// The real residual risk is a cluster tall enough to overflow the screen — at
// which point SwiftUI compresses or pushes content rather than overlapping it,
// so §7 still holds but the board can be squeezed to uselessness. That is a
// real failure mode and it is #1055 (iPhone SE already measures 26.1pt cells,
// under §3.4's own 28pt floor); it is a sizing problem, not an overlap one.
//
// It also does not model the banner slot, and its callers pass idealised
// chrome heights rather than measured ones. Both are fine for the property
// being argued — it is monotonic in total chrome height, so more chrome only
// shrinks the board — but they are why this is an argument about the shape of
// the layout, not a measurement of the app.
//
// ## Why the accessibility switches are absent
//
// Increase Contrast and Reduce Transparency change how glass is PAINTED, never
// how much room it occupies, so there is no switch for `bands(...)` to read.
// Dynamic Type is the input that can genuinely grow a cluster, and the tests
// sweep it well past the `.xLarge` cap these compact controls carry (#540).
// Glass DEGRADATION under those switches is a separate obligation §7 also
// states, discharged by the simulator sweep on #1022's PR, not here.
//
// Deliberately NOT a fixed metrics table: freezing the group heights and
// rendering them with `.frame(height:)` would make the numbers true by force
// and hide a real overflow behind a clip. Heights are inputs.

internal import CoreGraphics

enum BoardControlClusterLayout {

    /// Where the board square and each glass group land inside the offered box.
    ///
    /// `editGroup` is `nil` for a single-group cluster — Minesweeper today,
    /// which has no edit-group controls (see #1052).
    struct Bands: Equatable, Sendable {
        let board: CGRect
        let editGroup: CGRect?
        let inputGroup: CGRect

        init(board: CGRect, editGroup: CGRect?, inputGroup: CGRect) {
            self.board = board
            self.editGroup = editGroup
            self.inputGroup = inputGroup
        }

        /// Every glass group present, in render order.
        var glassGroups: [CGRect] {
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
    ///   - stackGapCount: how many such gaps the arrangement has.
    ///   - safeAreaTop/safeAreaBottom: the device insets the stack is laid out
    ///     inside. Not cosmetic — omitting them made the model predict a
    ///     402pt board where the device renders 392.5pt, which is how the
    ///     measured anchor in the tests earns its keep.
    ///   - editGroupHeight: rendered height of the edit group, or `nil` when
    ///     the game has no edit-group controls.
    ///   - inputGroupHeight: rendered height of the input group.
    ///   - groupSpacing: the gap between the two groups inside the cluster.
    static func bands(
        offered: CGSize,
        verticalMargin: CGFloat,
        headerHeight: CGFloat,
        stackSpacing: CGFloat,
        stackGapCount: Int,
        safeAreaTop: CGFloat = 0,
        safeAreaBottom: CGFloat = 0,
        editGroupHeight: CGFloat?,
        inputGroupHeight: CGFloat,
        groupSpacing: CGFloat
    ) -> Bands {
        let clusterHeight = (editGroupHeight.map { $0 + groupSpacing } ?? 0) + inputGroupHeight
        // `stackGapCount` is the caller's, not a constant here: neither app has
        // a fixed number of gaps (the banner slot comes and goes), and hard-
        // coding one would assert a correspondence with real code that nothing
        // checks. The property under test is monotonic in total chrome, so the
        // exact count only moves where on the sweep a given case lands.
        let chrome = safeAreaTop + safeAreaBottom + verticalMargin * 2 + headerHeight
            + clusterHeight + stackSpacing * CGFloat(stackGapCount)
        let boardSide = max(0, min(offered.width, offered.height - chrome))

        // The cluster is bottom-anchored; everything between the header and it
        // is the board's band, and the square centres inside that band (both
        // games do: Minesweeper's grid centres in its fitted branch, #764, and
        // Sudoku's square centres in a `.frame(maxHeight: .infinity)`).
        // Centring can only move the square further from the header, never
        // past the band's bottom edge — which is what keeps the rule below
        // true no matter how tall the band gets.
        let clusterTop = offered.height - safeAreaBottom - verticalMargin - clusterHeight
        let bandTop = safeAreaTop + verticalMargin + headerHeight + stackSpacing
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
    static func cellRects(in board: CGRect, rows: Int, columns: Int) -> [CGRect] {
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
    static func fullBleedCellSide(screenWidth: CGFloat, columns: Int) -> CGFloat {
        guard columns > 0 else { return 0 }
        return screenWidth / CGFloat(columns)
    }
}
