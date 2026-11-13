// MinesweeperWaveRenderSupport (#1018) — harness for the rendered reveal-wave
// tests: one rendered frame sampled in points, the cell grid located from the
// all-hidden "before" frame, and the board rig.
//
// Sampling: one BACKGROUND spot per cell, near the bottom-trailing corner and
// inset from the cell's edges, away from the glyph, compared against the
// "before" render. A deliberate, small duplicate of SudokuKit's
// `BoardSweepRenderSupport.swift` (separate packages, no shared test-support
// target); the duplicated part is `SweepFrame`-equivalent frame sampling.

import Foundation
import GameShellUI
import MinesweeperEngine
import MonetizationUI
import SwiftUI
import Testing
@testable import MinesweeperUI

#if canImport(AppKit)
import AppKit

/// Lets the main run loop (and so the render server) advance in real time.
/// A synchronous function: `RunLoop.run(until:)` is unavailable directly in async code.
@MainActor
func spinRunLoop(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

/// One rendered frame of the host, sampled in points.
@MainActor
struct WaveFrame {
    let rep: NSBitmapImageRep
    let scale: Double

    init(_ host: NSView) throws {
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        self.rep = rep
        self.scale = Double(rep.pixelsWide) / Double(host.bounds.width)
    }

    /// Mean RGB (0...255) over a 3x3 pixel patch around the point.
    func rgb(_ point: CGPoint) -> [Double] {
        let centerX = Int((Double(point.x) * scale).rounded())
        let centerY = Int((Double(point.y) * scale).rounded())
        var sum = [0.0, 0.0, 0.0]
        var count = 0.0
        for offsetY in -1...1 {
            for offsetX in -1...1 {
                let pixel = rep.colorAt(x: centerX + offsetX, y: centerY + offsetY)
                guard let color = pixel?.usingColorSpace(.deviceRGB) else { continue }
                sum[0] += Double(color.redComponent) * 255
                sum[1] += Double(color.greenComponent) * 255
                sum[2] += Double(color.blueComponent) * 255
                count += 1
            }
        }
        return count == 0 ? [0, 0, 0] : sum.map { $0 / count }
    }

    func png() -> Data? { rep.representation(using: .png, properties: [:]) }
}

/// Where each cell sits in the compact iPhone render, found from the all-hidden frame.
struct WaveGrid {
    let columnRanges: [ClosedRange<Double>]
    let rowRanges: [ClosedRange<Double>]

    /// Where in a tile to sample.
    enum Spot {
        /// Bottom-trailing corner, clear of the glyph: reads the BACKGROUND.
        case corner
        /// The centre, where a number is drawn: reads the GLYPH (and the background).
        case center
    }

    func sample(row: Int, col: Int, at spot: Spot = .corner) -> CGPoint {
        let xRange = columnRanges[col]
        let yRange = rowRanges[row]
        let fraction = spot == .corner ? 0.82 : 0.5
        return CGPoint(
            x: xRange.lowerBound + fraction * (xRange.upperBound - xRange.lowerBound),
            y: yRange.lowerBound + fraction * (yRange.upperBound - yRange.lowerBound)
        )
    }
}

/// The real `MinesweeperBoardView` over a live view model, plus the pixel readings the tests compare.
@MainActor
enum WaveRig {
    static let size = SnapshotLayouts.iPhone

    /// A render with a design-ish stagger but slow enough to see: for pictures.
    static let pictureTiming = CellFeedbackMotionPlan.Timing(unitSweep: 3, waveStagger: 0.35, cellFade: 0.3, waveCap: 1_000)
    /// A stagger of tens of seconds per ring, a tiny fade, a cap far too large to compress it.
    static let slowTiming = CellFeedbackMotionPlan.Timing(unitSweep: 3, waveStagger: 20, cellFade: 0.05, waveCap: 100_000)

    static func makeHost(
        _ viewModel: MinesweeperGameViewModel,
        reduceMotion: Bool?,
        timing: CellFeedbackMotionPlan.Timing = .design,
        scheme: ColorScheme = .light
    ) -> NSView {
        hostingView(
            MinesweeperBoardView(
                viewModel: viewModel,
                suppressTickerForSnapshot: true,
                tapModeDefaults: BoardTestDefaults.store
            )
            .environment(\.bannerSession, .disabled)
            .environment(\.cellFeedbackReduceMotionOverride, reduceMotion)
            .environment(\.cellFeedbackTiming, timing),
            size: size,
            colorScheme: scheme,
            sizeClass: .compact
        )
    }

    /// A borderless window that is never ordered front or made key; the caller
    /// closes it (`defer`) even on failure.
    static func makeWindow(containing host: NSView, scheme: ColorScheme = .light) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        return window
    }

    /// Runs of pixels along a line that leave the page background, as ranges of the varying coordinate.
    private static func runs(
        _ frame: WaveFrame,
        background: [Double],
        range: ClosedRange<Double>,
        point: (Double) -> CGPoint
    ) -> [ClosedRange<Double>] {
        var result: [ClosedRange<Double>] = []
        var start: Double?
        var position = range.lowerBound
        while position <= range.upperBound {
            let color = frame.rgb(point(position))
            let away = zip(color, background).map { abs($0 - $1) }.reduce(0, +) > 12
            if away, start == nil { start = position }
            if !away, let began = start {
                result.append(began...(position - 0.5))
                start = nil
            }
            position += 0.5
        }
        if let began = start { result.append(began...range.upperBound) }
        return result
    }

    /// Finds every cell tile in the all-hidden frame: a horizontal scan that
    /// yields `cols` equal runs, then a vertical scan through the first column
    /// that yields `rows` square-ish runs.
    static func findGrid(_ frame: WaveFrame, rows: Int, cols: Int) throws -> WaveGrid {
        let background = frame.rgb(CGPoint(x: 1, y: 1))
        let width = Double(size.width)
        let height = Double(size.height)
        var columnRanges: [ClosedRange<Double>] = []
        var scanY = 80.0
        while scanY < height - 80 {
            let found = runs(frame, background: background, range: 0...(width - 1)) { CGPoint(x: $0, y: scanY) }
                .filter { $0.upperBound - $0.lowerBound > 15 }
            if found.count == cols {
                let widths = found.map { $0.upperBound - $0.lowerBound }
                if (widths.max() ?? 0) - (widths.min() ?? 0) < 3 { columnRanges = found; break }
            }
            scanY += 4
        }
        try #require(columnRanges.count == cols, "could not find \(cols) cell tiles along any horizontal scan line")
        let tile = columnRanges[0].upperBound - columnRanges[0].lowerBound
        let centerX = (columnRanges[0].lowerBound + columnRanges[0].upperBound) / 2
        let rowRanges = runs(frame, background: background, range: 0...(height - 1)) { CGPoint(x: centerX, y: $0) }
            .filter { abs(($0.upperBound - $0.lowerBound) - tile) < 3 }
        try #require(rowRanges.count == rows, "found \(rowRanges.count) tile rows, expected \(rows)")
        return WaveGrid(columnRanges: columnRanges, rowRanges: rowRanges)
    }

    /// Summed absolute RGB difference between two frames at a cell.
    static func delta(
        _ before: WaveFrame,
        _ after: WaveFrame,
        _ grid: WaveGrid,
        row: Int,
        col: Int,
        at spot: WaveGrid.Spot = .corner
    ) -> Double {
        let point = grid.sample(row: row, col: col, at: spot)
        return zip(before.rgb(point), after.rgb(point)).map { abs($0 - $1) }.reduce(0, +)
    }

    /// Print the measured numbers (the task report quotes them).
    static func report(_ label: String, _ values: [Double]) {
        print("WAVE-MEASURE \(label): " + values.map { String(format: "%.1f", $0) }.joined(separator: " "))
    }

    // MARK: Thresholds (summed |ΔRGB| over 0...765) — set from the measured values in the task report.

    static let litThreshold = 30.0
    static let unlitThreshold = 2.0
}
#endif
