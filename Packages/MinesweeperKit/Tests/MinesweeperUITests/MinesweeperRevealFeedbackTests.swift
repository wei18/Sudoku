// MinesweeperRevealFeedbackTests (#1018, design.md §6 M13) — the Minesweeper
// view-model half of the region-reveal wave: a tap that newly reveals more
// than one safe cell begins ONE event carrying every newly revealed cell's
// ring (Chebyshev distance from the tapped cell), the event expires on its
// own, and feedback never blocks or drops input (the VM only WRITES to the
// feedback state). Expiry is released by hand through an injected sleeper and
// settled by awaiting the expiry Task's value, never by `Task.yield()`.

import Foundation
import GameShellUI
import MinesweeperEngine
import MinesweeperGameState
import Testing
@testable import MinesweeperUI

@MainActor
@Suite("MinesweeperGameViewModel — #1018 reveal-wave feedback")
struct MinesweeperRevealFeedbackTests {

    private func settle(_ viewModel: MinesweeperGameViewModel) async {
        await viewModel.cellFeedback.waitForPendingExpiries()
    }

    // MARK: V1 — a flood reveal begins one event with correct rings

    @Test("V1 a flood reveal begins one event: origin, Chebyshev rings, maxRing, then expires")
    func v1FloodBeginsOneEvent() async throws {
        let gate = makeFeedbackGate()
        let viewModel = try FeedbackBoard.oneBigRegion.viewModel(gate: gate)
        #expect(viewModel.cellFeedback.isIdle)

        await viewModel.reveal(row: 0, col: 0)

        let events = viewModel.cellFeedback.activeEvents.map(\.event)
        try #require(events.count == 1, "expected exactly one event, got \(events.count)")
        let event = events[0]
        let columns = viewModel.columns
        let revealed = viewModel.cells.indices.filter { viewModel.cells[$0].state == .revealed }
        try #require(revealed.count > 1, "the tap should flood")

        #expect(event.originRow == 0 && event.originColumn == 0)
        #expect(event.ring(row: 0, col: 0) == 0)
        #expect(Set(event.rings.keys) == Set(revealed), "event cells differ from the newly revealed cells")
        for index in revealed {
            let expected = chebyshevRing(index: index, columns: columns, originRow: 0, originCol: 0)
            #expect(event.rings[index] == expected, "cell \(index): ring \(String(describing: event.rings[index])) != \(expected)")
        }
        let expectedMax = revealed.map { chebyshevRing(index: $0, columns: columns, originRow: 0, originCol: 0) }.max()
        #expect(event.maxRing == expectedMax, "maxRing \(event.maxRing) != \(String(describing: expectedMax)) over \(revealed.count) cells")
        #expect(!viewModel.cellFeedback.isIdle)

        await gate.release()
        await settle(viewModel)
        #expect(viewModel.cellFeedback.isIdle)
    }

    // MARK: V2 — no event

    @Test("V2 no event for a single-cell reveal")
    func v2SingleCellRevealBeginsNothing() async throws {
        let gate = makeFeedbackGate()
        let viewModel = try FeedbackBoard.oneBigRegion.viewModel(gate: gate)
        // (7,0) borders the mine at (8,0): a numbered cell, so exactly itself opens.
        await viewModel.reveal(row: 7, col: 0)
        #expect(viewModel.cells.filter { $0.state == .revealed }.count == 1)
        #expect(viewModel.cellFeedback.pendingExpiries.isEmpty)
        #expect(viewModel.cellFeedback.isIdle)
        await gate.release()
    }

    @Test("V2 no event for a mine detonation")
    func v2MineDetonationBeginsNothing() async throws {
        let gate = makeFeedbackGate()
        let viewModel = try FeedbackBoard.oneBigRegion.viewModel(gate: gate)
        await viewModel.reveal(row: 8, col: 0)
        #expect(viewModel.status == .lost)
        #expect(viewModel.cellFeedback.pendingExpiries.isEmpty)
        #expect(viewModel.cellFeedback.isIdle)
        await gate.release()
    }

    @Test("V2 no event for re-revealing an already revealed cell, and none for a flag toggle")
    func v2NoOpAndFlagBeginNothing() async throws {
        let gate = makeFeedbackGate()
        let viewModel = try FeedbackBoard.oneBigRegion.viewModel(gate: gate)
        await viewModel.reveal(row: 0, col: 0)
        #expect(viewModel.cellFeedback.pendingExpiries.count == 1)

        await viewModel.reveal(row: 0, col: 0)
        #expect(viewModel.cellFeedback.pendingExpiries.count == 1, "re-revealing a revealed cell began an event")

        await viewModel.toggleFlag(row: 8, col: 0)
        #expect(viewModel.cell(row: 8, col: 0).state == .flagged)
        #expect(viewModel.cellFeedback.pendingExpiries.count == 1, "a flag toggle began an event")
        await gate.release()
        await settle(viewModel)
    }

    // MARK: V3 — THE INPUT TEST

    @Test("V3 feedback never blocks or drops input: two regions and a flag land while both events are held")
    func v3InputNeverWaitsOnFeedback() async throws {
        let gate = makeFeedbackGate()
        let viewModel = try FeedbackBoard.twoRegions.viewModel(gate: gate)

        await viewModel.reveal(row: 0, col: 0)
        #expect(viewModel.cellFeedback.activeEvents.count == 1)
        #expect(await gate.isReleased == false)

        // Second, separate region while A's sleeper is still held. If `reveal`
        // awaited expiry it would only return after the 5 s watchdog, by which
        // time A would already have ended and the asserts below fail.
        await viewModel.reveal(row: 0, col: 15)
        #expect(await gate.isReleased == false, "the second reveal returned only after the watchdog released the sleeper")
        #expect(viewModel.cell(row: 0, col: 15).state == .revealed)
        #expect(viewModel.cell(row: 10, col: 2).state == .revealed, "region A cell missing")
        #expect(viewModel.cell(row: 10, col: 12).state == .revealed, "region B cell missing")
        let events = viewModel.cellFeedback.activeEvents.map(\.event)
        #expect(events.map(\.originColumn) == [0, 15], "both events should be active in begin order")

        // A flag toggle on a still-hidden cell during both animations also lands.
        #expect(viewModel.status == .playing)
        await viewModel.toggleFlag(row: 5, col: 3)
        #expect(await gate.isReleased == false)
        #expect(viewModel.cell(row: 5, col: 3).state == .flagged)
        #expect(viewModel.cellFeedback.activeEvents.count == 2)

        await gate.release()
        await settle(viewModel)
        #expect(viewModel.cellFeedback.isIdle)
        #expect(viewModel.cellFeedback.pendingExpiries.isEmpty, "pending expiries not empty after a full sequence")
    }

    // MARK: V4 — THE CAP TEST on a real Expert board

    @Test("V4 on a real 16x30 Expert flood every cell finishes within the 200 ms cap, delays strictly increasing")
    func v4CapOnExpertBoard() async throws {
        let gate = makeFeedbackGate()
        let viewModel = try FeedbackBoard.expertWide.viewModel(gate: gate)
        #expect(viewModel.rows == 16 && viewModel.columns == 30)

        await viewModel.reveal(row: 0, col: 0)

        let event = try #require(viewModel.cellFeedback.activeEvents.first?.event)
        let size = event.rings.count
        let description = "region size \(size), maxRing \(event.maxRing)"
        try #require(event.maxRing >= 16, "need a deep flood for the cap to matter: \(description)")

        let form = CellFeedbackMotionPlan.plan(reduceMotion: false).regionReveal
        guard case let .wave(stagger, cellDuration, cap) = form else {
            Issue.record("design plan is not a wave: \(form)")
            return
        }
        #expect(Double(event.maxRing) * stagger > cap - cellDuration, "the plain stagger would already fit, so the cap is not exercised: \(description)")

        var delayByRing: [Int: Double] = [:]
        for ring in Set(event.rings.values) {
            let delay = form.delay(ring: ring, maxRing: event.maxRing)
            delayByRing[ring] = delay
            #expect(delay + cellDuration <= cap + 1e-9, "ring \(ring): delay \(delay) + fade \(cellDuration) > cap \(cap); \(description)")
        }
        let rings = delayByRing.keys.sorted()
        for (previous, next) in zip(rings, rings.dropFirst()) {
            #expect(
                delayByRing[next, default: 0] > delayByRing[previous, default: 0],
                "delay not strictly increasing from ring \(previous) to \(next); \(description)"
            )
        }
        print("V4-MEASURE \(description); distinct rings \(rings.count); last delay \(delayByRing[event.maxRing] ?? -1)")

        await gate.release()
        await settle(viewModel)
    }
}
