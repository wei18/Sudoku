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

    #if canImport(AppKit)
    @Test func snapshotIPhoneLight() {
        let host = hostingView(
            HomeView(viewModel: HomeViewModel()),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "HomeView-iPhone-light")
        }
    }

    @Test func snapshotMacLight() {
        let host = hostingView(
            HomeView(viewModel: HomeViewModel()),
            size: SnapshotLayouts.mac,
            colorScheme: .light,
            sizeClass: .regular
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "HomeView-Mac-light")
        }
    }
    #endif
}
