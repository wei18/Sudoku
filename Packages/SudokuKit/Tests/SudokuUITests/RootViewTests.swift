// RootView — bootstrap behavior + snapshot baselines.
//
// Behavior: `authenticate()` is invoked exactly once on `.task`; resume
// candidate from Persistence surfaces as the Resume pill.
// Snapshots: empty state (no resume), iPhone + Mac, light only — Part 1
// scope. Part 2 (8.11) doubles light↔dark + locale matrix.

import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import SudokuUI

import GameAppKit
import GameCenterClient
import GameCenterTesting  // Stage 3: FakeGameCenterClient (was in SudokuKitTesting)
import MonetizationCore
import MonetizationTesting
import Persistence
import PuzzleStore
import SudokuEngine
import SudokuKitTesting
import Telemetry

// #455: mirrors the Sudoku composition `fetchResume` mapping — reads the
// injected `FakePersistence` and maps its `SavedGameSummary` into the
// game-agnostic `ResumeCandidate` with the same strings the pill renders.
private func sudokuFetchResume(
    _ persistence: FakePersistence
) -> () async throws -> ResumeCandidate<AppRoute>? {
    {
        guard let summary = try await persistence.latestInProgress() else { return nil }
        let minutes = summary.elapsedSeconds / 60
        let seconds = summary.elapsedSeconds % 60
        return ResumeCandidate(
            title: "Resume \(summary.difficulty.rawValue.capitalized)",
            subtitle: String(format: "%d:%02d", minutes, seconds),
            route: .board(puzzleId: summary.puzzleId)
        )
    }
}

@MainActor
private func makeTestRouteFactory() -> LiveRouteFactory {
    let store = FakeAdGateStateStore(
        initial: AdGateState(firstLaunchAt: Date(timeIntervalSince1970: 0))
    )
    return LiveRouteFactory(
        puzzleProvider: FakePuzzleProvider(),
        persistence: FakePersistence(),
        gameCenter: FakeGameCenterClient(),
        telemetry: Telemetry(sinks: []),
        adProvider: FakeAdProvider(),
        iapClient: FakeIAPClient(),
        adGate: AdGate(store: store)
    )
}

@MainActor
@Suite("RootView — bootstrap + snapshots")
struct RootViewTests {

    // Issue #196: regression — `RootViewModel.bootstrap()` must call
    // `persistence.bootstrap()` exactly once so the CloudKit zone is
    // provisioned before any read/write. Without this, fresh iCloud
    // accounts hit "Zone Not Found" (CKError 26) on every operation.
    @Test func bootstrapProvisionsPersistenceExactlyOnce() async {
        let persistence = FakePersistence()
        let viewModel = RootViewModel(
            gameCenter: FakeGameCenterClient(),
            persistence: persistence,
            fetchResume: sudokuFetchResume(persistence)
        )

        await viewModel.bootstrap()
        await viewModel.bootstrap()  // idempotent

        let operations = await persistence.operations
        let bootstrapCount = operations.filter { $0 == .bootstrap }.count
        #expect(bootstrapCount == 1)
    }

    @Test func bootstrapCallsAuthenticateExactlyOnce() async {
        let gameCenter = FakeGameCenterClient()
        let persistence = FakePersistence()
        let viewModel = RootViewModel(
            gameCenter: gameCenter,
            persistence: persistence,
            fetchResume: sudokuFetchResume(persistence)
        )

        await viewModel.bootstrap()
        await viewModel.bootstrap()  // idempotent

        let operations = await gameCenter.operations
        let authCount = operations.filter { $0 == .authenticate }.count
        #expect(authCount == 1)
    }

    @Test func resumeCandidateFromPersistenceSurfacesOnViewModel() async {
        let summary = SavedGameSummary(
            recordName: "saved-2026-05-19-easy",
            puzzleId: "2026-05-19-easy",
            mode: .daily,
            difficulty: .easy,
            lastModifiedAt: Date(timeIntervalSince1970: 1_715_000_000),
            elapsedSeconds: 201,
            status: "inProgress",
            generatorVersion: 1
        )
        let persistence = FakePersistence(resumeCandidate: summary)
        let viewModel = RootViewModel(
            gameCenter: FakeGameCenterClient(),
            persistence: persistence,
            fetchResume: sudokuFetchResume(persistence)
        )

        await viewModel.bootstrap()

        // #455: `resumeCandidate` is now the game-agnostic DTO, not the
        // Sudoku-typed `SavedGameSummary`. Assert the mapped fields ("Resume
        // Easy" + "3:21" for 201s) + the board route.
        #expect(viewModel.resumeCandidate == ResumeCandidate(
            title: "Resume Easy",
            subtitle: "3:21",
            route: .board(puzzleId: summary.puzzleId)
        ))
    }

    @Test func authFailureFallsBackToUnauthenticated() async {
        let gameCenter = FakeGameCenterClient()
        await gameCenter.setAuthResult(.failure(.cancelled))
        let persistence = FakePersistence()
        let viewModel = RootViewModel(
            gameCenter: gameCenter,
            persistence: persistence,
            fetchResume: sudokuFetchResume(persistence)
        )

        await viewModel.bootstrap()

        #expect(viewModel.authState == .unauthenticated)
    }

    #if canImport(AppKit)
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotEmptyStateIPhoneLight() async {
        let persistence = FakePersistence()
        let viewModel = RootViewModel(
            gameCenter: FakeGameCenterClient(),
            persistence: persistence,
            fetchResume: sudokuFetchResume(persistence)
        )
        await viewModel.bootstrap()

        let view = RootView(
            viewModel: viewModel,
            routeFactory: makeTestRouteFactory()
        )
        let host = hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .light, sizeClass: .compact)

        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "RootView-iPhone-light-empty")
        }
    }

    // #387: with a resume candidate the ResumePill must render as the FIRST
    // child INSIDE HomeView's scroll region (above the mode cards), so it
    // scrolls with the content instead of staying pinned at the top. This
    // baseline pins that placement.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotResumeCandidateIPhoneLight() async {
        let summary = SavedGameSummary(
            recordName: "saved-2026-05-19-easy",
            puzzleId: "2026-05-19-easy",
            mode: .daily,
            difficulty: .easy,
            lastModifiedAt: Date(timeIntervalSince1970: 1_715_000_000),
            elapsedSeconds: 201,
            status: "inProgress",
            generatorVersion: 1
        )
        let persistence = FakePersistence(resumeCandidate: summary)
        let viewModel = RootViewModel(
            gameCenter: FakeGameCenterClient(),
            persistence: persistence,
            fetchResume: sudokuFetchResume(persistence)
        )
        await viewModel.bootstrap()

        let view = RootView(
            viewModel: viewModel,
            routeFactory: makeTestRouteFactory()
        )
        let host = hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .light, sizeClass: .compact)

        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "RootView-iPhone-light-resume")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotEmptyStateMacLight() async {
        let persistence = FakePersistence()
        let viewModel = RootViewModel(
            gameCenter: FakeGameCenterClient(),
            persistence: persistence,
            fetchResume: sudokuFetchResume(persistence)
        )
        await viewModel.bootstrap()

        let view = RootView(
            viewModel: viewModel,
            routeFactory: makeTestRouteFactory()
        )
        let host = hostingView(view, size: SnapshotLayouts.mac, colorScheme: .light, sizeClass: .regular)

        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "RootView-Mac-light-empty")
        }
    }
    #endif
}
