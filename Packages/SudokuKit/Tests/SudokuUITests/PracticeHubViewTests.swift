// PracticeHubView — shimmer threshold + 3-state snapshots.

import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import SudokuUI

import PuzzleStore
import SudokuEngine
import SudokuKitTesting

@MainActor
@Suite("PracticeHubView — shimmer + snapshots")
struct PracticeHubViewTests {

    @Test func subThresholdDrawSkipsShimmer() async {
        let provider = FakePuzzleProvider()
        // 50 ms artificial delay — below the 100 ms shimmer threshold.
        await provider.setArtificialDelay(nanos: 50_000_000)
        let viewModel = PracticeHubViewModel(
            provider: provider,
            shimmerDelayNanos: 100_000_000
        )

        await viewModel.drawPuzzle()

        if case .drawn = viewModel.loadingState {
            // ok
        } else {
            Issue.record("expected drawn, got \(viewModel.loadingState)")
        }
    }

    @Test func overThresholdDrawShowsShimmer() async {
        let provider = FakePuzzleProvider()
        // 800 ms fetch + 50 ms shimmer — large margins to survive parallel
        // test scheduling jitter.
        await provider.setArtificialDelay(nanos: 800_000_000)
        let viewModel = PracticeHubViewModel(
            provider: provider,
            shimmerDelayNanos: 50_000_000
        )

        // Kick off the draw and observe an intermediate shimmer state.
        let drawTask = Task { await viewModel.drawPuzzle() }
        // Sleep well past shimmer threshold but before fetch completes.
        try? await Task.sleep(nanoseconds: 400_000_000)
        let mid = viewModel.loadingState
        await drawTask.value

        #expect(mid == .drawingShimmer)
    }

    @Test func selectDifficultyResetsLoadingState() async {
        let viewModel = PracticeHubViewModel(provider: FakePuzzleProvider())
        await viewModel.drawPuzzle()

        viewModel.selectDifficulty(.hard)

        #expect(viewModel.loadingState == .idle)
        #expect(viewModel.difficulty == .hard)
    }

    @Test func playTappedFromDrawnAppendsBoardRoute() async {
        let viewModel = PracticeHubViewModel(provider: FakePuzzleProvider())
        await viewModel.drawPuzzle()

        viewModel.playTapped()

        #expect(viewModel.path.count == 1)
        guard case .board = viewModel.path[0] else {
            Issue.record("expected board route")
            return
        }
    }

    // MARK: - Snapshots

    @Test func snapshotIdleIPhoneLight() async {
        let viewModel = PracticeHubViewModel(provider: FakePuzzleProvider())
        let view = PracticeHubView(viewModel: viewModel).preferredColorScheme(.light)
        let host = hostingView(view, size: SnapshotLayouts.iPhone)
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "PracticeHub-iPhone-light-idle")
        }
    }

    @Test func snapshotShimmerIPhoneLight() async {
        let viewModel = PracticeHubViewModel(provider: FakePuzzleProvider())
        viewModel.setLoadingStateForTesting(.drawingShimmer)
        let view = PracticeHubView(viewModel: viewModel).preferredColorScheme(.light)
        let host = hostingView(view, size: SnapshotLayouts.iPhone)
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "PracticeHub-iPhone-light-shimmer")
        }
    }

    @Test func snapshotDrawnIPhoneLight() async {
        let provider = FakePuzzleProvider()
        let viewModel = PracticeHubViewModel(provider: provider)
        await viewModel.drawPuzzle()
        let view = PracticeHubView(viewModel: viewModel).preferredColorScheme(.light)
        let host = hostingView(view, size: SnapshotLayouts.iPhone)
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "PracticeHub-iPhone-light-drawn")
        }
    }
}

