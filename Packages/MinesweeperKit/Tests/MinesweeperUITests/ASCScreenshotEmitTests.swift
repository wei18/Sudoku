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
// (MinesweeperGameViewModel(seeded:), DailyHubViewModel.setStateForTesting).
// Light-mode (ASC v1 storyline).

#if canImport(AppKit)
import Foundation
import GameAppKit
import GameCenterClient
import GameCenterTesting
import GameShellUI
import GameTestSupportKit
import MinesweeperEngine
import MinesweeperGameState
import MonetizationCore
import MonetizationTesting
import MonetizationUI
import PersistenceTesting
import SwiftUI
import Testing
@testable import MinesweeperUI

// MS home mode config — byte-identical to Live.swift subtitles.
@MainActor
private let minesweeperAscHomeModes: [HomeMode: HomeModeContent<AppRoute>] = [
    .daily: HomeModeContent<AppRoute>(subtitleKey: "3 boards today", route: .daily),
    .practice: HomeModeContent<AppRoute>(subtitleKey: "All difficulties", route: .practice),
    .leaderboard: HomeModeContent<AppRoute>(subtitleKey: "Best times"),
    .settings: HomeModeContent<AppRoute>(subtitleKey: "Purchases / about", route: .settings)
]

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
            suppressTickerForSnapshot: true,
            tapModeDefaults: BoardTestDefaults.store
        )
    }

    private func homeView() -> some View {
        // #572: migrated from MinesweeperHomeView to shared GameHomeView.
        let rootVM = MinesweeperRootViewModel(
            gameCenter: FakeGameCenterClient(),
            persistence: FakePersistence()
        )
        let homeVM = GameHomeViewModel<AppRoute>(
            rootViewModel: rootVM,
            homeModes: minesweeperAscHomeModes
        )
        return NavigationStack {
            GameHomeView(
                viewModel: homeVM,
                rootViewModel: rootVM,
                title: "Minesweeper",
                adProvider: FakeAdProvider(),
                adGate: AdGate(store: FakeAdGateStateStore(
                    initial: AdGateState(
                        firstLaunchAt: Date(timeIntervalSince1970: 0),
                        hasPurchasedRemoveAds: true
                    )
                )),
                attPrimer: ATTPrimerCoordinator(
                    isNotDetermined: { false },
                    requestSystemPrompt: {}
                )
            )
        }
        .environment(\.theme, MinesweeperTheme())
    }

    private func dailyHubView() -> some View {
        let viewModel = MinesweeperDailyHubViewModel(path: .constant([]))
        viewModel.setStateForTesting(.loaded(Self.loadedTrio))
        // `setStateForTesting` bypasses `bootstrap()` and leaves
        // `isPhase2Pending` at its default `true`. Since #941 the pending flag
        // no longer dims cards, so this only pins the settled in-flight state
        // for determinism.
        viewModel.setPhase2PendingForTesting(false)
        return NavigationStack {
            MinesweeperDailyHubView(viewModel: viewModel)
        }
    }

    private func completionView() -> some View {
        // #698: leaderboard-state seeding removed — the popup has hardcoded
        // `state: .hidden` since v2.6, so the leaderboard slice never rendered.
        let viewModel = MinesweeperCompletionViewModel(
            didWin: true,
            elapsedSeconds: 65,
            leaderboardId: MinesweeperLeaderboardID.easyDaily
        )
        // The hero-reveal `.onAppear` never fires on this off-screen render
        // path — see `completionHeroSkipsReveal`'s doc comment. Without this,
        // the emitted ASC screenshot would ship with a blank hero card.
        return MinesweeperCompletionView(viewModel: viewModel, onClose: {})
            .environment(\.completionHeroSkipsReveal, true)
    }

    // MARK: - iPhone 6.9" (1290×2796) — Home / Daily / Board / Completion

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_iPhone_home() throws {
        try emitASCScreenshot(
            homeView(),
            profile: .iPhone69, app: Self.app, device: "iphone-6.9", locale: "en",
            slot: "01-home", background: Self.background,
            host: hostingView
        )
    }

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_iPhone_daily() throws {
        try emitASCScreenshot(
            dailyHubView(),
            profile: .iPhone69, app: Self.app, device: "iphone-6.9", locale: "en",
            slot: "02-daily", background: Self.background,
            host: hostingView
        )
    }

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_iPhone_board() throws {
        try emitASCScreenshot(
            boardView(),
            profile: .iPhone69, app: Self.app, device: "iphone-6.9", locale: "en",
            slot: "03-board", background: Self.background,
            host: hostingView
        )
    }

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_iPhone_completion() throws {
        try emitASCScreenshot(
            completionView(),
            profile: .iPhone69, app: Self.app, device: "iphone-6.9", locale: "en",
            slot: "04-completion", background: Self.background,
            host: hostingView
        )
    }

    // MARK: - iPad 13" (2064×2752) — Home + Board (fills the #311 iPad gap)

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_iPad_home() throws {
        try emitASCScreenshot(
            homeView(),
            profile: .iPad13, app: Self.app, device: "ipad-13", locale: "en",
            slot: "01-home", background: Self.background,
            host: hostingView
        )
    }

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_iPad_board() throws {
        try emitASCScreenshot(
            boardView(),
            profile: .iPad13, app: Self.app, device: "ipad-13", locale: "en",
            slot: "03-board", background: Self.background,
            host: hostingView
        )
    }

    // MARK: - Mac (2880×1800) — Home + Daily

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_mac_home() throws {
        try emitASCScreenshot(
            homeView(),
            profile: .mac, app: Self.app, device: "mac", locale: "en",
            slot: "01-home", background: Self.background,
            host: hostingView
        )
    }

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_mac_daily() throws {
        try emitASCScreenshot(
            dailyHubView(),
            profile: .mac, app: Self.app, device: "mac", locale: "en",
            slot: "02-daily", background: Self.background,
            host: hostingView
        )
    }
}
#endif
