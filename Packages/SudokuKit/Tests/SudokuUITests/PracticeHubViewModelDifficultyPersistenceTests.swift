// PracticeHubViewModelDifficultyPersistenceTests — #720 G1: Practice's
// last-selected difficulty must survive a relaunch instead of always
// resetting to Medium. `PracticeHubViewModelInteractionTests` covers the
// draw/play service-call shape; this suite isolates the seed-from-persistence
// / persist-on-select seam itself (the composition root's concrete
// `LastSelectionStore` wiring is exercised separately in
// `GameAppKitTests.LastSelectionStoreTests`).

import Foundation
import Testing
@testable import SudokuUI

import SudokuEngine
import SudokuKitTesting

@MainActor
@Suite("PracticeHubViewModel — last-selected-difficulty persistence (#720 G1)")
struct PracticeHubViewModelDifficultyPersistenceTests {

    @Test("No initial difficulty given → defaults to Medium (unchanged behavior)")
    func defaultsToMediumWhenNoInitialDifficultyGiven() {
        let viewModel = PracticeHubViewModel(provider: FakePuzzleProvider())
        #expect(viewModel.difficulty == .medium)
    }

    @Test("initialDifficulty seeds the view model's difficulty")
    func initialDifficultySeedsDifficulty() {
        let viewModel = PracticeHubViewModel(provider: FakePuzzleProvider(), initialDifficulty: .hard)
        #expect(viewModel.difficulty == .hard)
    }

    @Test("selectDifficulty invokes the injected persist closure with the new value")
    func selectDifficultyPersists() {
        var persisted: [Difficulty] = []
        let viewModel = PracticeHubViewModel(
            provider: FakePuzzleProvider(),
            persistDifficulty: { persisted.append($0) }
        )

        viewModel.selectDifficulty(.hard)

        #expect(persisted == [.hard])
        #expect(viewModel.difficulty == .hard)
    }

    @Test("round trip: persisted value from one view model seeds the next (simulated relaunch)")
    func roundTripAcrossSimulatedRelaunch() {
        /// Stands in for the composition root's `LastSelectionStore` —
        /// backed by a plain in-memory box rather than real UserDefaults so
        /// this test stays a pure view-model seam test.
        final class Box {
            var value: Difficulty = .medium
        }
        let box = Box()

        let firstLaunch = PracticeHubViewModel(
            provider: FakePuzzleProvider(),
            initialDifficulty: box.value,
            persistDifficulty: { box.value = $0 }
        )
        firstLaunch.selectDifficulty(.easy)

        // A brand-new view model reading the SAME box simulates relaunch: no
        // in-memory state survives except what was persisted.
        let secondLaunch = PracticeHubViewModel(
            provider: FakePuzzleProvider(),
            initialDifficulty: box.value,
            persistDifficulty: { box.value = $0 }
        )

        #expect(secondLaunch.difficulty == .easy)
    }
}
