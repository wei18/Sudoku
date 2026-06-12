// ASCScreenshotEmitTests — emit submission-spec App Store screenshots for
// Minesweeper by rendering the REAL screens at EXACT ASC pixel dimensions,
// opaque (no alpha). MS mirror of SudokuKit's emitter. See ASCScreenshotRender.swift.
//
// Gated behind `ASC_EMIT_SCREENSHOTS=1`. To regenerate:
//
//   ASC_EMIT_SCREENSHOTS=1 swift test \
//     --package-path Packages/MinesweeperKit \
//     --filter ASCScreenshotEmitTests
//
// Determinism mirrors the MS snapshot suites: seeded VMs
// (MinesweeperGameViewModel(seeded:), DailyHubViewModel.setStateForTesting,
// CompletionViewModel.setStateForTesting). Light-mode (ASC v1 storyline).

#if canImport(AppKit)
import Foundation
import SwiftUI
import Testing
@testable import MinesweeperUI

import GameCenterClient
import GameCenterTesting
import MinesweeperEngine
import MinesweeperGameState

@MainActor
@Suite("ASC screenshots — Minesweeper (emit; gated on ASC_EMIT_SCREENSHOTS)")
struct ASCScreenshotEmitTests {

    private static let app = "minesweeper"
    private static var background: Color { MinesweeperTheme().surface.background.resolved }

    private static let cols = Difficulty.beginner.columns
    private static let rows = Difficulty.beginner.rows

    // MARK: - Deterministic fixtures (reused from the MS snapshot suites)

    private static let loadedTrio: [MinesweeperDailyCard] = [
        MinesweeperDailyCard(
            entry: MinesweeperDailyEntry(puzzleId: "fixture-beginner", difficulty: .beginner, seed: 1),
            isCompleted: false
        ),
        MinesweeperDailyCard(
            entry: MinesweeperDailyEntry(puzzleId: "fixture-intermediate", difficulty: .intermediate, seed: 2),
            isCompleted: true
        ),
        MinesweeperDailyCard(
            entry: MinesweeperDailyEntry(puzzleId: "fixture-expert", difficulty: .expert, seed: 3),
            isCompleted: false
        ),
    ]

    private static let completionSlice = LeaderboardSlice(
        leaderboardId: MinesweeperLeaderboardID.easyDaily,
        scope: .globalAllTime,
        entries: [
            LeaderboardEntry(rank: 1, player: PlayerSummary(teamPlayerId: "P1", displayName: "alice"), score: 41),
            LeaderboardEntry(rank: 2, player: PlayerSummary(teamPlayerId: "P2", displayName: "bob"), score: 55),
            LeaderboardEntry(rank: 3, player: PlayerSummary(teamPlayerId: "P3", displayName: "carol"), score: 73),
        ],
        totalPlayerCount: 900,
        fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    private func index(row: Int, col: Int) -> Int { row * Self.cols + col }

    /// A mid-game beginner board surfacing the full 1…8 neighbor palette — the
    /// most marketing-legible board state (numbers + a calm opened region).
    private func midRevealCells() -> [Cell] {
        var cells = Array(repeating: Cell(state: .hidden), count: Self.rows * Self.cols)
        for count in 1...8 {
            cells[index(row: 0, col: count - 1)] = Cell(neighborMineCount: count, state: .revealed)
        }
        for col in 0..<6 {
            cells[index(row: 1, col: col)] = Cell(neighborMineCount: 0, state: .revealed)
        }
        cells[index(row: 2, col: 0)] = Cell(neighborMineCount: 3, state: .revealed)
        cells[index(row: 2, col: 1)] = Cell(neighborMineCount: 1, state: .revealed)
        cells[index(row: 2, col: 2)] = Cell(neighborMineCount: 2, state: .revealed)
        return cells
    }

    private func boardView() -> MinesweeperBoardView {
        let snapshot = MinesweeperSessionSnapshot(
            difficulty: .beginner,
            cells: midRevealCells(),
            status: .playing,
            elapsedSeconds: 42,
            mineCount: Difficulty.beginner.mineCount,
            flagCount: 0
        )
        return MinesweeperBoardView(
            viewModel: MinesweeperGameViewModel(seeded: snapshot),
            suppressTickerForSnapshot: true
        )
    }

    private func homeView() -> some View {
        NavigationStack {
            MinesweeperHomeView(viewModel: MinesweeperHomeViewModel())
        }
    }

    private func dailyHubView() -> some View {
        let viewModel = MinesweeperDailyHubViewModel(path: .constant([]))
        viewModel.setStateForTesting(.loaded(Self.loadedTrio))
        return NavigationStack {
            MinesweeperDailyHubView(viewModel: viewModel)
        }
    }

    private func completionView() -> some View {
        let viewModel = MinesweeperCompletionViewModel(
            didWin: true,
            elapsedSeconds: 65,
            leaderboardId: MinesweeperLeaderboardID.easyDaily,
            gameCenter: FakeGameCenterClient()
        )
        viewModel.setStateForTesting(.loaded(Self.completionSlice))
        return MinesweeperCompletionView(viewModel: viewModel, onClose: {})
    }

    // MARK: - iPhone 6.9" (1290×2796) — Home / Daily / Board / Completion

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_iPhone_home() throws {
        try emitASCScreenshot(
            homeView(),
            profile: .iPhone69, app: Self.app, device: "iphone-6.9", locale: "en",
            slot: "01-home", background: Self.background
        )
    }

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_iPhone_daily() throws {
        try emitASCScreenshot(
            dailyHubView(),
            profile: .iPhone69, app: Self.app, device: "iphone-6.9", locale: "en",
            slot: "02-daily", background: Self.background
        )
    }

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_iPhone_board() throws {
        try emitASCScreenshot(
            boardView(),
            profile: .iPhone69, app: Self.app, device: "iphone-6.9", locale: "en",
            slot: "03-board", background: Self.background
        )
    }

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_iPhone_completion() throws {
        try emitASCScreenshot(
            completionView(),
            profile: .iPhone69, app: Self.app, device: "iphone-6.9", locale: "en",
            slot: "04-completion", background: Self.background
        )
    }

    // MARK: - iPad 13" (2064×2752) — Home + Board (fills the #311 iPad gap)

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_iPad_home() throws {
        try emitASCScreenshot(
            homeView(),
            profile: .iPad13, app: Self.app, device: "ipad-13", locale: "en",
            slot: "01-home", background: Self.background
        )
    }

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_iPad_board() throws {
        try emitASCScreenshot(
            boardView(),
            profile: .iPad13, app: Self.app, device: "ipad-13", locale: "en",
            slot: "03-board", background: Self.background
        )
    }

    // MARK: - Mac (2880×1800) — Home + Daily

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_mac_home() throws {
        try emitASCScreenshot(
            homeView(),
            profile: .mac, app: Self.app, device: "mac", locale: "en",
            slot: "01-home", background: Self.background
        )
    }

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_mac_daily() throws {
        try emitASCScreenshot(
            dailyHubView(),
            profile: .mac, app: Self.app, device: "mac", locale: "en",
            slot: "02-daily", background: Self.background
        )
    }
}
#endif
