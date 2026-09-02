// StreakCalendarView — PROGRESS's month view (#1021 Phase A, design.md §3.3:
// "連續日曆: 月視圖(紀錄陳列,不是資料視覺化)"). A record display: filled
// circle + checkmark glyph for a completed day (color is not the sole
// channel — the glyph carries the signal too), an accent ring for today.

public import SwiftUI

public struct StreakCalendarView: View {
    @Environment(\.theme) private var theme
    @ScaledSpacing(.small) private var contentGap

    private let history: StreakHistory
    private let month: DayKey
    private let monthTitle: String
    private let calendar: Calendar

    private static let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private static let dayCellHeight: CGFloat = 28

    public init(history: StreakHistory, month: DayKey, monthTitle: String, calendar: Calendar = .current) {
        self.history = history
        self.month = month
        self.monthTitle = monthTitle
        self.calendar = calendar
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: contentGap) {
            header
            weekdayRow
            LazyVGrid(columns: Self.columns, spacing: contentGap) {
                ForEach(Array(history.monthCells(for: month, calendar: calendar).enumerated()), id: \.offset) { _, cell in
                    dayCell(cell)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text(monthTitle)
                .font(.headline)
                .foregroundStyle(theme.text.primary.resolved)
            Spacer()
            Text(Self.summaryText(current: history.current, longest: history.longest))
                .font(.subheadline)
                .foregroundStyle(theme.text.secondary.resolved)
        }
    }

    private var weekdayInitials: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let offset = (calendar.firstWeekday - 1 + symbols.count) % symbols.count
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var weekdayRow: some View {
        HStack {
            ForEach(Array(weekdayInitials.enumerated()), id: \.offset) { _, initial in
                Text(initial)
                    .font(.caption2)
                    .foregroundStyle(theme.text.tertiary.resolved)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func dayCell(_ cell: MonthCell) -> some View {
        if let day = cell.day {
            ZStack {
                Circle().fill(cell.isCompleted ? theme.accent.primary.resolved : Color.clear)
                Circle().strokeBorder(cell.isToday ? theme.accent.primary.resolved : Color.clear, lineWidth: 1.5)
                if cell.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.surface.primary.resolved)
                } else {
                    Text("\(day)")
                        .font(.caption)
                        .foregroundStyle(theme.text.primary.resolved)
                }
            }
            .frame(height: Self.dayCellHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.dayAccessibilityLabel(day: day, isCompleted: cell.isCompleted, isToday: cell.isToday))
        } else {
            Color.clear
                .frame(height: Self.dayCellHeight)
                .accessibilityHidden(true)
        }
    }

    public static func summaryText(current: Int, longest: Int) -> String {
        String(localized: "Current \(current) · Best \(longest)", bundle: .main)
    }

    public static func dayAccessibilityLabel(day: Int, isCompleted: Bool, isToday: Bool) -> String {
        let status = isCompleted
            ? String(localized: "completed", bundle: .main)
            : String(localized: "not completed", bundle: .main)
        guard isToday else {
            return String(localized: "\(day), \(status)", bundle: .main)
        }
        return String(localized: "\(day), \(status), today", bundle: .main)
    }
}
