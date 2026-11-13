// MinesweeperRevealWavePictureTests (#1018) — writes pictures of the real board
// for a design look. NOT committed output and not an assertion: it only runs
// when MINESWEEPER_WAVE_PNG_DIR names a directory, so a normal `swift test`
// never touches the disk outside the build.

import Foundation
import GameShellUI
import SwiftUI
import Testing
@testable import MinesweeperUI

#if canImport(AppKit)
import AppKit

@MainActor
@Suite("MinesweeperBoardView — #1018 reveal wave pictures (gated on MINESWEEPER_WAVE_PNG_DIR)", .serialized)
struct MinesweeperRevealWavePictureTests {

    private typealias Rig = WaveRig

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MINESWEEPER_WAVE_PNG_DIR"] != nil))
    func writePictures() async throws {
        let directory = try #require(ProcessInfo.processInfo.environment["MINESWEEPER_WAVE_PNG_DIR"])
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        func save(_ frame: WaveFrame, _ name: String) throws {
            try #require(frame.png()).write(to: URL(fileURLWithPath: directory + "/" + name + ".png"))
        }

        // Reduce Motion first frame (everything appears at once) and the default-motion first frame
        // (still the hidden board), bare host, light.
        for (reduce, name) in [(true, "01-reduce-motion-first-frame-light"), (false, "02-default-motion-first-frame-light")] {
            let gate = makeFeedbackGate()
            let viewModel = try FeedbackBoard.oneBigRegion.viewModel(gate: gate)
            let host = Rig.makeHost(viewModel, reduceMotion: reduce)
            await viewModel.reveal(row: 0, col: 0)
            try save(WaveFrame(host), name)
            await gate.release()
            await viewModel.cellFeedback.waitForPendingExpiries()
        }

        // The wave mid-expansion, picture timing (0.35 s per ring, 0.3 s fade) in an offscreen
        // window: frames a fixed interval after the tapped cell first reads revealed.
        for scheme in [ColorScheme.light, .dark] {
            let tag = scheme == .light ? "light" : "dark"
            let gate = makeFeedbackGate(watchdog: .seconds(60))
            let viewModel = try FeedbackBoard.oneBigRegion.viewModel(gate: gate)
            let host = Rig.makeHost(viewModel, reduceMotion: false, timing: Rig.pictureTiming, scheme: scheme)
            let window = Rig.makeWindow(containing: host, scheme: scheme)
            defer {
                window.contentView = nil
                window.close()
            }
            let before = try WaveFrame(host)
            let grid = try Rig.findGrid(before, rows: 9, cols: 9)
            await viewModel.reveal(row: 0, col: 0)

            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline {
                let frame = try WaveFrame(host)
                if Rig.delta(before, frame, grid, row: 0, col: 0) > 5 { break }
                spinRunLoop(0.02)
            }
            let anchor = Date()
            let schedule: [Double] = scheme == .light ? [0.0, 0.7, 1.4, 2.1, 3.2] : [0.7, 2.1]
            for (step, target) in schedule.enumerated() {
                let remaining = target - Date().timeIntervalSince(anchor)
                if remaining > 0 { spinRunLoop(remaining) }
                let millis = Int(Date().timeIntervalSince(anchor) * 1000)
                try save(WaveFrame(host), "03-wave-\(tag)-frame\(step + 1)-plus\(millis)ms")
            }
            await gate.release()
            await viewModel.cellFeedback.waitForPendingExpiries()
        }
    }
}
#endif
