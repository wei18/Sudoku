// BoardLoaderViewFailedExitTests — issue #719.
//
// The `.failed` screen used to be a dead end on iOS: `fullScreenCover` has no
// interactive dismiss, and Retry was the ONLY affordance. Two things pin the
// fix:
//   1. `isLoaderFailLaunch` — the testable core behind the DEBUG-only
//      `-uitest-loader-fail` sim hook (mirrors `UITestLaunchArgTests`'s
//      `routeValue(in:)` coverage style: test the arg-parsing core directly,
//      not a live process relaunch).
//   2. A snapshot proving `failedBlock` renders BOTH Close and Retry, via the
//      `failedForSnapshot` seam (mirrors `MinesweeperBoardView`'s
//      `completionViewModelForSnapshot` pattern) — no live/fake persistence
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
@testable import SudokuUI

import Persistence
import SudokuEngine
import SudokuGameState
import SudokuPersistence
import Telemetry

@MainActor
@Suite("BoardLoaderView — .failed exit (#719)")
struct BoardLoaderViewFailedExitTests {

    // MARK: - Hook: testable core

    @Test func loaderFailArgPresentForcesTrue() {
        #expect(BoardLoaderView.isLoaderFailLaunch(arguments: ["-uitest-loader-fail"]))
    }

    @Test func loaderFailArgAbsentStaysFalse() {
        #expect(!BoardLoaderView.isLoaderFailLaunch(arguments: ["App", "-uitest-near-win"]))
    }

    // MARK: - Snapshot: failedBlock shows Close alongside Retry

    #if canImport(AppKit)
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshot_failed_iPhoneLight() {
        let host = hostingView(
            BoardLoaderView(
                puzzleId: "2026-05-21-easy",
                puzzleProvider: UnreachablePuzzleProvider(),
                persistence: UnreachablePersistence(),
                failedForSnapshot: .networkUnavailable
            ),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "BoardLoader-iPhone-light-failed")
        }
    }
    #endif
}

// MARK: - Unreachable fixtures

/// `failedForSnapshot` skips `.task`'s `load()` entirely, so these are never
/// actually invoked — they only exist to satisfy `BoardLoaderView.init`'s
/// required protocol params.
private struct UnreachablePuzzleProvider: PuzzleProviderProtocol {
    func fetchDailyTrio(date: Date) async throws -> [PuzzleEnvelope] {
        fatalError("UnreachablePuzzleProvider must not be called — failedForSnapshot skips load()")
    }
    func fetchPracticePool(difficulty: Difficulty) async throws -> PuzzleEnvelope {
        fatalError("UnreachablePuzzleProvider must not be called — failedForSnapshot skips load()")
    }
    func puzzle(for puzzleId: String) async throws -> Puzzle {
        fatalError("UnreachablePuzzleProvider must not be called — failedForSnapshot skips load()")
    }
}

private actor UnreachablePersistence: PersistenceProtocol {
    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(puzzleId: String, mode: Mode, difficulty: Difficulty) async throws -> GameSessionSnapshot {
        fatalError("UnreachablePersistence must not be called — failedForSnapshot skips load()")
    }
    func save(_ snapshot: GameSessionSnapshot, puzzleId: String, mode: Mode, difficulty: Difficulty) async throws {}
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> { [] }
    func fetchPersonalRecord(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        PersonalRecord(
            recordName: "",
            mode: .daily,
            difficulty: .easy,
            bestTimeSeconds: nil,
            totalTimeSeconds: 0,
            completedCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 0),
            completedPuzzleIds: []
        )
    }
    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}

#endif
