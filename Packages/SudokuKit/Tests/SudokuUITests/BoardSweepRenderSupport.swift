// BoardSweepRenderSupport (#1018) — shared harness for the rendered unit-sweep
// tests: a hand-released sleeper gate, one rendered frame sampled in points,
// the grid geometry of the compact iPhone render, and the board rig.
//
// Sampling: one spot per cell, near the bottom-trailing corner and inset from
// the grid lines, where digit ink never reaches, so a newly placed digit does
// not pollute the reading.

import Foundation
import GameShellUI
import SudokuEngine
import SudokuGameState
import SudokuPersistence
import SwiftUI
import Testing
@testable import SudokuUI

#if canImport(AppKit)
import AppKit

/// Releases held sleepers by hand; a watchdog frees it after 20 s so a
/// regression fails an assertion instead of hanging the run.
actor SweepGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false

    func wait() async {
        if isReleased { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        isReleased = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

func makeSweepGate() -> SweepGate {
    let gate = SweepGate()
    Task {
        try? await Task.sleep(for: .seconds(20))
        await gate.release()
    }
    return gate
}

/// Lets the main run loop (and so the render server) advance in real time.
/// A synchronous function: `RunLoop.run(until:)` is unavailable directly in async code.
@MainActor
func spinRunLoop(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

/// One rendered frame of the host, sampled in points.
@MainActor
struct SweepFrame {
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

/// Where the 9x9 grid sits in the compact iPhone render (full-bleed: the cell
/// side is the offered width / 9; only the vertical origin is found).
struct SweepGrid {
    let originY: Double
    let cell: Double
    /// True under a right-to-left layout: the grid mirrors, so board column `c`
    /// sits at physical column `8 - c`.
    var mirrored = false

    /// Sample spot for a board index: the lower, inset corner of its cell,
    /// where digit ink never reaches (physical x measured from the left edge).
    func sample(_ index: Int) -> CGPoint {
        let row = Double(index / 9)
        let column = Double(index % 9)
        // Mirrored: the same spot of the mirrored cell (the leading edge is on the right).
        let physicalColumn = mirrored ? 8 - column : column
        let fraction = mirrored ? 0.18 : 0.82
        return CGPoint(x: (physicalColumn + fraction) * cell, y: originY + (row + 0.82) * cell)
    }
}

/// The real `BoardView` over a preview-path `GameViewModel`, plus the pixel
/// readings the rendered tests compare.
@MainActor
enum SweepRig {
    static let size = SnapshotLayouts.iPhone
    private static let identity = PuzzleIdentity.practice(salt: 7, difficulty: .easy)
    private static let solved = Array(
        "534678912672195348198342567859761423426853791713924856961537284287419635345286179"
    ).map { Int(String($0)) ?? 0 }

    static func coord(_ row: Int, _ column: Int) -> GridCoordinate {
        GridCoordinate(row: row, column: column)
    }

    static func solution(_ row: Int, _ column: Int) -> Int {
        solved[Board.index(row: row, column: column)]
    }

    /// Row 0 one digit short (and (1,0) blank, so column 0 / box 0 stay open).
    static var rowBlanks: Set<GridCoordinate> { [coord(0, 0), coord(1, 0)] }

    static func makeViewModel(blanks: Set<GridCoordinate>, gate: SweepGate) throws -> GameViewModel {
        var clues = ""
        for index in 0..<Board.cellCount {
            clues.append(blanks.contains(coord(index / 9, index % 9)) ? "." : String(solved[index]))
        }
        return GameViewModel(
            identity: identity,
            board: try Board(clues: clues),
            cellFeedbackSleeper: { _ in await gate.wait() }
        )
    }

    static func makeHost(
        _ viewModel: GameViewModel,
        reduceMotion: Bool?,
        timing: CellFeedbackMotionPlan.Timing = .design,
        scheme: ColorScheme = .light,
        layoutDirection: LayoutDirection = .leftToRight
    ) -> NSView {
        hostingView(
            adFreeBoard(viewModel)
                .environment(\.layoutDirection, layoutDirection)
                .environment(\.cellFeedbackReduceMotionOverride, reduceMotion)
                .environment(\.cellFeedbackTiming, timing),
            size: size,
            colorScheme: scheme,
            sizeClass: .compact
        )
    }

    /// A borderless window that is never ordered front or made key; the caller
    /// closes it (`defer`) even on failure.
    static func makeWindow(containing host: NSView) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        return window
    }

    /// Finds the grid's top edge by scanning the leftmost strip (clear of the
    /// header's horizontal padding) for the first row that leaves the page
    /// background, and checks the grid's bottom lands one board-width lower.
    static func findGrid(_ frame: SweepFrame, rightToLeft: Bool = false) throws -> SweepGrid {
        let cell = Double(size.width) / 9
        let background = frame.rgb(CGPoint(x: 3, y: 2))
        func leavesBackground(_ scanY: Double) -> Bool {
            let color = frame.rgb(CGPoint(x: 3, y: scanY))
            return zip(color, background).map { abs($0 - $1) }.reduce(0, +) > 6
        }
        var top: Double?
        var scanY = 2.0
        while scanY < Double(size.height) / 2 {
            if leavesBackground(scanY) { top = scanY; break }
            scanY += 0.5
        }
        let originY = try #require(top, "grid top edge not found in the leftmost strip")
        #expect(leavesBackground(originY + cell * 9 - 3), "grid bottom is not one board-width below its top")
        #expect(!leavesBackground(originY + cell * 9 + 4), "something sits right below the grid's bottom edge")
        return SweepGrid(originY: originY, cell: cell, mirrored: rightToLeft)
    }

    /// Summed absolute RGB difference between two frames at a board index.
    static func delta(_ before: SweepFrame, _ after: SweepFrame, _ grid: SweepGrid, _ index: Int) -> Double {
        zip(before.rgb(grid.sample(index)), after.rgb(grid.sample(index))).map { abs($0 - $1) }.reduce(0, +)
    }

    /// Print the measured numbers (visible in the test output).
    static func report(_ label: String, _ values: [Double]) {
        print("SWEEP-MEASURE \(label): " + values.map { String(format: "%.1f", $0) }.joined(separator: " "))
    }

    // MARK: Thresholds (summed |ΔRGB| over 0...765)
    //
    // Measured on this machine (light theme, iPhone frame): a cell under the
    // full light reads 82...108; a cell with no light reads exactly 0.0; a cell
    // at the soft edge of the band reads ~19...22. `litThreshold` sits at under
    // half the weakest fully-lit reading, `unlitThreshold` far above the 0.0
    // noise floor and far below any lit one, `touchedThreshold` marks "the
    // band's soft edge has reached this cell".

    static let litThreshold = 40.0
    static let touchedThreshold = 8.0
    static let unlitThreshold = 2.0
    static let evennessRatio = 1.5
}
#endif
