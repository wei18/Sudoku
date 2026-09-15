// MinesweeperBoardBannerSuppressionTests — the board's banner host wiring
// (#1058 2c.1). Renders the real `MinesweeperBoardView` over a started session
// with a loaded slot and reads the height its banner is laid out at:
// running > 0, paused == 0, terminal == 0.
//
// Mutation targets: `MinesweeperBoardView.bannerSlot`'s
// `isSuppressed: viewModel.isTerminal || viewModel.isPaused` → `false` (paused
// and terminal rows go red), and → `viewModel.isPaused` (terminal row goes red).

#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI
import Testing

import MinesweeperEngine
import MinesweeperGameState
import MonetizationCore
import MonetizationTesting
import MonetizationUI
@testable import MinesweeperUI

@MainActor
@Suite("MinesweeperBoardView — banner suppression host wiring (#1058)", .timeLimit(.minutes(1)))
struct MinesweeperBoardBannerSuppressionTests {

    @Test func runningBoard_rendersLoadedBanner() async throws {
        #expect(try await renderedBannerHeight(status: .playing) > 0)
    }

    @Test func pausedBoard_suppressesLoadedBanner() async throws {
        #expect(try await renderedBannerHeight(status: .paused) == 0)
    }

    @Test func terminalBoard_suppressesLoadedBanner() async throws {
        #expect(try await renderedBannerHeight(status: .lost) == 0)
    }

    /// Hosts the real board over a started, visible session whose provider
    /// serves a height probe, waits for the slot to load, then lays the host
    /// out again and reads the height the probe was given.
    private func renderedBannerHeight(status: MinesweeperSessionStatus) async throws -> CGFloat {
        let probe = BannerHeightProbe()
        let gate = AdGate(store: FakeAdGateStateStore(initial: AdGateState(firstLaunchAt: Date(timeIntervalSince1970: 0))))
        let session = BannerSessionModel(adProvider: BannerHeightProbeProvider(probe: probe), adGate: gate)
        await session.start()
        let difficulty = Difficulty.beginner
        let snapshot = MinesweeperSessionSnapshot(
            difficulty: difficulty,
            cells: Array(repeating: Cell(state: .hidden), count: difficulty.rows * difficulty.columns),
            status: status,
            elapsedSeconds: 42,
            mineCount: difficulty.mineCount,
            flagCount: 0
        )
        let board = MinesweeperBoardView(
            viewModel: MinesweeperGameViewModel(seeded: snapshot),
            suppressTickerForSnapshot: true,
            tapModeDefaults: BoardTestDefaults.store
        )
        .environment(\.bannerSession, session)
        let host = hostingView(board, size: SnapshotLayouts.iPhone, colorScheme: .light)

        var waits = 0
        while !session.slots.values.contains(where: \.isLoaded), waits < 200 {
            try await Task.sleep(for: .milliseconds(10))
            waits += 1
        }
        let loaded = session.slots.values.contains(where: \.isLoaded)
        #expect(loaded, "the board's slot should load")
        return settledBannerHeight(of: host, probe: probe)
    }
}

/// Records the tallest height the banner slot lays its loaded banner out at.
@MainActor
private final class BannerHeightProbe {
    private(set) var height: CGFloat = 0

    func clearView(recording newHeight: CGFloat) -> Color {
        height = max(height, newHeight)
        return .clear
    }
}

/// Serves a loaded banner whose view is a height probe.
private actor BannerHeightProbeProvider: AdProvider, BannerViewProviding {
    nonisolated let probe: BannerHeightProbe

    init(probe: BannerHeightProbe) {
        self.probe = probe
    }

    func initialize() async throws {}

    func awaitReady() async throws {}

    var bannerStatus: AdBannerStatus { .notInitialized }

    func refreshBanner() async throws -> AdBannerHandle { AdBannerHandle() }

    func dispose(handle: AdBannerHandle) async {}

    @MainActor
    func bannerView(for handle: AdBannerHandle) -> AnyView? {
        let probe = probe
        return AnyView(GeometryReader { proxy in probe.clearView(recording: proxy.size.height) })
    }
}

/// Lays the host out until the probe reports a height or the passes run out,
/// letting SwiftUI apply the session's observation updates between passes.
@MainActor
private func settledBannerHeight(of host: NSView, probe: BannerHeightProbe, passes: Int = 25) -> CGFloat {
    for _ in 0..<passes where probe.height == 0 {
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    return probe.height
}

private extension AdBannerStatus {
    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }
}
#endif
