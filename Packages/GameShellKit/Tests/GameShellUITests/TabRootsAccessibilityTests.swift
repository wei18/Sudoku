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

    // #1021 Phase F1: a degraded/loading streak header must never read out
    // "0 day streak" — that claims a real (if minimal) streak the fetch
    // never confirmed.
    @Test("StreakHeaderView label reads 'Streak unavailable' when skeleton")
    func streakHeaderViewLabelSkeleton() {
        let label = StreakHeaderView.accessibilityLabel(current: 0, longest: nil, isSkeleton: true)
        #expect(label == "Streak unavailable")
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

    // #1021 CR2 M2: loading must never let VoiceOver read a redacted
    // placeholder ("Easy, best none, 0 solved") as fact.

    @Test("PersonalBestRow loading label reads '<title>, loading', not the placeholder zeros")
    func personalBestRowLoadingLabel() {
        let label = PersonalBestRow.loadingAccessibilityLabel(title: "Easy")
        #expect(label == "Easy, loading")
    }

    @Test("StreakCalendarView header reads 'Streak history loading' while loading, not 'Current 0 · Best 0'")
    func streakCalendarViewHeaderLoading() {
        let text = StreakCalendarView.headerTrailingText(isLoading: true, history: nil)
        #expect(text == "Streak history loading")
    }

    @Test("StreakCalendarView header reads the unavailable footnote text on a settled fetch failure")
    func streakCalendarViewHeaderUnavailable() {
        let text = StreakCalendarView.headerTrailingText(isLoading: false, history: nil)
        #expect(text == "Streak history unavailable")
    }

    @Test("StreakCalendarView header reads the real summary once history has landed")
    func streakCalendarViewHeaderReady() {
        let history = StreakHistory(completedDays: [], today: DayKey(year: 2025, month: 8, day: 30))
        let text = StreakCalendarView.headerTrailingText(isLoading: false, history: history)
        #expect(text == "Current 0 · Best 0")
    }

    @Test("StreakCalendarView footnote renders while loading too, not only on unavailable")
    func streakCalendarViewFootnoteLoading() {
        #expect(StreakCalendarView.statusFootnote(isLoading: true, history: nil) == "Streak history loading")
        #expect(StreakCalendarView.statusFootnote(isLoading: false, history: nil) == "Streak history unavailable")
        let history = StreakHistory(completedDays: [], today: DayKey(year: 2025, month: 8, day: 30))
        #expect(StreakCalendarView.statusFootnote(isLoading: false, history: history) == nil)
    }
}
