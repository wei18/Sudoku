// TabRootsAccessibilityTests — #1021 Phase A.
//
// Mirrors `DailyPuzzleCardAccessibilityTests` (SudokuUITests): every new view
// exposes its combined VoiceOver label as a `static func` computed from plain
// values, tested directly here — no rendering, no `@Environment`, no
// snapshot dependency needed.

import Testing
@testable import GameShellUI

@Suite("GameShellUI — TabRoots accessibility labels")
struct TabRootsAccessibilityTests {

    @Test("DifficultyPips label reads 'Difficulty N of M'")
    func difficultyPipsLabel() {
        #expect(DifficultyPips.accessibilityLabel(level: 2, max: 3) == "Difficulty 2 of 3")
    }

    @Test("DailyCardView label combines title and statusText")
    func dailyCardViewLabel() {
        let label = DailyCardView.accessibilityLabel(title: "Easy", statusText: "Solved · 4:32")
        #expect(label == "Easy, Solved · 4:32")
    }

    @Test("PracticeDifficultyCardView label combines title and detail")
    func practiceDifficultyCardViewLabel() {
        let label = PracticeDifficultyCardView.accessibilityLabel(title: "Hard", detail: "~33 givens")
        #expect(label == "Hard, ~33 givens")
    }

    @Test("PersonalBestRow label includes best time when present")
    func personalBestRowLabelWithBestTime() {
        let label = PersonalBestRow.accessibilityLabel(title: "Medium", bestTimeText: "5:10", footnote: "12 solved · avg 5:10")
        #expect(label == "Medium, best 5:10, 12 solved · avg 5:10")
    }

    @Test("PersonalBestRow label says none when there's no best time yet")
    func personalBestRowLabelWithoutBestTime() {
        let label = PersonalBestRow.accessibilityLabel(title: "Hard", bestTimeText: nil, footnote: "0 solved")
        #expect(label == "Hard, best none, 0 solved")
    }

    @Test("StreakHeaderView label includes best when longest is present")
    func streakHeaderViewLabelWithLongest() {
        let label = StreakHeaderView.accessibilityLabel(current: 12, longest: 31)
        #expect(label == "12 day streak, best 31")
    }

    @Test("StreakHeaderView label omits best when longest is nil")
    func streakHeaderViewLabelWithoutLongest() {
        let label = StreakHeaderView.accessibilityLabel(current: 3, longest: nil)
        #expect(label == "3 day streak")
        #expect(!label.contains("best"))
    }

    @Test("StreakCalendarView day label includes today when applicable")
    func streakCalendarViewDayLabelToday() {
        let label = StreakCalendarView.dayAccessibilityLabel(day: 15, isCompleted: true, isToday: true)
        #expect(label == "15, completed, today")
    }

    @Test("StreakCalendarView day label omits today when not today")
    func streakCalendarViewDayLabelNotToday() {
        let label = StreakCalendarView.dayAccessibilityLabel(day: 3, isCompleted: false, isToday: false)
        #expect(label == "3, not completed")
    }

    @Test("StreakCalendarView summary reads 'Current N · Best M'")
    func streakCalendarViewSummary() {
        #expect(StreakCalendarView.summaryText(current: 5, longest: 12) == "Current 5 · Best 12")
    }
}
