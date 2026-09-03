// PersonalBestRowTests — direct snapshot coverage for GameShellKit's
// `PersonalBestRow` and `StreakCalendarView` (#1021 Phase D snapshot-coverage
// note, mirrors `TabRootsComponentSnapshotTests`'s Phase B rationale:
// GameShellKit carries no SnapshotTesting dependency by design, so the FIRST
// phase to actually consume a shared component adds its direct snapshot
// here, in addition to the composed-screen snapshot in
// `ProgressScreenTests`).

#if canImport(AppKit)
import Foundation
import GameShellUI
import SnapshotTesting
import SwiftUI
import Testing
@testable import SudokuUI

@MainActor
@Suite("PersonalBestRow / StreakCalendarView — direct snapshots (#1021 Phase D)")
struct PersonalBestRowTests {

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func personalBestRow_populated() {
        let model = PersonalBestModel(
            id: "hard", title: "Hard", pipLevel: 3,
            bestTimeText: "12:34", footnote: "27 solved · avg 15:02"
        )
        let host = hostingView(
            PersonalBestRow(model: model).frame(width: 380),
            size: CGSize(width: 380, height: 90),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "PersonalBestRow_populated")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func personalBestRow_neverCompleted() {
        let model = PersonalBestModel(
            id: "hard", title: "Hard", pipLevel: 3,
            bestTimeText: nil, footnote: "0 solved"
        )
        let host = hostingView(
            PersonalBestRow(model: model).frame(width: 380),
            size: CGSize(width: 380, height: 90),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "PersonalBestRow_neverCompleted")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func streakCalendarView_withMarks() {
        let history = StreakHistory(
            completedDays: [
                DayKey(year: 2025, month: 8, day: 28),
                DayKey(year: 2025, month: 8, day: 29),
                DayKey(year: 2025, month: 8, day: 30)
            ],
            today: DayKey(year: 2025, month: 8, day: 30)
        )
        let host = hostingView(
            StreakCalendarView(history: history, month: DayKey(year: 2025, month: 8, day: 30), monthTitle: "August 2025")
                .frame(width: 380),
            size: CGSize(width: 380, height: 320),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "StreakCalendarView_withMarks")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func streakCalendarView_empty() {
        let history = StreakHistory(completedDays: [], today: DayKey(year: 2025, month: 8, day: 30))
        let host = hostingView(
            StreakCalendarView(history: history, month: DayKey(year: 2025, month: 8, day: 30), monthTitle: "August 2025")
                .frame(width: 380),
            size: CGSize(width: 380, height: 320),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "StreakCalendarView_empty")
        }
    }
}
#endif
