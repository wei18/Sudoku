// MinesweeperRevealWaveRenderTests (#1018, design.md §6 M13) — pixels of the
// REAL `MinesweeperBoardView`, not unit tests of a plan. A Reduce Motion form
// can be computed and never consumed by the rendered view while every unit
// test stays green (#1065), so each claim here is proved by comparing renders
// taken before and after a reveal.
//
// Measured facts the harness relies on (toy-view spike, #1018): a render of an
// `NSHostingView` taken right after a state change shows the FINAL state for an
// un-animated change and the INITIAL frame when a non-nil animation applies;
// animations never advance in a bare hosting view but do advance in real time
// when the hosting view is the content view of an `NSWindow` that is never
// ordered front (W3 / W4 use that).
//
// Board: 9x9, a tap at (0,0) floods nearly everything (rings 0...8). (8,4) is
// the farthest revealed cell (ring 8), (3,3) is ring 3; (8,8) is a hidden mine
// and (6,6) a hidden safe pocket, both outside the region and never touched.

import Foundation
import GameShellUI
import MinesweeperEngine
import SwiftUI
import Testing
@testable import MinesweeperUI

#if canImport(AppKit)
import AppKit

@MainActor
@Suite("MinesweeperBoardView — #1018 reveal wave, rendered pixels", .serialized, .enabled(if: !SnapshotEnv.isXcodeCloud))
struct MinesweeperRevealWaveRenderTests {

    private typealias Rig = WaveRig

    private static let far = (row: 8, col: 4)
    private static let ringThree = (row: 3, col: 3)
    private static let outsideCells = [(row: 8, col: 8), (row: 6, col: 6), (row: 5, col: 5)]

    private func outsideDeltas(_ before: WaveFrame, _ after: WaveFrame, _ grid: WaveGrid) -> [Double] {
        Self.outsideCells.map { Rig.delta(before, after, grid, row: $0.row, col: $0.col) }
    }

    // MARK: W1 — Reduce Motion: the whole region appears at once

    @Test("W1 Reduce Motion: the tapped cell and a far cell both read revealed on the first render")
    func w1ReduceMotionRevealsAtOnce() async throws {
        let gate = makeFeedbackGate()
        let viewModel = try FeedbackBoard.oneBigRegion.viewModel(gate: gate)
        let host = Rig.makeHost(viewModel, reduceMotion: true)
        let before = try WaveFrame(host)
        let grid = try Rig.findGrid(before, rows: 9, cols: 9)

        await viewModel.reveal(row: 0, col: 0)
        let after = try WaveFrame(host)

        let tapped = Rig.delta(before, after, grid, row: 0, col: 0)
        let farDelta = Rig.delta(before, after, grid, row: Self.far.row, col: Self.far.col)
        let outside = outsideDeltas(before, after, grid)
        Rig.report("W1 tapped / far", [tapped, farDelta])
        Rig.report("W1 outside", outside)

        #expect(tapped > Rig.litThreshold, "tapped cell still reads hidden (delta \(tapped))")
        #expect(farDelta > Rig.litThreshold, "far cell (ring 8) still reads hidden (delta \(farDelta))")
        for value in outside { #expect(value < Rig.unlitThreshold, "a cell outside the region changed (delta \(value))") }
        await gate.release()
        await viewModel.cellFeedback.waitForPendingExpiries()
    }

    // MARK: W2 — default motion: the first frame is still the hidden board

    @Test("W2 default motion: the tapped cell and the far cell still read hidden on the first render")
    func w2DefaultMotionStartsHidden() async throws {
        let gate = makeFeedbackGate()
        let viewModel = try FeedbackBoard.oneBigRegion.viewModel(gate: gate)
        let host = Rig.makeHost(viewModel, reduceMotion: false)
        let before = try WaveFrame(host)
        let grid = try Rig.findGrid(before, rows: 9, cols: 9)

        await viewModel.reveal(row: 0, col: 0)
        let after = try WaveFrame(host)

        let tapped = Rig.delta(before, after, grid, row: 0, col: 0)
        let farDelta = Rig.delta(before, after, grid, row: Self.far.row, col: Self.far.col)
        let outside = outsideDeltas(before, after, grid)
        Rig.report("W2 tapped / far", [tapped, farDelta])
        Rig.report("W2 outside", outside)

        // The glyph must not appear ahead of its tile: the far cell's CENTRE (where its number is drawn).
        let farGlyph = Rig.delta(before, after, grid, row: Self.far.row, col: Self.far.col, at: .center)
        Rig.report("W2 far cell centre (glyph)", [farGlyph])

        #expect(tapped < Rig.unlitThreshold, "tapped cell already reads revealed (delta \(tapped))")
        #expect(farDelta < Rig.unlitThreshold, "far cell already reads revealed (delta \(farDelta))")
        #expect(farGlyph < Rig.unlitThreshold, "far cell's number is already painted (centre delta \(farGlyph)) while its tile is not")
        for value in outside { #expect(value < Rig.unlitThreshold, "a cell outside the region changed (delta \(value))") }
        await gate.release()
        await viewModel.cellFeedback.waitForPendingExpiries()
    }

    // MARK: W3 — slow timing in a window: the tapped cell appears, a far cell has not

    @Test("W3 slow timing in an offscreen window: the tapped cell reads revealed while a ring-3 and a ring-8 cell still read hidden")
    func w3WaveIsStaggered() async throws {
        let gate = makeFeedbackGate(watchdog: .seconds(30))
        let viewModel = try FeedbackBoard.oneBigRegion.viewModel(gate: gate)
        let host = Rig.makeHost(viewModel, reduceMotion: false, timing: Rig.slowTiming)
        let window = Rig.makeWindow(containing: host)
        defer {
            window.contentView = nil
            window.close()
        }
        let before = try WaveFrame(host)
        let grid = try Rig.findGrid(before, rows: 9, cols: 9)

        await viewModel.reveal(row: 0, col: 0)

        // Poll (hard bound 8 s, no retries around an assertion) for the tapped cell to appear.
        let deadline = Date().addingTimeInterval(8)
        var tapped = 0.0
        var frame = try WaveFrame(host)
        while Date() < deadline {
            frame = try WaveFrame(host)
            tapped = Rig.delta(before, frame, grid, row: 0, col: 0)
            if tapped > Rig.litThreshold { break }
            spinRunLoop(0.02)
        }
        #expect(tapped > Rig.litThreshold, "waiting for the tapped cell (0,0) to read revealed; last delta \(tapped) after 8 s")

        let ringThree = Rig.delta(before, frame, grid, row: Self.ringThree.row, col: Self.ringThree.col)
        let farDelta = Rig.delta(before, frame, grid, row: Self.far.row, col: Self.far.col)
        let outside = outsideDeltas(before, frame, grid)
        Rig.report("W3 tapped / ring3 / far when the tapped cell appeared", [tapped, ringThree, farDelta])
        let farGlyph = Rig.delta(before, frame, grid, row: Self.far.row, col: Self.far.col, at: .center)
        Rig.report("W3 far cell centre (glyph)", [farGlyph])
        #expect(farGlyph < Rig.unlitThreshold, "far cell's number is already painted (centre delta \(farGlyph)) — the glyph is not staggered")
        #expect(ringThree < Rig.unlitThreshold, "ring-3 cell already reads revealed (delta \(ringThree)) — the wave is not staggered")
        #expect(farDelta < Rig.unlitThreshold, "ring-8 cell already reads revealed (delta \(farDelta)) — the wave is not staggered")
        for value in outside { #expect(value < Rig.unlitThreshold, "a cell outside the region changed (delta \(value))") }

        await gate.release()
        await viewModel.cellFeedback.waitForPendingExpiries()
    }

    // MARK: W4 — design timing in a window: the wave finishes and settles to the ordinary revealed board

    @Test("W4 design timing in an offscreen window: the far cell appears and the settled board equals the instant (Reduce Motion) one")
    func w4WaveCompletes() async throws {
        // Reference: the same reveal under Reduce Motion (instant), rendered in
        // a window too — a window render and a bare-host render differ in colour.
        let referenceGate = makeFeedbackGate()
        let referenceModel = try FeedbackBoard.oneBigRegion.viewModel(gate: referenceGate)
        let referenceHost = Rig.makeHost(referenceModel, reduceMotion: true)
        let referenceWindow = Rig.makeWindow(containing: referenceHost)
        defer {
            referenceWindow.contentView = nil
            referenceWindow.close()
        }
        let referenceBefore = try WaveFrame(referenceHost)
        let grid = try Rig.findGrid(referenceBefore, rows: 9, cols: 9)
        await referenceModel.reveal(row: 0, col: 0)
        let reference = try WaveFrame(referenceHost)
        await referenceGate.release()

        let gate = makeFeedbackGate(watchdog: .seconds(30))
        let viewModel = try FeedbackBoard.oneBigRegion.viewModel(gate: gate)
        let host = Rig.makeHost(viewModel, reduceMotion: false)
        let window = Rig.makeWindow(containing: host)
        defer {
            window.contentView = nil
            window.close()
        }
        let before = try WaveFrame(host)

        await viewModel.reveal(row: 0, col: 0)

        let started = Date()
        let deadline = started.addingTimeInterval(8)
        var farDelta = 0.0
        var tappedSeconds: Double?
        while Date() < deadline {
            let frame = try WaveFrame(host)
            if tappedSeconds == nil, Rig.delta(before, frame, grid, row: 0, col: 0) > Rig.litThreshold {
                tappedSeconds = Date().timeIntervalSince(started)
            }
            farDelta = Rig.delta(before, frame, grid, row: Self.far.row, col: Self.far.col)
            if farDelta > Rig.litThreshold { break }
            spinRunLoop(0.02)
        }
        let waited = Date().timeIntervalSince(started)
        Rig.report("W4 far cell delta / seconds until far read revealed / seconds until tapped read revealed", [farDelta, waited, tappedSeconds ?? -1])
        #expect(farDelta > Rig.litThreshold, "waiting for the far cell (8,4) to read revealed; last delta \(farDelta) after 8 s")

        // Settled: every cell equals the instant render.
        spinRunLoop(0.6)
        let settled = try WaveFrame(host)
        var worst = 0.0
        var worstCell = (row: 0, col: 0)
        for row in 0..<9 {
            for col in 0..<9 {
                let difference = Rig.delta(reference, settled, grid, row: row, col: col)
                if difference > worst { worst = difference; worstCell = (row, col) }
            }
        }
        Rig.report("W4 worst settled-vs-instant cell delta", [worst])
        #expect(worst < Rig.unlitThreshold, "settled cell (\(worstCell.row),\(worstCell.col)) differs from the instant render by \(worst)")
        let outside = outsideDeltas(before, settled, grid)
        for value in outside { #expect(value < Rig.unlitThreshold, "a cell outside the region changed (delta \(value))") }

        // After expiry: release the held sleeper, let the event end, render again in the same window.
        await gate.release()
        await viewModel.cellFeedback.waitForPendingExpiries()
        #expect(viewModel.cellFeedback.isIdle)
        let expired = try WaveFrame(host)
        var worstAfterExpiry = 0.0
        var worstExpiredCell = (row: 0, col: 0)
        for row in 0..<9 {
            for col in 0..<9 {
                let difference = Rig.delta(reference, expired, grid, row: row, col: col)
                if difference > worstAfterExpiry { worstAfterExpiry = difference; worstExpiredCell = (row, col) }
            }
        }
        Rig.report("W4 worst post-expiry-vs-instant cell delta", [worstAfterExpiry])
        #expect(
            worstAfterExpiry < Rig.unlitThreshold,
            "after expiry cell (\(worstExpiredCell.row),\(worstExpiredCell.col)) differs from the instant render by \(worstAfterExpiry)"
        )
    }
}
#endif
