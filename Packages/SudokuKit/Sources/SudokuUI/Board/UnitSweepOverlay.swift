// UnitSweepOverlay — draws the #1018 unit sweep (design.md §6 M12) over every
// row / column / box that a placement just completed.
//
// One `ForEach` item per (event, unit), each a transparent board-sized view
// whose INSERTION TRANSITION paints the light: the transition's initial phase
// is the first frame (a band over the unit's leading cells / the whole unit
// lit) and its identity phase is the last (band fully past the trailing edge /
// nothing lit). Because the light lives in the transition, an event that
// appears, plays once and is removed needs no `.onAppear` bootstrap and no
// stored progress, and a removal changes nothing visible.
//
// The body is a `ZStack { ForEach }`, and the `.animation(_, value:)` sits on
// that ZStack, not on the `ForEach`: measured (#1018), an animation attached to
// a bare `ForEach` gives its insertions no animation context and the
// transition never plays (every render showed the final, un-lit state), while
// the same modifier on a container does. With no active events the `ForEach`
// is empty, so the ZStack contributes no pixels and settled-state snapshots
// cannot move. It never reads or writes the view model's feedback state
// beyond the entries it is handed.

import GameShellUI
import SudokuEngine
import SwiftUI

struct UnitSweepOverlay: View {
    typealias Entry = CellFeedbackState<SudokuCellFeedbackEvent>.Entry

    /// One drawn sweep: an event's unit, identified by the event's token.
    struct Item: Hashable, Identifiable {
        let token: CellFeedbackState<SudokuCellFeedbackEvent>.Token
        let unit: SudokuUnit
        var id: Self { self }
    }

    let entries: [Entry]
    let plan: CellFeedbackMotionPlan
    /// Side of the square 9x9 grid, in points.
    let boardSide: CGFloat
    @Environment(\.theme) private var theme

    /// Opacity of the light at its brightest — low enough to read as "light
    /// passing" in both themes without hiding digits.
    nonisolated static let lightOpacity = 0.25

    nonisolated static func items(for entries: [Entry]) -> [Item] {
        entries.flatMap { entry in entry.event.units.map { Item(token: entry.token, unit: $0) } }
    }

    var body: some View {
        let items = Self.items(for: entries)
        ZStack {
            ForEach(items) { item in
                Color.clear
                    .frame(width: boardSide, height: boardSide)
                    .transition(UnitSweepTransition(
                        form: plan.unitSweep,
                        unit: item.unit,
                        cellSide: boardSide / CGFloat(Board.dimension),
                        tint: theme.accent.primary.resolved
                    ))
            }
        }
        .animation(Self.animation(for: plan.unitSweep), value: items)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Travel is linear; the static flash eases out as it fades.
    nonisolated static func animation(for form: CellFeedbackMotionPlan.UnitSweepForm) -> Animation {
        switch form {
        case let .sweep(duration): .linear(duration: duration)
        case let .staticFlash(duration): .easeOut(duration: duration)
        }
    }

    /// The unit's rectangle on the grid, in the grid's own coordinates.
    nonisolated static func rect(of unit: SudokuUnit, cellSide: CGFloat) -> CGRect {
        switch unit {
        case let .row(row):
            CGRect(x: 0, y: CGFloat(row) * cellSide, width: 9 * cellSide, height: cellSide)
        case let .column(column):
            CGRect(x: CGFloat(column) * cellSide, y: 0, width: cellSide, height: 9 * cellSide)
        case let .box(box):
            CGRect(
                x: CGFloat(box % 3) * 3 * cellSide,
                y: CGFloat(box / 3) * 3 * cellSide,
                width: 3 * cellSide,
                height: 3 * cellSide
            )
        }
    }

    /// Row and box sweeps run leading→trailing, a column top→bottom.
    nonisolated static func travelsHorizontally(_ unit: SudokuUnit) -> Bool {
        if case .column = unit { return false }
        return true
    }
}

/// First frame: the light sits over the unit's leading end (sweep) or covers
/// the whole unit (static flash). Identity: the band is past the trailing edge
/// / the flash has faded. Removal keeps the identity look, so nothing moves.
private struct UnitSweepTransition: Transition {
    let form: CellFeedbackMotionPlan.UnitSweepForm
    let unit: SudokuUnit
    let cellSide: CGFloat
    let tint: Color

    func body(content: Content, phase: TransitionPhase) -> some View {
        let rect = UnitSweepOverlay.rect(of: unit, cellSide: cellSide)
        let isFirstFrame = phase == .willAppear
        return content.overlay(alignment: .topLeading) {
            light(in: rect, isFirstFrame: isFirstFrame)
                .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                .clipped()
                .offset(x: rect.minX, y: rect.minY)
        }
    }

    @ViewBuilder
    private func light(in rect: CGRect, isFirstFrame: Bool) -> some View {
        switch form {
        case .sweep:
            band(in: rect, progress: isFirstFrame ? 0 : 1)
        case .staticFlash:
            tint.opacity(isFirstFrame ? UnitSweepOverlay.lightOpacity : 0)
        }
    }

    /// A soft band a third of the unit long, travelling once along it.
    private func band(in rect: CGRect, progress: CGFloat) -> some View {
        let horizontal = UnitSweepOverlay.travelsHorizontally(unit)
        let length = horizontal ? rect.width : rect.height
        let bandLength = length / 3
        let light = tint.opacity(UnitSweepOverlay.lightOpacity)
        return LinearGradient(
            stops: [
                .init(color: tint.opacity(0), location: 0),
                .init(color: light, location: 0.25),
                .init(color: light, location: 0.75),
                .init(color: tint.opacity(0), location: 1),
            ],
            startPoint: horizontal ? .leading : .top,
            endPoint: horizontal ? .trailing : .bottom
        )
        .frame(
            width: horizontal ? bandLength : rect.width,
            height: horizontal ? rect.height : bandLength
        )
        .offset(
            x: horizontal ? progress * length : 0,
            y: horizontal ? 0 : progress * length
        )
    }
}
