// PersonalBestMath — shared merge math + formatters for the PROGRESS
// screen's personal-best rows (#1021 CR2 M6). Sudoku's `ProgressViewModel`
// and Minesweeper's `MinesweeperProgressViewModel` duplicated ~120 lines of
// this (bestModel merge / timeLabel / monthTitle) — hoisted here (zero-dep)
// so per-app view models keep only their own persistence reads + record→
// input mapping. `footnote`/`title`/`pipLevel` stay per-app: the wording
// ("solved" vs "cleared", localized separately) and difficulty enum differ
// per game, so there is nothing game-agnostic left to share there.

public import Foundation

/// The DAILY+PRACTICE merge for one difficulty's personal-best row: best =
/// the smaller (faster) of the two modes' best times (`nil` only when BOTH
/// are `nil` — a mode with zero completions never overrides a real best from
/// the other mode); `completedCount`/`averageTimeSeconds` = the two modes'
/// counts/totals summed. Mirrors the merge both apps' `bestModel` static
/// funcs used to inline separately.
public struct PersonalBestMerge: Sendable, Equatable {
    public let bestTimeSeconds: Int?
    public let completedCount: Int
    public let averageTimeSeconds: Int?

    public init(
        dailyBestTimeSeconds: Int?,
        dailyCompletedCount: Int,
        dailyTotalTimeSeconds: Int,
        practiceBestTimeSeconds: Int?,
        practiceCompletedCount: Int,
        practiceTotalTimeSeconds: Int
    ) {
        switch (dailyBestTimeSeconds, practiceBestTimeSeconds) {
        case let (daily?, practice?): bestTimeSeconds = min(daily, practice)
        case let (daily?, nil): bestTimeSeconds = daily
        case let (nil, practice?): bestTimeSeconds = practice
        case (nil, nil): bestTimeSeconds = nil
        }
        completedCount = dailyCompletedCount + practiceCompletedCount
        let totalTimeSeconds = dailyTotalTimeSeconds + practiceTotalTimeSeconds
        averageTimeSeconds = completedCount > 0 ? totalTimeSeconds / completedCount : nil
    }
}

/// `m:ss` display label — identical formatter both apps' PROGRESS view
/// models defined separately.
public enum PersonalBestFormatting {
    public static func timeLabel(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// PROGRESS calendar's `"MMMM y"` month header — identical in both apps'
/// `ProgressViewModel`s.
public enum StreakMonthFormatting {
    public static func monthTitle(for month: DayKey, calendar: Calendar) -> String {
        var components = DateComponents()
        components.year = month.year
        components.month = month.month
        components.day = 1
        components.hour = 12
        guard let date = calendar.date(from: components) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM y")
        return formatter.string(from: date)
    }
}
