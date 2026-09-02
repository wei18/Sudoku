// BoardPreviewView — renders a `BoardPreview` (#1017) as a density/progress
// thumbnail (#1021 Phase A, design.md §3.1/§3.2).
//
// Digits are NEVER drawn — illegible-by-intent (design.md §3.1: "縮圖尺寸下
// 數字不可讀,這是刻意的...它傳達的是密度與進度,不是內容"). The thumbnail is
// also never the sole progress channel: every card that hosts this view pairs
// it with a text status, and this view marks itself `.accessibilityHidden(true)`
// so VoiceOver skips straight to that text (design.md §3.1 official-quote
// callout, design.md §7 "顏色非唯一通道").
//
// `Canvas` draws cell fills + a thin grid in one pass — no per-cell subviews,
// so a 30×16 Minesweeper board thumbnail costs one draw call, not 480 view
// instances. No `.animation`/`.transition` is applied anywhere in this file:
// reduce-motion-safe by construction, not by branching on the environment.
//
// `isAccessibilityHidden` is a plain `Bool` constant (not introspectable
// SwiftUI state) so a test can pin the "always hidden" contract without
// rendering the view — this package carries no snapshot-testing dependency
// (see PHASE A REPORT for why visual snapshot coverage isn't in this file).

public import SwiftUI

public struct BoardPreviewView: View {
    @Environment(\.theme) private var theme

    /// `true` for `BoardPreviewView`, unconditionally — every instance
    /// applies `.accessibilityHidden(true)` in `body`. Exposed as a design
    /// constant (not derived from a live view) so it can be asserted without
    /// instantiating/rendering SwiftUI.
    public static let isAccessibilityHidden = true

    private let preview: BoardPreview?
    private let columns: Int
    private let rows: Int

    /// Draws `preview`'s real cell marks.
    public init(preview: BoardPreview) {
        self.preview = preview
        self.columns = preview.columns
        self.rows = preview.rows
    }

    private init(skeletonColumns: Int, skeletonRows: Int) {
        self.preview = nil
        self.columns = skeletonColumns
        self.rows = skeletonRows
    }

    /// Loading placeholder: grid-line structure only, no cell fills
    /// (design.md §3.1 "保留格線結構,不是空白方塊" — a blank rectangle would
    /// read as "nothing here" rather than "still loading").
    public static func skeleton(columns: Int, rows: Int) -> BoardPreviewView {
        BoardPreviewView(skeletonColumns: columns, skeletonRows: rows)
    }

    public var body: some View {
        Canvas { context, size in
            paint(in: &context, size: size)
        }
        .aspectRatio(CGFloat(columns) / CGFloat(rows), contentMode: .fit)
        .accessibilityHidden(Self.isAccessibilityHidden)
    }

    private func paint(in context: inout GraphicsContext, size: CGSize) {
        guard columns > 0, rows > 0 else { return }
        let cellWidth = size.width / CGFloat(columns)
        let cellHeight = size.height / CGFloat(rows)

        if let preview {
            for (index, mark) in preview.cells.enumerated() {
                guard mark != .empty else { continue }
                let column = index % columns
                let row = index / columns
                let rect = CGRect(
                    x: CGFloat(column) * cellWidth,
                    y: CGFloat(row) * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                )
                context.fill(Path(rect), with: .color(color(for: mark)))
            }
        }

        context.stroke(gridPath(cellWidth: cellWidth, cellHeight: cellHeight, size: size), with: .color(gridLineColor), lineWidth: 0.5)
    }

    private func gridPath(cellWidth: CGFloat, cellHeight: CGFloat, size: CGSize) -> Path {
        var path = Path()
        for column in 0...columns {
            let lineX = CGFloat(column) * cellWidth
            path.move(to: CGPoint(x: lineX, y: 0))
            path.addLine(to: CGPoint(x: lineX, y: size.height))
        }
        for row in 0...rows {
            let lineY = CGFloat(row) * cellHeight
            path.move(to: CGPoint(x: 0, y: lineY))
            path.addLine(to: CGPoint(x: size.width, y: lineY))
        }
        return path
    }

    /// `.empty` is skipped entirely by `paint(in:size:)` (nothing to fill —
    /// the background shows through), so this is never actually looked up for
    /// `.empty`; kept exhaustive so a new `CellMark` case fails to compile
    /// here instead of silently rendering unstyled.
    private func color(for mark: CellMark) -> Color {
        switch mark {
        case .empty: theme.surface.background.resolved
        case .given: theme.text.given.resolved.opacity(0.7)
        case .filled: theme.accent.primary.resolved
        case .marked: theme.status.warning.resolved
        }
    }

    /// Same token in both the real-preview and skeleton grid — keeps the
    /// "loading" and "loaded" states reading as the same board geometry
    /// settling in, not two different visual languages.
    private var gridLineColor: Color {
        theme.surface.placeholder.resolved
    }
}
