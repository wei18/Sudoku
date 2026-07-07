// MinesweeperBoardLoaderViewFailedExitTests — issue #719.
//
// The `.failed` screen used to be a dead end on iOS: `fullScreenCover` has no
// interactive dismiss, and Retry was the ONLY affordance. MS resume is
// genuinely reachable here (an offline tap on the Resume pill hits this path
// for real — MinesweeperSavedGameStore.loadInProgress swallows only
// `iCloudSignedOut`). Two things pin the fix:
//   1. `isLoaderFailLaunch` — the testable core behind the DEBUG-only
//      `-uitest-loader-fail` sim hook (mirrors `UITestLaunchArgTests`'s
//      `routeValue(in:)` coverage style: test the arg-parsing core directly,
//      not a live process relaunch).
//   2. A snapshot proving `failedBlock` renders BOTH Close and Retry, via the
//      `failedForSnapshot` seam (mirrors this file's own
//      `completionViewModelForSnapshot`-style pattern) — no live persistence
//      fetch involved.
//
// The actual dismiss-back-to-caller behavior (`@Environment(\.dismiss)`
// wiring) is verified by sim walkthrough, not a unit test — SwiftUI's
// `DismissAction` isn't interceptable outside a real presentation context.

#if DEBUG

import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import MinesweeperUI

import MinesweeperEngine
import MinesweeperPersistence
import Persistence
import PersistenceTesting
import Telemetry

@MainActor
@Suite("MinesweeperBoardLoaderView — .failed exit (#719)")
struct MinesweeperBoardLoaderViewFailedExitTests {

    // MARK: - Hook: testable core

    @Test func loaderFailArgPresentForcesTrue() {
        #expect(MinesweeperBoardLoaderView.isLoaderFailLaunch(arguments: ["-uitest-loader-fail"]))
    }

    @Test func loaderFailArgAbsentStaysFalse() {
        #expect(!MinesweeperBoardLoaderView.isLoaderFailLaunch(arguments: ["App", "-uitest-near-win"]))
    }

    // MARK: - Snapshot: failedBlock shows Close alongside Retry

    #if canImport(AppKit)
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshot_failed_iPhoneLight() {
        // `failedForSnapshot` skips `.task`'s `load()` entirely, so this
        // store/gateway is never actually invoked.
        let store = MinesweeperSavedGameStore(gateway: FakePrivateCKGateway())
        let host = hostingView(
            MinesweeperBoardLoaderView(
                recordName: "practice-beginner",
                mode: .practice,
                store: store,
                failedForSnapshot: .networkUnavailable
            ),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "MinesweeperBoardLoader-iPhone-light-failed")
        }
    }
    #endif
}

#endif
