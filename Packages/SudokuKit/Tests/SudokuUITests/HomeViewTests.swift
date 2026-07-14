// HomeView — selection routes correctly + snapshot baselines.
//
// #557: HomeView/HomeViewModel retired; tests migrated to GameHomeView /
// GameHomeViewModel<AppRoute>. The empty-state baselines (no ResumePill, no
// banner) are unchanged — GameHomeView renders pixel-identically to the former
// HomeView for those cases.
//
// #557 review (Finding 1): the UNIVERSAL ResumePill mount (#554 render-site
// half) is the core deliverable, so `snapshotResumeCandidateIPhoneLight`
// renders GameHomeView WITH a non-nil resume candidate and pins the ResumePill
// as the first child in the scroll region. This is NEW shared-view coverage —
// its baseline was recorded once and eyeballed (pill visible above the cards),
// not inherited from the retired RootViewTests.

import Foundation
import GameAppKit
import GameCenterTesting
import GameShellUI
import MonetizationCore
import MonetizationTesting
import MonetizationUI
import Persistence
import SnapshotTesting
import SudokuKitTesting
import SwiftUI
import Testing
@testable import SudokuUI

// Helper: build a minimal rootViewModel + GameHomeViewModel with Sudoku defaults.
@MainActor
private func makeSudokuHomeViewModel(
    persistence: any PersistenceProtocol = FakePersistence()
) -> (rootVM: RootViewModel, homeVM: GameHomeViewModel<AppRoute>) {
    let rootVM = RootViewModel(
        gameCenter: FakeGameCenterClient(),
        persistence: persistence
    )
    let homeVM = GameHomeViewModel(
        rootViewModel: rootVM,
        homeModes: sudokuHomeModes,
        // #773: mirrors SudokuAppComposition.live()'s statsRoute so the Home
        // snapshots pin the secondary-weight Statistics entry below the cards.
        statsRoute: .stats
    )
    return (rootVM, homeVM)
}

// #557 Finding 1: build a rootVM whose `resumeCandidate` is populated (via an
// inline fetchResume + bootstrap, since the property is `private(set)`), plus the
// home VM — so GameHomeView renders the ResumePill header. Mirrors the resume
// strings the retired RootViewTests used ("Resume Easy" / "3:21").
@MainActor
private func makeSudokuHomeViewModelWithResume() async -> (
    rootVM: RootViewModel, homeVM: GameHomeViewModel<AppRoute>
) {
    let rootVM = RootViewModel(
        gameCenter: FakeGameCenterClient(),
        persistence: FakePersistence(),
        fetchResume: {
            ResumeCandidate(
                title: "Resume Easy",
                subtitle: "3:21",
                route: .board(puzzleId: "2026-05-19-easy")
            )
        }
    )
    await rootVM.bootstrap()
    let homeVM = GameHomeViewModel(
        rootViewModel: rootVM, homeModes: sudokuHomeModes, statsRoute: .stats
    )
    return (rootVM, homeVM)
}

// Sudoku's per-mode subtitle copy — same literals as former HomeViewModel.subtitleKey
// extension, kept here so snapshot text is byte-identical.
@MainActor
private let sudokuHomeModes: [HomeMode: HomeModeContent<AppRoute>] = [
    .daily: HomeModeContent<AppRoute>(subtitleKey: "3 puzzles today", route: .daily),
    .practice: HomeModeContent<AppRoute>(subtitleKey: "Mixed difficulty pool", route: .practice),
    .leaderboard: HomeModeContent<AppRoute>(subtitleKey: "Global / friends"),
    .settings: HomeModeContent<AppRoute>(subtitleKey: "Account / language", route: .settings)
]

@MainActor
@Suite("HomeView — selection + snapshots")
struct HomeViewTests {

    @Test func selectDailyAppendsDailyRoute() {
        let (rootVM, homeVM) = makeSudokuHomeViewModel()
        homeVM.select(.daily)
        #expect(rootVM.path == [.daily])
    }

    @Test func selectPracticeAppendsPracticeRoute() {
        let (rootVM, homeVM) = makeSudokuHomeViewModel()
        homeVM.select(.practice)
        #expect(rootVM.path == [.practice])
    }

    @Test func selectSettingsAppendsSettingsRoute() {
        let (rootVM, homeVM) = makeSudokuHomeViewModel()
        homeVM.select(.settings)
        #expect(rootVM.path == [.settings])
    }

    // #773: the secondary-weight Statistics entry pushes `.stats`.
    @Test func selectStatsAppendsStatsRoute() {
        let (rootVM, homeVM) = makeSudokuHomeViewModel()
        #expect(homeVM.showsStatsEntry)
        homeVM.selectStats()
        #expect(rootVM.path == [.stats])
    }

    #if canImport(AppKit)
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotIPhoneLight() {
        let (rootVM, homeVM) = makeSudokuHomeViewModel()
        let host = hostingView(
            GameHomeView(
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
            ),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "HomeView-iPhone-light")
        }
        assertViewStructure(of: host, named: "HomeView-iPhone-light", record: SnapshotMode.recordMode)
    }

    // #762 PR1 spec item E — AX5 smoke snapshot. `HomeScreen` + `HomeModeCard`
    // (GameShellUI) are the D-migration exemplar: their padding/gaps now
    // route through `ScaledSpacing` (content tier) and `theme.spacing.*`
    // (structural tier). This snapshot exercises the new `hostingView(...,
    // dynamicTypeSize:)` overload (SnapshotConfig.swift) at `.accessibility5`
    // and pins the `ScaledSpacing` multiplier's visual effect (cards render
    // taller / more inset than `snapshotIPhoneLight`'s baseline).
    //
    // CAVEAT (found recording this baseline): comparing this PNG against
    // `snapshotIPhoneLight`'s, the spacing visibly grows but the semantic
    // `Font` sizes (`.title3`, `.caption`, …) do NOT — text renders
    // identically to the default-size snapshot, same as `@ScaledMetric`'s
    // documented failure to respond to `dynamicTypeSize` overrides in this
    // repo's headless `swift test` host (see `ScaledSpacing.swift`'s PIVOT
    // note). So this snapshot is a real, meaningful `ScaledSpacing`-scaling
    // baseline, but it is NOT a truncation regression guard — text never
    // grows here, so nothing could truncate. Real on-device/simulator AX5
    // truncation testing is out of this PR's scope (would need the
    // `mise-tasks/test/ui` XCUITest path or manual QA, not this unit/
    // snapshot harness).
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotAccessibility5IPhoneLight() {
        let (rootVM, homeVM) = makeSudokuHomeViewModel()
        let host = hostingView(
            GameHomeView(
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
            ),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact,
            dynamicTypeSize: .accessibility5
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "HomeView-iPhone-light-accessibility5")
        }
        assertViewStructure(of: host, named: "HomeView-iPhone-light-accessibility5", record: SnapshotMode.recordMode)
    }

    // #557 Finding 1: ResumePill render-site coverage for the shared view. The
    // pill must appear as the FIRST child of HomeScreen's scroll region (above
    // the mode cards), so it scrolls WITH the content (#387 placement) — this is
    // the #554 half-b universal-mount the migration delivers. NEW baseline,
    // recorded once and eyeballed.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotResumeCandidateIPhoneLight() async {
        let (rootVM, homeVM) = await makeSudokuHomeViewModelWithResume()
        let host = hostingView(
            GameHomeView(
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
            ),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "HomeView-iPhone-light-resume")
        }
        assertViewStructure(of: host, named: "HomeView-iPhone-light-resume", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotIPadLight() {
        let (rootVM, homeVM) = makeSudokuHomeViewModel()
        let host = hostingView(
            GameHomeView(
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
            ),
            size: SnapshotLayouts.iPad,
            colorScheme: .light,
            sizeClass: .regular
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "HomeView-iPad-light")
        }
        assertViewStructure(of: host, named: "HomeView-iPad-light", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotMacLight() {
        let (rootVM, homeVM) = makeSudokuHomeViewModel()
        let host = hostingView(
            GameHomeView(
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
            ),
            size: SnapshotLayouts.mac,
            colorScheme: .light,
            sizeClass: .regular
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "HomeView-Mac-light")
        }
        assertViewStructure(of: host, named: "HomeView-Mac-light", record: SnapshotMode.recordMode)
    }
    #endif
}
