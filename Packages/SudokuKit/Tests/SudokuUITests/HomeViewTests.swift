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
        homeModes: sudokuHomeModes
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
    let homeVM = GameHomeViewModel(rootViewModel: rootVM, homeModes: sudokuHomeModes)
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
