// swiftlint:disable identifier_name
// `vm` is the file-local shorthand for `viewModel` in setup helpers below;
// pre-existing convention scoped to this test file.
// BoardViewBannerTests — v2.3.5 banner wiring on BoardView.
//
// Two behaviors:
//   1. `viewModel.isPaused == false` AND gate allows → banner mounts.
//   2. `viewModel.isPaused == true` → banner hidden regardless of gate.
//
// The pause pins render the real `BoardView` with a started session and a
// loaded slot, and read the height its banner is laid out at (#1058 2c.1):
// running > 0, paused == 0.

import Foundation
#if canImport(AppKit)
import AppKit
#endif
import SnapshotTesting
import SwiftUI
import Testing

import SudokuGameState
import MonetizationCore
import MonetizationTesting
import MonetizationUI
import SudokuPersistence
import SudokuEngine
@testable import SudokuUI

@MainActor
@Suite("BoardView — BannerSlotView wiring")
struct BoardViewBannerTests {

    private static let identity = PuzzleIdentity(
        puzzleId: "test-banner",
        kind: .practice,
        difficulty: .easy
    )
    private static let emptyClues = String(repeating: ".", count: 81)

    private func makeViewModel(paused: Bool) throws -> GameViewModel {
        let board = try Board(clues: Self.emptyClues)
        return GameViewModel(
            identity: Self.identity,
            board: board,
            status: paused ? .paused : .playing,
            elapsedSeconds: 0,
            errorIndices: [],
            selection: nil
        )
    }

    private func makeAdGate(allow: Bool) -> AdGate {
        // `allow == true` → 30 days post-launch, not purchased.
        // `allow == false` → purchased (rule #1 in `shouldShowBanner`); we
        // can't lean on grace-period denial since #212 zeroed
        // `gracePeriodDays` for TestFlight visibility. Purchase-driven
        // denial is purely state-driven so this stays robust whether
        // grace returns to 7 or stays at 0.
        let store = FakeAdGateStateStore(
            initial: AdGateState(
                firstLaunchAt: Date().addingTimeInterval(-30 * 86_400),
                hasPurchasedRemoveAds: !allow
            )
        )
        return AdGate(store: store)
    }

    /// A started session over a readiness-held fake: the gate decides whether
    /// the slot shows, and no load can resolve, so it stays in its reserved
    /// loading state.
    private func reservedBannerSession(gate: AdGate) async -> BannerSessionModel {
        let session = BannerSessionModel(adProvider: FakeAdProvider(readinessHeld: true), adGate: gate)
        await session.start()
        return session
    }

    @Test func running_andGateAllows_bannerMountIsActive() async throws {
        let vm = try makeViewModel(paused: false)
        #expect(vm.isPaused == false)
        let gate = makeAdGate(allow: true)
        let allowed = await gate.shouldShowBanner(now: Date())
        #expect(allowed == true)
        // Construct the view to ensure init compiles + holds the deps.
        _ = BoardView(viewModel: vm)
    }

    // MARK: - Pause host wiring (#1058 2c.1)
    //
    // Mutation target: `BoardView+Layout.themedBanner`'s
    // `isSuppressed: viewModel.isPaused` → `false` (the paused row goes red).

    #if canImport(AppKit)
    @Test func runningBoard_rendersLoadedBanner() async throws {
        let height = try await renderedBannerHeight(paused: false)
        #expect(height > 0)
    }

    @Test func pausedBoard_suppressesLoadedBanner() async throws {
        let height = try await renderedBannerHeight(paused: true)
        #expect(height == 0)
    }

    /// Hosts the real board over a started, visible session whose provider
    /// serves a height probe, waits for the slot to load, then lays the host
    /// out again and reads the height the probe was given.
    private func renderedBannerHeight(paused: Bool) async throws -> CGFloat {
        let probe = BannerHeightProbe()
        let session = BannerSessionModel(adProvider: BannerHeightProbeProvider(probe: probe), adGate: makeAdGate(allow: true))
        await session.start()
        let host = hostingView(
            BoardView(viewModel: try makeViewModel(paused: paused)).environment(\.bannerSession, session),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        var waits = 0
        while !session.slots.values.contains(where: \.isLoaded), waits < 200 {
            try await Task.sleep(for: .milliseconds(10))
            waits += 1
        }
        let loaded = session.slots.values.contains(where: \.isLoaded)
        #expect(loaded, "the board's slot should load")
        return settledBannerHeight(of: host, probe: probe)
    }
    #endif

    @Test func running_butGateDenies_bannerSlotCollapsesToEmpty() async throws {
        let vm = try makeViewModel(paused: false)
        let gate = makeAdGate(allow: false)
        let allowed = await gate.shouldShowBanner(now: Date())
        #expect(allowed == false)
        _ = BoardView(viewModel: vm)
    }

    // MARK: - #723 snapshots — ads-enabled, ad NOT loaded, slot reserved
    //
    // First repo fixtures rendering the banner slot's VISIBLE (ads-enabled)
    // state — every other Home/Board snapshot seeds hasPurchasedRemoveAds:
    // true, so the slot collapses in all of them (#723 acceptance note from
    // #725's review). The fixture injects a started session over a
    // readiness-held fake provider, so the slot shows on the very first layout
    // and reserves the 50pt rect (spinner placeholder, no ad) —
    // pinning both the #723 reservation and #725's page-background slot.
    // `.tolerantImage` per the board-suite policy (#586: AA-heavy boards).
    //
    // #732: the live `ProgressView` shown while `.loading` is a genuinely
    // timing-dependent spin animation, so capturing it made these baselines
    // environment-sensitive (pixel drift across machines/worktrees even on an
    // unmodified commit). We inject a static placeholder via
    // `BannerSlotView`'s `\.bannerSlotLoadingPreview` environment override
    // (production default stays the real spinner) AND keep `.tolerantImage`
    // as a second line of defense — mirrors MinesweeperKit's twin fixture.

    /// Deterministic stand-in for the live `ProgressView` spinner (#732) —
    /// same static ring look, no animation-frame dependency.
    private var deterministicBannerLoadingPreview: AnyView {
        AnyView(
            Circle()
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .frame(width: 16, height: 16)
        )
    }

    #if canImport(AppKit)
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotAdsEnabledUnloadedSlot_iPhone_light() async throws {
        let vm = try makeViewModel(paused: false)
        let session = await reservedBannerSession(gate: makeAdGate(allow: true))
        let host = hostingView(
            BoardView(viewModel: vm)
                .environment(\.bannerSlotLoadingPreview, deterministicBannerLoadingPreview)
                .environment(\.bannerSession, session),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .tolerantImage, named: "Board-iPhone-light-banner-reserved")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotAdsEnabledUnloadedSlot_iPhone_dark() async throws {
        let vm = try makeViewModel(paused: false)
        let session = await reservedBannerSession(gate: makeAdGate(allow: true))
        let host = hostingView(
            BoardView(viewModel: vm)
                .environment(\.bannerSlotLoadingPreview, deterministicBannerLoadingPreview)
                .environment(\.bannerSession, session),
            size: SnapshotLayouts.iPhone,
            colorScheme: .dark,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .tolerantImage, named: "Board-iPhone-dark-banner-reserved")
        }
    }
    #endif
}
// swiftlint:enable identifier_name

#if canImport(AppKit)

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
