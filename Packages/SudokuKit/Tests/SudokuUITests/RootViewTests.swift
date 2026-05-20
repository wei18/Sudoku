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

import GameCenterClient
import Persistence
import PuzzleStore
import SudokuKitTesting
import Telemetry

@MainActor
@Suite("RootView — bootstrap + snapshots")
struct RootViewTests {

    @Test func bootstrapCallsAuthenticateExactlyOnce() async {
        let gameCenter = FakeGameCenterClient()
        let persistence = FakePersistence()
        let viewModel = RootViewModel(gameCenter: gameCenter, persistence: persistence)

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
            mode: "daily",
            difficulty: "easy",
            lastModifiedAt: Date(timeIntervalSince1970: 1_715_000_000),
            elapsedSeconds: 201,
            status: "inProgress",
            generatorVersion: 1
        )
        let persistence = FakePersistence(resumeCandidate: summary)
        let viewModel = RootViewModel(
            gameCenter: FakeGameCenterClient(),
            persistence: persistence
        )

        await viewModel.bootstrap()

        #expect(viewModel.resumeCandidate == summary)
    }

    @Test func authFailureFallsBackToUnauthenticated() async {
        let gameCenter = FakeGameCenterClient()
        await gameCenter.setAuthResult(.failure(.cancelled))
        let viewModel = RootViewModel(
            gameCenter: gameCenter,
            persistence: FakePersistence()
        )

        await viewModel.bootstrap()

        #expect(viewModel.authState == .unauthenticated)
    }

    @Test func snapshotEmptyStateIPhoneLight() async {
        let viewModel = RootViewModel(
            gameCenter: FakeGameCenterClient(),
            persistence: FakePersistence()
        )
        await viewModel.bootstrap()

        let view = RootView(
            viewModel: viewModel,
            puzzleProvider: FakePuzzleProvider(),
            persistence: FakePersistence(),
            gameCenter: FakeGameCenterClient(),
            telemetry: Telemetry(sinks: [])
        )
        let host = hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .light, sizeClass: .compact)

        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "RootView-iPhone-light-empty")
        }
    }

    @Test func snapshotEmptyStateMacLight() async {
        let viewModel = RootViewModel(
            gameCenter: FakeGameCenterClient(),
            persistence: FakePersistence()
        )
        await viewModel.bootstrap()

        let view = RootView(
            viewModel: viewModel,
            puzzleProvider: FakePuzzleProvider(),
            persistence: FakePersistence(),
            gameCenter: FakeGameCenterClient(),
            telemetry: Telemetry(sinks: [])
        )
        let host = hostingView(view, size: SnapshotLayouts.mac, colorScheme: .light, sizeClass: .regular)

        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "RootView-Mac-light-empty")
        }
    }
}
