// RootView — bootstrap behavior tests.
//
// #557: RootView retired (GameHomeView + makeGameApp replace it).
// The snapshot baselines that were here snapshotted the full GameRoot
// navigation shell + HomeView — a superset of what HomeViewTests covers.
// HomeViewTests now snapshots GameHomeView (the inner content surface)
// with identical mode cards and subtitle copy. The GameRoot navigation
// shell is integration-tested via the live wired stack (AppComposition).
//
// Behavioral tests kept as-is — they test RootViewModel (= GameRootViewModel<AppRoute>)
// directly and do not reference RootView.

import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import SudokuUI

import GameAppKit
import GameCenterClient
import GameCenterTesting
import MonetizationCore
import MonetizationTesting
import Persistence
import SudokuPersistence
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
}
