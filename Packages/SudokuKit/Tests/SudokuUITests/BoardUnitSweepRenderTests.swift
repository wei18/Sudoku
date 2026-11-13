// BoardUnitSweepRenderTests (#1018) — pixels of the REAL `BoardView`, not unit
// tests of a plan. #1065 shipped a Reduce Motion form that was computed and
// never consumed by the rendered view while every unit test stayed green, so
// each claim here is proved by comparing renders taken before and after a
// placement. Harness: BoardSweepRenderSupport.swift.
//
// Measured facts the harness relies on (toy-view spike, #1018): a render of an
// `NSHostingView` taken right after a state change shows the FINAL state for an
// un-animated change and the INITIAL frame when a non-nil animation applies;
// animations never advance in a bare hosting view but do advance in real time
// when the hosting view is the content view of an `NSWindow` that is never
// ordered front (R3 uses that).

import Foundation
import GameShellUI
import SudokuEngine
import SudokuGameState
import SwiftUI
import Testing
@testable import SudokuUI

#if canImport(AppKit)
import AppKit

@MainActor
@Suite("BoardView — #1018 unit sweep, rendered pixels", .serialized, .enabled(if: !SnapshotEnv.isXcodeCloud))
struct BoardUnitSweepRenderTests {

    private typealias Rig = SweepRig

    private func rowIndices(_ row: Int) -> [Int] { SudokuUnit.row(row).cellIndices }

    // MARK: R1 — Reduce Motion: the whole row lights at once

    @Test("R1 Reduce Motion: all nine cells of the completed row light by a similar amount")
    func r1ReduceMotionLightsWholeRow() async throws {
        let gate = makeSweepGate()
        let viewModel = try Rig.makeViewModel(blanks: Rig.rowBlanks, gate: gate)
        let host = Rig.makeHost(viewModel, reduceMotion: true)
        let before = try SweepFrame(host)
        let grid = try Rig.findGrid(before)

        await viewModel.placeDigit(Rig.solution(0, 0), at: Rig.coord(0, 0))
        let after = try SweepFrame(host)

        let rowDeltas = rowIndices(0).map { Rig.delta(before, after, grid, $0) }
        let outside = [Board.index(row: 4, column: 4), Board.index(row: 8, column: 8), Board.index(row: 1, column: 5)]
            .map { Rig.delta(before, after, grid, $0) }
        Rig.report("R1 row", rowDeltas)
        Rig.report("R1 outside", outside)

        for (column, value) in rowDeltas.enumerated() {
            #expect(value > Rig.litThreshold, "row 0 column \(column) did not light (delta \(value))")
        }
        let lowest = rowDeltas.min() ?? 0
        let highest = rowDeltas.max() ?? 0
        #expect(highest / max(lowest, 0.001) < Rig.evennessRatio, "row cells lit unevenly: \(rowDeltas)")
        for value in outside {
            #expect(value < Rig.unlitThreshold, "a cell outside the row changed (delta \(value))")
        }
        await gate.release()
        await viewModel.cellFeedback.waitForPendingExpiries()
    }

    // MARK: R2 — default motion: the band starts at the leading cell

    @Test("R2 default motion: leading cell lit, trailing cell unchanged on the first frame")
    func r2DefaultMotionStartsAtLeadingCell() async throws {
        let gate = makeSweepGate()
        let viewModel = try Rig.makeViewModel(blanks: Rig.rowBlanks, gate: gate)
        let host = Rig.makeHost(viewModel, reduceMotion: false)
        let before = try SweepFrame(host)
        let grid = try Rig.findGrid(before)

        await viewModel.placeDigit(Rig.solution(0, 0), at: Rig.coord(0, 0))
        let after = try SweepFrame(host)

        let rowDeltas = rowIndices(0).map { Rig.delta(before, after, grid, $0) }
        Rig.report("R2 row", rowDeltas)

        #expect(rowDeltas[0] > Rig.litThreshold, "leading cell not lit (delta \(rowDeltas[0]))")
        #expect(rowDeltas[8] < Rig.unlitThreshold, "trailing cell already lit (delta \(rowDeltas[8]))")
        await gate.release()
        await viewModel.cellFeedback.waitForPendingExpiries()
    }

    // MARK: R3 — slow timing in a window: the band travels

    @Test("R3 slow timing in an offscreen window: lit at the leading cell, then reaches the trailing cell")
    func r3BandTravels() async throws {
        let gate = makeSweepGate()
        let viewModel = try Rig.makeViewModel(blanks: Rig.rowBlanks, gate: gate)
        let slow = CellFeedbackMotionPlan.Timing(unitSweep: 3, waveStagger: 0.5, cellFade: 1, waveCap: 9)
        let host = Rig.makeHost(viewModel, reduceMotion: false, timing: slow)
        // Never ordered front, never made key; torn down even on failure.
        let window = Rig.makeWindow(containing: host)
        defer {
            window.contentView = nil
            window.close()
        }

        let before = try SweepFrame(host)
        let grid = try Rig.findGrid(before)

        await viewModel.placeDigit(Rig.solution(0, 0), at: Rig.coord(0, 0))
        let first = try SweepFrame(host)
        let startDeltas = rowIndices(0).map { Rig.delta(before, first, grid, $0) }
        Rig.report("R3 start", startDeltas)
        #expect(startDeltas[0] > Rig.litThreshold, "leading cell not lit at the start (delta \(startDeltas[0]))")

        // Poll (hard bound 8 s, no retries around an assertion) for the band to reach the trailing cell.
        let deadline = Date().addingTimeInterval(8)
        var lastTrailing = startDeltas[8]
        var lastLeading = startDeltas[0]
        var reached = lastTrailing > Rig.touchedThreshold
        while !reached, Date() < deadline {
            spinRunLoop(0.05)
            let frame = try SweepFrame(host)
            lastTrailing = Rig.delta(before, frame, grid, 8)
            lastLeading = Rig.delta(before, frame, grid, 0)
            reached = lastTrailing > Rig.touchedThreshold
        }
        Rig.report("R3 trailing / leading when the band reached the trailing cell", [lastTrailing, lastLeading])
        #expect(reached, "waiting for the trailing cell (row 0, column 8) to light; last delta \(lastTrailing) after 8 s")
        // The light travelled: by the time it reaches the trailing end it has left the leading cell.
        #expect(lastLeading < Rig.unlitThreshold, "leading cell still lit (delta \(lastLeading)) when the band reached the trailing cell")

        await gate.release()
        await viewModel.cellFeedback.waitForPendingExpiries()
    }

    // MARK: R4 — resolves

    @Test("R4 after expiry every sampled cell of the row is back at its before value")
    func r4Resolves() async throws {
        let gate = makeSweepGate()
        let viewModel = try Rig.makeViewModel(blanks: Rig.rowBlanks, gate: gate)
        let host = Rig.makeHost(viewModel, reduceMotion: true)
        let before = try SweepFrame(host)
        let grid = try Rig.findGrid(before)

        await viewModel.placeDigit(Rig.solution(0, 0), at: Rig.coord(0, 0))
        let lit = try SweepFrame(host)
        #expect(Rig.delta(before, lit, grid, 3) > Rig.litThreshold, "precondition: the row was lit while the event was active")

        await gate.release()
        await viewModel.cellFeedback.waitForPendingExpiries()
        #expect(viewModel.cellFeedback.isIdle)
        let after = try SweepFrame(host)

        let rowDeltas = rowIndices(0).map { Rig.delta(before, after, grid, $0) }
        Rig.report("R4 row after expiry", rowDeltas)
        for (column, value) in rowDeltas.enumerated() {
            #expect(value < Rig.unlitThreshold, "row 0 column \(column) still lit after expiry (delta \(value))")
        }
    }

    // MARK: R5 — column and box geometry

    @Test("R5 column: exactly that column's cells light")
    func r5ColumnGeometry() async throws {
        // (0,0) + (0,1) blank: filling (0,0) completes column 0 only (row 0 and box 0 keep (0,1)).
        try await assertLitCells(blanks: [Rig.coord(0, 0), Rig.coord(0, 1)], place: Rig.coord(0, 0), unit: .column(0))
    }

    @Test("R5 box: exactly that box's cells light")
    func r5BoxGeometry() async throws {
        // (0,0) + (0,3) + (4,0) blank: filling (0,0) completes box 0 only.
        try await assertLitCells(
            blanks: [Rig.coord(0, 0), Rig.coord(0, 3), Rig.coord(4, 0)], place: Rig.coord(0, 0), unit: .box(0)
        )
    }

    private func assertLitCells(
        blanks: Set<GridCoordinate>,
        place: GridCoordinate,
        unit: SudokuUnit
    ) async throws {
        let gate = makeSweepGate()
        let viewModel = try Rig.makeViewModel(blanks: blanks, gate: gate)
        let host = Rig.makeHost(viewModel, reduceMotion: true)
        let before = try SweepFrame(host)
        let grid = try Rig.findGrid(before)

        await viewModel.placeDigit(Rig.solution(place.row, place.column), at: place)
        #expect(viewModel.cellFeedback.activeEvents.map(\.event.units) == [[unit]])
        let after = try SweepFrame(host)

        let deltas = (0..<Board.cellCount).map { Rig.delta(before, after, grid, $0) }
        let litIndices = Set(deltas.indices.filter { deltas[$0] > Rig.litThreshold })
        let unlitMax = deltas.indices.filter { !unit.cellIndices.contains($0) }.map { deltas[$0] }.max() ?? 0
        Rig.report("R5 \(unit) unit cells", unit.cellIndices.map { deltas[$0] })
        Rig.report("R5 \(unit) max outside", [unlitMax])
        #expect(litIndices == Set(unit.cellIndices), "lit cells \(litIndices.sorted()) != unit cells \(unit.cellIndices.sorted())")
        #expect(unlitMax < Rig.unlitThreshold)
        await gate.release()
        await viewModel.cellFeedback.waitForPendingExpiries()
    }
}
#endif
