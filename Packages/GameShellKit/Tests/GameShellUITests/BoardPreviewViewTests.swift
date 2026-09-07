// BoardPreviewViewTests — #1021 Phase A.
//
// No visual snapshot coverage here: `GameShellKit`'s Package.swift carries no
// `SnapshotTesting` dependency (unlike `SudokuKit`/`MinesweeperKit`), and
// `CompletionScreenTests.swift`'s header comment documents that visual
// snapshot suites for shared shell views live per-app instead. Pinning
// `isAccessibilityHidden` as a plain constant (rather than rendering the view
// and inspecting it) follows the same "no rendering needed" shape as
// `DailyPuzzleCardAccessibilityTests` in SudokuUITests.

import Testing
@testable import GameShellUI

@Suite("GameShellUI — BoardPreviewView")
struct BoardPreviewViewTests {

    @Test("the thumbnail is always accessibility-hidden")
    func alwaysAccessibilityHidden() {
        #expect(BoardPreviewView.isAccessibilityHidden)
    }

    // MARK: - densitySample determinism

    @Test("same seed produces identical cells")
    func sameSeedIsDeterministic() throws {
        let first = try #require(
            BoardPreview.densitySample(columns: 9, rows: 9, fillRatio: 0.4, mark: .given, seed: 42)
        )
        let second = try #require(
            BoardPreview.densitySample(columns: 9, rows: 9, fillRatio: 0.4, mark: .given, seed: 42)
        )
        #expect(first == second)
    }

    @Test("different seeds usually produce different cells")
    func differentSeedsDiffer() throws {
        let first = try #require(
            BoardPreview.densitySample(columns: 9, rows: 9, fillRatio: 0.4, mark: .given, seed: 1)
        )
        let second = try #require(
            BoardPreview.densitySample(columns: 9, rows: 9, fillRatio: 0.4, mark: .given, seed: 2)
        )
        #expect(first != second)
    }

    @Test("fill count matches ratio × cell count within ±1")
    func fillCountMatchesRatio() throws {
        let columns = 16
        let rows = 30
        let ratio = 0.35
        let preview = try #require(
            BoardPreview.densitySample(columns: columns, rows: rows, fillRatio: ratio, mark: .marked, seed: 7)
        )
        let expected = Double(columns * rows) * ratio
        let actualCount = preview.cells.filter { $0 == .marked }.count
        #expect(abs(Double(actualCount) - expected) <= 1)
    }

    @Test("densitySample fails for non-positive dimensions")
    func densitySampleFailsForNonPositiveDimensions() {
        #expect(BoardPreview.densitySample(columns: 0, rows: 9, fillRatio: 0.5, mark: .given, seed: 1) == nil)
        #expect(BoardPreview.densitySample(columns: 9, rows: 0, fillRatio: 0.5, mark: .given, seed: 1) == nil)
    }

    @Test("densitySample every non-fill cell is empty")
    func densitySampleFillsOnlyRequestedMark() throws {
        let preview = try #require(
            BoardPreview.densitySample(columns: 4, rows: 4, fillRatio: 0.5, mark: .filled, seed: 3)
        )
        for cell in preview.cells {
            #expect(cell == .empty || cell == .filled)
        }
    }
}
