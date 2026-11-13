// BoardUnitSweepPictureTests (#1018) — writes pictures of the real board for a
// design look. NOT committed output and not an assertion: it only runs when
// SUDOKU_SWEEP_PNG_DIR names a directory, so a normal `swift test` never
// touches the disk outside the build.

import Foundation
import GameShellUI
import SudokuGameState
import SwiftUI
import Testing
@testable import SudokuUI

#if canImport(AppKit)
import AppKit

@MainActor
@Suite("BoardView — #1018 unit sweep pictures (gated on SUDOKU_SWEEP_PNG_DIR)", .serialized)
struct BoardUnitSweepPictureTests {

    private typealias Rig = SweepRig

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SUDOKU_SWEEP_PNG_DIR"] != nil))
    func writePictures() async throws {
        let directory = try #require(ProcessInfo.processInfo.environment["SUDOKU_SWEEP_PNG_DIR"])
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        func save(_ frame: SweepFrame, _ name: String) throws {
            try #require(frame.png()).write(to: URL(fileURLWithPath: directory + "/" + name + ".png"))
        }

        // First frames on a bare hosting view: Reduce Motion flash, default sweep; light and dark.
        for scheme in [ColorScheme.light, .dark] {
            let tag = scheme == .light ? "light" : "dark"
            for (reduce, label) in [(true, "01-reduce-motion-flash-first-frame"), (false, "02-default-sweep-first-frame")] {
                let gate = makeSweepGate()
                let viewModel = try Rig.makeViewModel(blanks: Rig.rowBlanks, gate: gate)
                let host = Rig.makeHost(viewModel, reduceMotion: reduce, scheme: scheme)
                await viewModel.placeDigit(Rig.solution(0, 0), at: Rig.coord(0, 0))
                try save(SweepFrame(host), "\(label)-\(tag)")
                await gate.release()
                await viewModel.cellFeedback.waitForPendingExpiries()
            }
        }

        // Slow timing in an offscreen window: frames mid-travel for a row, a column and a box.
        let slow = CellFeedbackMotionPlan.Timing(unitSweep: 3, waveStagger: 0.5, cellFade: 1, waveCap: 9)
        let cases: [(String, Set<GridCoordinate>)] = [
            ("03-slow-row", Rig.rowBlanks),
            ("04-slow-column", [Rig.coord(0, 0), Rig.coord(0, 1)]),
            ("05-slow-box", [Rig.coord(0, 0), Rig.coord(0, 3), Rig.coord(4, 0)]),
        ]
        for (name, blanks) in cases {
            let gate = makeSweepGate()
            let viewModel = try Rig.makeViewModel(blanks: blanks, gate: gate)
            let host = Rig.makeHost(viewModel, reduceMotion: false, timing: slow)
            let window = Rig.makeWindow(containing: host)
            defer {
                window.contentView = nil
                window.close()
            }
            await viewModel.placeDigit(Rig.solution(0, 0), at: Rig.coord(0, 0))
            let started = Date()
            for (step, wait) in [0.0, 0.9, 1.0].enumerated() {
                spinRunLoop(wait)
                let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                try save(SweepFrame(host), "\(name)-frame\(step + 1)-\(elapsed)ms")
            }
            await gate.release()
            await viewModel.cellFeedback.waitForPendingExpiries()
        }
    }
}
#endif
