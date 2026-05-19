// HomeView — selection routes correctly + snapshot baselines.

import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import SudokuUI

@MainActor
@Suite("HomeView — selection + snapshots")
struct HomeViewTests {

    @Test func selectDailyAppendsDailyRoute() {
        let viewModel = HomeViewModel()
        viewModel.select(.daily)
        #expect(viewModel.path == [.daily])
    }

    @Test func selectPracticeAppendsPracticeRoute() {
        let viewModel = HomeViewModel()
        viewModel.select(.practice)
        #expect(viewModel.path == [.practice])
    }

    @Test func selectSettingsAppendsSettingsRoute() {
        let viewModel = HomeViewModel()
        viewModel.select(.settings)
        #expect(viewModel.path == [.settings])
    }

    @Test func snapshotIPhoneLight() {
        let view = HomeView(viewModel: HomeViewModel())
            .preferredColorScheme(.light)
        let host = hostingView(view, size: SnapshotLayouts.iPhone)
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "HomeView-iPhone-light")
        }
    }

    @Test func snapshotMacLight() {
        let view = HomeView(viewModel: HomeViewModel())
            .preferredColorScheme(.light)
        let host = hostingView(view, size: SnapshotLayouts.mac)
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "HomeView-Mac-light")
        }
    }
}
