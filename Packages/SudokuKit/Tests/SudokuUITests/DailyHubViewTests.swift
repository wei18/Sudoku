// DailyHubView — bootstrap, exhausted alert, and 3-state snapshots.

import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import SudokuUI

import Persistence
import PuzzleStore
import SudokuKitTesting

@MainActor
@Suite("DailyHubView — bootstrap + snapshots")
struct DailyHubViewTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    private func makeViewModel(
        completedDailyIds: Set<String> = [],
        providerResult: Result<[PuzzleEnvelope], PuzzleStoreError>? = nil
    ) async -> DailyHubViewModel {
        let provider = FakePuzzleProvider()
        let result = providerResult ?? .success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate))
        await provider.setDailyTrioResult(result)
        let persistence = FakePersistence(completedDailyIds: completedDailyIds)
        return DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            dateProvider: { Self.fixedDate }
        )
    }

    @Test func bootstrapLoadsTrioAndMergesCompletion() async {
        let envelopes = FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)
        let easyId = envelopes[0].identity.puzzleId

        let viewModel = await makeViewModel(completedDailyIds: [easyId])
        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(cards.count == 3)
        #expect(cards[0].isCompleted == true)
        #expect(cards[1].isCompleted == false)
        #expect(cards[2].isCompleted == false)
    }

    @Test func generatorFailureMapsToExhaustedState() async {
        let viewModel = await makeViewModel(
            providerResult: .failure(.generatorFailed(underlying: "exhausted"))
        )

        await viewModel.bootstrap()

        #expect(viewModel.state == .exhausted)
    }

    @Test func cardTapAppendsBoardRoute() async {
        let viewModel = await makeViewModel()
        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded")
            return
        }

        viewModel.cardTapped(cards[1])
        #expect(viewModel.path == [.board(puzzleId: cards[1].envelope.identity.puzzleId)])
    }

    // MARK: - Snapshots

    #if canImport(AppKit)
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotUnfinishedIPhoneLight() async {
        let viewModel = await makeViewModel()
        await viewModel.bootstrap()
        let host = hostingView(
            DailyHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPhone-light-unfinished")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotEasyCompletedIPhoneLight() async {
        let envelopes = FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)
        let easyId = envelopes[0].identity.puzzleId
        let viewModel = await makeViewModel(completedDailyIds: [easyId])
        await viewModel.bootstrap()
        let host = hostingView(
            DailyHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPhone-light-easyDone")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotAllCompletedIPhoneLight() async {
        let envelopes = FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)
        let allIds = Set(envelopes.map(\.identity.puzzleId))
        let viewModel = await makeViewModel(completedDailyIds: allIds)
        await viewModel.bootstrap()
        let host = hostingView(
            DailyHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPhone-light-allDone")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotUnfinishedIPadLight() async {
        let viewModel = await makeViewModel()
        await viewModel.bootstrap()
        let host = hostingView(
            DailyHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPad,
            colorScheme: .light,
            sizeClass: .regular
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPad-light-unfinished")
        }
    }
    #endif
}
