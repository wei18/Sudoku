// Snapshots for view-level previews. Covers SnapshotMatrix §1 + §2.

import XCTest
import SwiftUI
import SnapshotTesting
@testable import DesignPreviewKit

@MainActor
final class ViewSnapshotTests: XCTestCase {

    private func assertViewSnapshot(
        _ view: some View,
        size: CGSize,
        colorScheme: ColorScheme = .light,
        locale: Locale = Locale(identifier: "en"),
        dynamicTypeSize: DynamicTypeSize = .large,
        named: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let host = hostingView(
            view,
            size: size,
            colorScheme: colorScheme,
            locale: locale,
            dynamicTypeSize: dynamicTypeSize
        )
        if let failure = verifySnapshot(
            of: host,
            as: .image(precision: snapshotPrecision, perceptualPrecision: snapshotPerceptualPrecision),
            named: named,
            snapshotDirectory: snapshotDirectory(forTestFile: file),
            file: file,
            testName: "ViewSnapshots",
            line: line
        ) {
            XCTFail(failure, file: file, line: line)
        }
    }

    // MARK: - §1 BoardView (12)

    func test_boardView_iphone_light_en_empty() {
        assertViewSnapshot(
            BoardView_Designs(board: BoardView_Designs.demoEmpty),
            size: DeviceSize.iPhone, named: "boardView_iphone_light_en_empty"
        )
    }
    func test_boardView_iphone_light_en_inProgressErrors() {
        assertViewSnapshot(
            BoardView_Designs(board: BoardView_Designs.demoInProgressWithErrors),
            size: DeviceSize.iPhone, named: "boardView_iphone_light_en_inProgressErrors"
        )
    }
    func test_boardView_iphone_light_en_aboutToComplete() {
        assertViewSnapshot(
            BoardView_Designs(board: BoardView_Designs.demoAboutToComplete),
            size: DeviceSize.iPhone, named: "boardView_iphone_light_en_aboutToComplete"
        )
    }
    func test_boardView_iphone_dark_ja_empty() {
        assertViewSnapshot(
            BoardView_Designs(board: BoardView_Designs.demoEmpty),
            size: DeviceSize.iPhone, colorScheme: .dark, locale: Locale(identifier: "ja"),
            named: "boardView_iphone_dark_ja_empty"
        )
    }
    func test_boardView_iphone_dark_ja_inProgressErrors() {
        assertViewSnapshot(
            BoardView_Designs(board: BoardView_Designs.demoInProgressWithErrors),
            size: DeviceSize.iPhone, colorScheme: .dark, locale: Locale(identifier: "ja"),
            named: "boardView_iphone_dark_ja_inProgressErrors"
        )
    }
    func test_boardView_iphone_dark_ja_aboutToComplete() {
        assertViewSnapshot(
            BoardView_Designs(board: BoardView_Designs.demoAboutToComplete),
            size: DeviceSize.iPhone, colorScheme: .dark, locale: Locale(identifier: "ja"),
            named: "boardView_iphone_dark_ja_aboutToComplete"
        )
    }
    func test_boardView_iphone_light_ko_empty() {
        assertViewSnapshot(
            BoardView_Designs(board: BoardView_Designs.demoEmpty),
            size: DeviceSize.iPhone, locale: Locale(identifier: "ko"),
            named: "boardView_iphone_light_ko_empty"
        )
    }
    func test_boardView_iphone_light_en_paused() {
        assertViewSnapshot(
            BoardView_Designs(board: BoardView_Designs.demoInProgressWithErrors, isPaused: true),
            size: DeviceSize.iPhone, named: "boardView_iphone_light_en_paused"
        )
    }
    func test_boardView_mac_light_en_empty() {
        assertViewSnapshot(
            BoardView_Designs(board: BoardView_Designs.demoEmpty),
            size: DeviceSize.mac, named: "boardView_mac_light_en_empty"
        )
    }
    func test_boardView_mac_light_en_inProgressErrors() {
        assertViewSnapshot(
            BoardView_Designs(board: BoardView_Designs.demoInProgressWithErrors),
            size: DeviceSize.mac, named: "boardView_mac_light_en_inProgressErrors"
        )
    }
    func test_boardView_mac_dark_en_aboutToComplete() {
        assertViewSnapshot(
            BoardView_Designs(board: BoardView_Designs.demoAboutToComplete),
            size: DeviceSize.mac, colorScheme: .dark,
            named: "boardView_mac_dark_en_aboutToComplete"
        )
    }
    func test_boardView_mac_dark_ja_inProgressErrors() {
        assertViewSnapshot(
            BoardView_Designs(board: BoardView_Designs.demoInProgressWithErrors),
            size: DeviceSize.mac, colorScheme: .dark, locale: Locale(identifier: "ja"),
            named: "boardView_mac_dark_ja_inProgressErrors"
        )
    }

    // MARK: - §1 DailyHubView (3)

    func test_dailyHub_iphone_light_en_nonePlayed() {
        assertViewSnapshot(
            NavigationStack { DailyHubView_Designs(state: .loaded(DailyHubView_Designs.demoNoneDone)) },
            size: DeviceSize.iPhone, named: "dailyHub_iphone_light_en_nonePlayed"
        )
    }
    func test_dailyHub_iphone_light_en_easyDone() {
        assertViewSnapshot(
            NavigationStack { DailyHubView_Designs(state: .loaded(DailyHubView_Designs.demoEasyDone)) },
            size: DeviceSize.iPhone, named: "dailyHub_iphone_light_en_easyDone"
        )
    }
    func test_dailyHub_iphone_light_en_allDone() {
        assertViewSnapshot(
            NavigationStack { DailyHubView_Designs(state: .loaded(DailyHubView_Designs.demoAllDone)) },
            size: DeviceSize.iPhone, named: "dailyHub_iphone_light_en_allDone"
        )
    }

    // MARK: - §1 PracticeHubView (3)

    func test_practiceHub_iphone_light_en_idle() {
        assertViewSnapshot(
            NavigationStack { PracticeHubView_Designs(state: .idle) },
            size: DeviceSize.iPhone, named: "practiceHub_iphone_light_en_idle"
        )
    }
    func test_practiceHub_iphone_light_en_drawingShimmer() {
        assertViewSnapshot(
            NavigationStack { PracticeHubView_Designs(state: .drawing) },
            size: DeviceSize.iPhone, named: "practiceHub_iphone_light_en_drawingShimmer"
        )
    }
    func test_practiceHub_iphone_light_en_drawn() {
        assertViewSnapshot(
            NavigationStack { PracticeHubView_Designs(state: .drawn(puzzleId: "24c8")) },
            size: DeviceSize.iPhone, named: "practiceHub_iphone_light_en_drawn"
        )
    }

    // MARK: - §1 CompletionView (3)

    func test_completion_iphone_light_zhTW_authenticated() {
        assertViewSnapshot(
            CompletionView_Designs(state: .authenticated(top: CompletionView_Designs.demoTop, around: CompletionView_Designs.demoAround)),
            size: DeviceSize.iPhone, locale: Locale(identifier: "zh-Hant"),
            named: "completion_iphone_light_zhTW_authenticated"
        )
    }
    func test_completion_iphone_light_en_unauthenticated() {
        assertViewSnapshot(
            CompletionView_Designs(state: .unauthenticated),
            size: DeviceSize.iPhone, named: "completion_iphone_light_en_unauthenticated"
        )
    }
    func test_completion_iphone_light_en_fetchFailed() {
        assertViewSnapshot(
            CompletionView_Designs(state: .fetchFailed),
            size: DeviceSize.iPhone, named: "completion_iphone_light_en_fetchFailed"
        )
    }

    // MARK: - §2 RootView (3)

    func test_root_iphone_light_en_withResume() {
        assertViewSnapshot(
            RootView_Designs(resume: .init(difficultyLabel: "Easy", elapsed: "3:21")),
            size: DeviceSize.iPhone, named: "root_iphone_light_en_withResume"
        )
    }
    func test_root_iphone_light_en_noResume() {
        assertViewSnapshot(
            RootView_Designs(resume: nil),
            size: DeviceSize.iPhone, named: "root_iphone_light_en_noResume"
        )
    }
    func test_root_mac_dark_ja_withResume() {
        assertViewSnapshot(
            RootView_Designs(resume: .init(difficultyLabel: "Easy", elapsed: "3:21")),
            size: DeviceSize.mac, colorScheme: .dark, locale: Locale(identifier: "ja"),
            named: "root_mac_dark_ja_withResume"
        )
    }

    // MARK: - §2 HomeView (2)

    func test_home_iphone_light_en() {
        assertViewSnapshot(
            NavigationStack { HomeView_Designs() },
            size: DeviceSize.iPhone, named: "home_iphone_light_en"
        )
    }
    func test_home_mac_dark_ja() {
        assertViewSnapshot(
            NavigationStack { HomeView_Designs() },
            size: DeviceSize.mac, colorScheme: .dark, locale: Locale(identifier: "ja"),
            named: "home_mac_dark_ja"
        )
    }

    // MARK: - §2 LeaderboardView (4)

    func test_leaderboard_iphone_light_en_loaded() {
        assertViewSnapshot(
            NavigationStack { LeaderboardView_Designs(state: .loaded(LeaderboardView_Designs.demoEntries)) },
            size: DeviceSize.iPhone, named: "leaderboard_iphone_light_en_loaded"
        )
    }
    func test_leaderboard_iphone_light_ja_unauthenticated() {
        assertViewSnapshot(
            NavigationStack { LeaderboardView_Designs(state: .unauthenticated) },
            size: DeviceSize.iPhone, locale: Locale(identifier: "ja"),
            named: "leaderboard_iphone_light_ja_unauthenticated"
        )
    }
    func test_leaderboard_iphone_light_en_error() {
        assertViewSnapshot(
            NavigationStack { LeaderboardView_Designs(state: .error) },
            size: DeviceSize.iPhone, named: "leaderboard_iphone_light_en_error"
        )
    }
    func test_leaderboard_iphone_light_en_AX3_loaded() {
        assertViewSnapshot(
            NavigationStack { LeaderboardView_Designs(state: .loaded(LeaderboardView_Designs.demoEntries)) },
            size: DeviceSize.iPhone, dynamicTypeSize: .accessibility3,
            named: "leaderboard_iphone_light_en_AX3_loaded"
        )
    }

    // MARK: - §2 SettingsView (2)

    func test_settings_iphone_light_en() {
        assertViewSnapshot(
            NavigationStack { SettingsView_Designs() },
            size: DeviceSize.iPhone, named: "settings_iphone_light_en"
        )
    }
    func test_settings_mac_dark_ja() {
        assertViewSnapshot(
            NavigationStack { SettingsView_Designs() },
            size: DeviceSize.mac, colorScheme: .dark, locale: Locale(identifier: "ja"),
            named: "settings_mac_dark_ja"
        )
    }

    // MARK: - §2 CompletionView extras (2)

    func test_completion_mac_dark_ja_fetchFailed() {
        assertViewSnapshot(
            CompletionView_Designs(state: .fetchFailed),
            size: DeviceSize.mac, colorScheme: .dark, locale: Locale(identifier: "ja"),
            named: "completion_mac_dark_ja_fetchFailed"
        )
    }
    func test_completion_iphone_light_en_practiceMode() {
        assertViewSnapshot(
            CompletionView_Designs(state: .practiceMode),
            size: DeviceSize.iPhone, named: "completion_iphone_light_en_practiceMode"
        )
    }
}
