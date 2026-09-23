// BannerSlotDarkBandRegressionTests — #851 deterministic repro, retargeted
// to a SHIPPED composition in #1097.
//
// What this pins: in dark mode, the banner slot must paint no visible band
// (seam) against the page it sits on. #866 fixed #851 by giving
// `BannerSlotView` the SAME `theme.surface.background` token the page paints
// itself with, replacing a stale `Color.secondary.opacity(0.12)` system-gray
// tint that read as a lighter rounded band on the dark ground.
//
// Which composition, and why this one:
//   - The original pin (session 064a54f6, #851) rendered the hub shell with
//     the slot composed BELOW `DailyHubView`. #1024 / #1080 moved the hub
//     banner into `tabViewBottomAccessory` (`GameAppKit.BannerAccessoryView`,
//     leased by `GameRoot`), so that composition no longer ships; #1096 kept
//     the pin alive on a hand-reconstructed VStack, and #1097 retargets it.
//   - The accessory itself CANNOT be pixel-pinned on this harness:
//     `BannerAccessoryView.swift` and `RootShellView`'s
//     `.tabViewBottomAccessory(...)` are both `#if os(iOS)`, and the macOS
//     build `swift test` uses (`NSHostingView`, `SnapshotConfig.swift`)
//     ships `EmptyView()` in that slot. Only an iOS-Simulator XCUITest could
//     see it.
//   - The board screen's slot (`BoardView+Layout.swift` `themedBanner`,
//     between the grid and the control cluster) is the shipped composition
//     that renders on this harness AND uses the same `surface.background`
//     token, so the pin lives there now.
//
// Strictness: `.image` (precision 1.0), deliberately NOT `.tolerantImage`
// like `BoardViewBannerTests`' sibling of the same state — a 12 %-alpha band
// over the slot area is ~1 % of the frame, inside a 0.95 tolerance, so only
// a strict compare catches the regression. Mutant proof (#1097): with
// `themedBanner`'s `backgroundColor` temporarily set back to
// `Color.secondary.opacity(0.12)`, this test fails; with the token, it
// passes.
//
// Determinism: the ad gate is OPEN and the session is started over a
// readiness-held fake provider BEFORE the view is built, so the slot renders
// reserved-but-unloaded on the first synchronous layout pass; the live
// loading spinner is replaced by the static ring via
// `\.bannerSlotLoadingPreview` (#732).

import Foundation
import SnapshotTesting
import SwiftUI
import Testing

import MonetizationCore
import MonetizationTesting
import MonetizationUI
import SudokuEngine
import SudokuGameState
import SudokuPersistence
@testable import SudokuUI

@MainActor
@Suite("BannerSlotView — dark-mode band regression (#851)")
struct BannerSlotDarkBandRegressionTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    private static let identity = PuzzleIdentity(
        puzzleId: "test-dark-band",
        kind: .practice,
        difficulty: .easy
    )
    private static let emptyClues = String(repeating: ".", count: 81)

    /// An `AdGate` that resolves OPEN at `fixedDate` — see file header for why
    /// the session is started before the view is built.
    private func makeOpenAdGate() async -> AdGate {
        let store = FakeAdGateStateStore(
            initial: AdGateState(firstLaunchAt: Self.fixedDate.addingTimeInterval(-30 * 86_400))
        )
        let gate = AdGate(store: store)
        let allowed = await gate.shouldShowBanner(now: Self.fixedDate)
        #expect(allowed == true)
        return gate
    }

    /// A playing board with no clues and no selection — the same fixture
    /// `BoardViewBannerTests` renders, so the two suites disagree only on
    /// tolerance, never on content.
    private func makePlayingViewModel() throws -> GameViewModel {
        let board = try Board(clues: Self.emptyClues)
        return GameViewModel(
            identity: Self.identity,
            board: board,
            status: .playing,
            elapsedSeconds: 0,
            errorIndices: [],
            selection: nil
        )
    }

    /// Deterministic stand-in for the live `ProgressView` spinner (#732).
    private var deterministicBannerLoadingPreview: AnyView {
        AnyView(
            Circle()
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .frame(width: 16, height: 16)
        )
    }

    #if canImport(AppKit)

    // MARK: - Post-#866: themed background — the shipped board slot

    /// Pins the fix on the board screen: the slot's background must equal the
    /// page's own `surface.background` token so no seam is visible in dark
    /// mode. Strict compare; see the file header for the mutant proof.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func postFix_themedBackground_boardDarkMode_bannerOpen_noBand() async throws {
        let session = BannerSessionModel(
            adProvider: FakeAdProvider(readinessHeld: true),
            adGate: await makeOpenAdGate(),
            now: { Self.fixedDate }
        )
        await session.start()
        let viewModel = try makePlayingViewModel()

        let host = hostingView(
            BoardView(viewModel: viewModel)
                .environment(\.bannerSlotLoadingPreview, deterministicBannerLoadingPreview)
                .environment(\.bannerSession, session),
            size: SnapshotLayouts.iPhone,
            colorScheme: .dark,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "Board-iPhone-dark-bannerOpen-postFix")
        }
    }

    #endif
}
