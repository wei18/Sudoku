// SettingsViewTests — behavior only.

import Foundation
import Testing
@testable import SudokuUI

import Persistence
import SudokuEngine
import TelemetryTesting

@MainActor
@Suite("SettingsView — behavior")
struct SettingsViewTests {

    @Test func generatorVersionRow_displaysV1() {
        let viewModel = SettingsViewModel(
            generatorVersion: .v1,
            persistence: FakePersistence()
        )
        // Asserts the value passed into the SettingsView label matches the
        // current GeneratorVersion.v1.rawValue. The View renders this via
        // `LabeledContent("Generator", value: viewModel.generatorVersion.rawValue)`.
        #expect(viewModel.generatorVersion.rawValue == "v1")
    }

    @Test func clearCache_deletesResumeCandidateAndSetsConfirmation() async {
        let candidate = SavedGameSummary(
            recordName: "saved-easy",
            puzzleId: "2026-05-19-easy",
            mode: .daily,
            difficulty: .easy,
            lastModifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            elapsedSeconds: 120,
            status: "inProgress",
            generatorVersion: 1
        )
        let fake = FakePersistence()
        await fake.setResumeCandidate(candidate)
        let viewModel = SettingsViewModel(persistence: fake)
        await viewModel.bootstrap()
        #expect(viewModel.resumeCandidate?.recordName == "saved-easy")

        await viewModel.clearCache()

        let ops = await fake.operations
        #expect(ops.contains(.deleteAbandoned(recordName: "saved-easy")))
        #expect(viewModel.resumeCandidate == nil)
        #expect(viewModel.clearCacheConfirmation == "Cache cleared")
    }

    @Test func clearCache_withNoCandidate_stillSetsConfirmation() async {
        let viewModel = SettingsViewModel(persistence: FakePersistence())
        await viewModel.bootstrap()
        await viewModel.clearCache()
        #expect(viewModel.clearCacheConfirmation == "Cache cleared")
    }
}
