// ASCScreenshotEmitTests — emit submission-spec App Store screenshots for Sudoku
// by rendering the REAL screens through the snapshot harness at EXACT ASC pixel
// dimensions, opaque (no alpha). See ASCScreenshotRender.swift for the render
// path; this file wires the deterministic screen fixtures + ASC slot mapping.
//
// These tests WRITE real PNG files under docs/app-store/screenshots/sudoku/…,
// so they are gated behind `ASC_EMIT_SCREENSHOTS=1`
// (`.enabled(if: ASCScreenshotEmit.isEnabled)`). A normal `swift test` skips
// them and never rewrites the committed assets. To regenerate:
//
//   ASC_EMIT_SCREENSHOTS=1 swift test \
//     --package-path Packages/SudokuKit \
//     --filter ASCScreenshotEmitTests
//
// Determinism mirrors the existing snapshot suites: no Date.now / RNG; the same
// seeded view models (BoardViewTests clue strings, DailyHubViewModel fixed-date
// trio). All renders are light-mode (the ASC v1 storyline is light-mode per
// screenshot-strategy.md).

#if canImport(AppKit)
import Foundation
import SwiftUI
import Testing
@testable import SudokuUI

import GameAppKit
import GameCenterClient
import GameCenterTesting
import GameShellUI
import SudokuGameState
import MonetizationCore
import MonetizationTesting
import MonetizationUI
import Persistence
import SudokuPersistence
import SudokuEngine
import SudokuKitTesting

@MainActor
@Suite("ASC screenshots — Sudoku (emit; gated on ASC_EMIT_SCREENSHOTS)")
struct ASCScreenshotEmitTests {

    private static let app = "sudoku"
    private static var background: Color { DefaultTheme().surface.background.resolved }

    // MARK: - Deterministic fixtures (reused from the snapshot suites)

    private static let inProgressClues =
        "53..7...." + "6..195..." + ".98....6." +
        "8...6...3" + "4..8.3..1" + "7...2...6" +
        ".6....28." + "...419..5" + "....8..79"

    private static let identityEasy = PuzzleIdentity(
        puzzleId: "test-easy", kind: .practice, difficulty: .easy
    )

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    private func boardView() throws -> BoardView {
        var board = try Board(clues: Self.inProgressClues)
        try board.setDigit(4, atRow: 0, column: 2)
        try board.setDigit(6, atRow: 0, column: 3)
        try board.setDigit(5, atRow: 4, column: 4)
        let viewModel = GameViewModel(
            identity: Self.identityEasy,
            board: board,
            status: .playing,
            elapsedSeconds: 201,
            errorIndices: [Board.index(row: 0, column: 2)],
            selection: GridCoordinate(row: 4, column: 4)
        )
        return BoardView(viewModel: viewModel)
    }

    private func dailyHubView() async -> some View {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        let viewModel = DailyHubViewModel(
            provider: provider,
            persistence: FakePersistence(completedDailyIds: []),
            dateProvider: { Self.fixedDate }
        )
        await viewModel.bootstrap()
        return DailyHubView(viewModel: viewModel)
    }

    private func completionView() -> some View {
        // #698: leaderboard-state seeding removed — the popup has hardcoded
        // `state: .hidden` since v2.6, so the leaderboard slice never rendered.
        let viewModel = CompletionViewModel(
            puzzleId: "2026-05-19-easy",
            elapsedSeconds: 251,
            mistakeCount: 2,
            leaderboardId: "com.wei18.sudoku.leaderboard.easy.daily.v1"
        )
        // The hero-reveal `.onAppear` never fires on this off-screen render
        // path — see `completionHeroSkipsReveal`'s doc comment. Without this,
        // the emitted ASC screenshot would ship with a blank hero card.
        return CompletionView(viewModel: viewModel)
            .environment(\.completionHeroSkipsReveal, true)
    }

    /// Settings wrapped in the production navigation + grouped-Form chrome
    /// (mirrors SettingsViewTests.makeSettingsHost). Built `purchased: true` so
    /// the marketing frame shows the unlocked Purchases section, not the CTA.
    private func settingsView() async -> some View {
        let store = FakeAdGateStateStore(
            initial: AdGateState(
                firstLaunchAt: Date(timeIntervalSince1970: 0),
                hasPurchasedRemoveAds: true
            )
        )
        let iap = FakeIAPClient()
        await iap.setProducts([
            IAPProduct(
                id: removeAdsProductId,
                displayName: "Remove Ads",
                displayPrice: "$2.99",
                isPurchased: true
            )
        ])
        let controller = MonetizationStateController(
            iapClient: iap,
            stateStore: store,
            adGate: AdGate(store: store)
        )
        await controller.bootstrap()
        return NavigationStack {
            SettingsView(viewModel: SettingsViewModel(persistence: FakePersistence()), monetizationController: controller)
        }
        .formStyle(.grouped)
    }

    // MARK: - Fixtures

    // #557: HomeView/HomeViewModel retired; home screenshot now uses GameHomeView
    // constructed from the same Sudoku mode content as Live.swift.
    private static let sudokuHomeModes: [HomeMode: HomeModeContent<AppRoute>] = [
        .daily: HomeModeContent<AppRoute>(subtitleKey: "3 puzzles today", route: .daily),
        .practice: HomeModeContent<AppRoute>(subtitleKey: "Mixed difficulty pool", route: .practice),
        .leaderboard: HomeModeContent<AppRoute>(subtitleKey: "Global / friends"),
        .settings: HomeModeContent<AppRoute>(subtitleKey: "Account / language", route: .settings)
    ]

    private func homeView() -> some View {
        let rootVM = RootViewModel(
            gameCenter: FakeGameCenterClient(),
            persistence: FakePersistence()
        )
        let homeVM = GameHomeViewModel(
            rootViewModel: rootVM,
            homeModes: Self.sudokuHomeModes
        )
        return GameHomeView(
            viewModel: homeVM,
            rootViewModel: rootVM,
            title: "Sudoku",
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

    // MARK: - iPhone 6.9" (1290×2796) — Home / Daily / Board / Completion / Settings

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_iPhone_home() throws {
        try emitASCScreenshot(
            homeView(),
            profile: .iPhone69, app: Self.app, device: "iphone-6.9", locale: "en",
            slot: "01-home", background: Self.background
        )
    }

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_iPhone_daily() async throws {
        try emitASCScreenshot(
            await dailyHubView(),
            profile: .iPhone69, app: Self.app, device: "iphone-6.9", locale: "en",
            slot: "02-daily", background: Self.background
        )
    }

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_iPhone_board() throws {
        try emitASCScreenshot(
            try boardView(),
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

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_iPhone_settings() async throws {
        try emitASCScreenshot(
            await settingsView(),
            profile: .iPhone69, app: Self.app, device: "iphone-6.9", locale: "en",
            slot: "05-settings", background: Self.background
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
            try boardView(),
            profile: .iPad13, app: Self.app, device: "ipad-13", locale: "en",
            slot: "03-board", background: Self.background
        )
    }

    // MARK: - Mac (2880×1800) — Home + Board

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_mac_home() throws {
        try emitASCScreenshot(
            homeView(),
            profile: .mac, app: Self.app, device: "mac", locale: "en",
            slot: "01-home", background: Self.background
        )
    }

    @Test(.enabled(if: ASCScreenshotEmit.isEnabled))
    func emit_mac_board() throws {
        try emitASCScreenshot(
            try boardView(),
            profile: .mac, app: Self.app, device: "mac", locale: "en",
            slot: "03-board", background: Self.background
        )
    }
}
#endif
