// PracticeHubView — shimmer threshold + 3-state snapshots.
//
// #1021 Phase C: `snapshotIdleIPhoneLight`/`snapshotShimmerIPhoneLight`/
// `snapshotDrawnIPhoneLight` below are LEFT UNCHANGED (still exercising the
// pre-redesign layout's committed baselines) rather than re-recorded —
// design.md §3.2 replaces the segmented difficulty Picker with 3 density-
// preview cards, so those 3 PNGs now intentionally diff (`.missing` record
// mode compares, doesn't overwrite). Re-recording those baselines is a
// Leader/CR decision, not this dispatch's call. The NEW layout gets its own
// freshly-named snapshots below instead (`-default`/`-selectedHard`/
// `-accessibility3`), which record clean on first run.

import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import SudokuUI

import SudokuPersistence
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

    // The shimmer transition is split into two deterministic tests rather
    // than driven by wall-clock timing. The previous wall-clock test (kick
    // off drawPuzzle, sleep 400ms, assert state) was flaky under parallel
    // MainActor contention: when other @MainActor suites held the global
    // main actor, the internal 50ms shimmer wake-up was sometimes deferred
    // past the test's 400ms read, leaving state at .drawingQuiet.
    //
    // The integration path (drawPuzzle actually spawns the shimmer task)
    // remains covered by subThresholdDrawSkipsShimmer above: if the timer
    // gating were broken, that test would land on .drawingShimmer instead
    // of .drawn under its sub-threshold delay.

    @Test func promoteToShimmerFlipsFromDrawingQuiet() {
        let viewModel = PracticeHubViewModel(provider: FakePuzzleProvider())
        viewModel.setLoadingStateForTesting(.drawingQuiet)

        viewModel.promoteToShimmer()

        #expect(viewModel.loadingState == .drawingShimmer)
    }

    @Test func promoteToShimmerNoOpFromNonQuietStates() {
        let viewModel = PracticeHubViewModel(provider: FakePuzzleProvider())

        viewModel.setLoadingStateForTesting(.idle)
        viewModel.promoteToShimmer()
        #expect(viewModel.loadingState == .idle)

        viewModel.setLoadingStateForTesting(.failed("boom"))
        viewModel.promoteToShimmer()
        #expect(viewModel.loadingState == .failed("boom"))
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

    #if canImport(AppKit)
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotIdleIPhoneLight() async {
        let viewModel = PracticeHubViewModel(provider: FakePuzzleProvider())
        let host = hostingView(
            PracticeHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "PracticeHub-iPhone-light-idle")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotShimmerIPhoneLight() async {
        let viewModel = PracticeHubViewModel(provider: FakePuzzleProvider())
        viewModel.setLoadingStateForTesting(.drawingShimmer)
        let host = hostingView(
            PracticeHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "PracticeHub-iPhone-light-shimmer")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotDrawnIPhoneLight() async {
        let provider = FakePuzzleProvider()
        let viewModel = PracticeHubViewModel(provider: provider)
        await viewModel.drawPuzzle()
        let host = hostingView(
            PracticeHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "PracticeHub-iPhone-light-drawn")
        }
    }

    // MARK: - #1021 Phase C: density-preview card layout

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotDefaultIPhoneLight() async {
        let viewModel = PracticeHubViewModel(provider: FakePuzzleProvider())
        let host = hostingView(
            PracticeHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "PracticeHub-iPhone-light-default")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotSelectedHardIPhoneLight() async {
        let viewModel = PracticeHubViewModel(provider: FakePuzzleProvider(), initialDifficulty: .hard)
        let host = hostingView(
            PracticeHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "PracticeHub-iPhone-light-selectedHard")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotAccessibility3IPhoneLight() async {
        let viewModel = PracticeHubViewModel(provider: FakePuzzleProvider())
        let host = hostingView(
            PracticeHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact,
            dynamicTypeSize: .accessibility3
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "PracticeHub-iPhone-light-accessibility3")
        }
    }

    /// AX3 Dynamic Type pin on an iPad-width REGULAR size class — #1021
    /// Phase G. Reproduces the Leader's iPad Pro 11 finding: the shell's
    /// fixed, screen-filling `VStack` under the large "Practice" title
    /// overlapped the "Difficulty" section label once the title needed
    /// more vertical space at AX3. `PracticeHubShellView` now wraps that
    /// content in a `ScrollView` so it flows below the title instead —
    /// confirms no overlap on an iPad-width regular layout.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotAccessibility3IPadLight() async {
        let viewModel = PracticeHubViewModel(provider: FakePuzzleProvider())
        let host = hostingView(
            PracticeHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPad,
            colorScheme: .light,
            sizeClass: .regular,
            dynamicTypeSize: .accessibility3
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "PracticeHub-iPad-light-accessibility3")
        }
    }
    #endif
}
