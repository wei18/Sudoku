// StreakCalendarView — PROGRESS's month view (#1021 Phase A, design.md §3.3:
// "連續日曆: 月視圖(紀錄陳列,不是資料視覺化)"). A record display: filled
// circle + checkmark glyph for a completed day (color is not the sole
// channel — the glyph carries the signal too), an accent ring for today.

public import SwiftUI

public struct StreakCalendarView: View {
    @Environment(\.theme) private var theme
    @ScaledSpacing(.small) private var contentGap

    /// #1021 CR2 M2: `nil` covers BOTH "still loading" (`isLoading == true`)
    /// AND "fetch failed, genuinely unavailable" (`isLoading == false`) — the
    /// caller (`ProgressScreen`) no longer substitutes a fake all-zero
    /// `StreakHistory` before handing this down (that substitution is what
    /// produced the "Current 0 · Best 0" VoiceOver lie on an unfetched or
    /// failed month). This view owns its own empty-grid fallback for LAYOUT
    /// only (`effectiveHistory`) and keeps the two `nil` causes distinguished
    /// in the header/footnote text via `isLoading`.
    private let history: StreakHistory?
    private let month: DayKey
    private let monthTitle: String
    private let calendar: Calendar
    private let isLoading: Bool

    private static let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private static let dayCellHeight: CGFloat = 28

    public init(
        history: StreakHistory?,
        month: DayKey,
        monthTitle: String,
        calendar: Calendar = .current,
        isLoading: Bool = false
    ) {
        self.history = history
        self.month = month
        self.monthTitle = monthTitle
        self.calendar = calendar
        self.isLoading = isLoading
    }

    /// Layout-only fallback — an empty grid (zero marks) when there is no
    /// real history yet/ever. Never read for the header/footnote TEXT, which
    /// branch on `history == nil` / `isLoading` directly so they never quote
    /// this placeholder's `current`/`longest` as real numbers.
    private var effectiveHistory: StreakHistory {
        history ?? Self.emptyHistory(today: month)
    }

    private static func emptyHistory(today: DayKey) -> StreakHistory {
        StreakHistory(completedDays: [], today: today)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: contentGap) {
            header
            weekdayRow
            LazyVGrid(columns: Self.columns, spacing: contentGap) {
                ForEach(Array(effectiveHistory.monthCells(for: month, calendar: calendar).enumerated()), id: \.offset) { _, cell in
                    dayCell(cell)
                }
            }
            // #1021 CR2 M2: cells read out real per-day facts ("12,
            // completed" / "12, not completed") — while loading there is no
            // real data behind them yet, so the whole grid is hidden from
            // VoiceOver rather than reading placeholder "not completed" for
            // every day as if it were known. (A genuinely UNAVAILABLE,
            // settled fetch failure leaves the grid visible/accessible: an
            // empty grid there is a true statement — no completions are
            // KNOWN — not a lie.)
            .accessibilityHidden(isLoading)
            if let statusFootnote {
                Text(statusFootnote)
                    .font(.footnote)
                    .foregroundStyle(theme.text.tertiary.resolved)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(monthTitle)
                .font(.headline)
                .foregroundStyle(theme.text.primary.resolved)
            Spacer()
            Text(headerTrailingText)
                .font(.subheadline)
                .foregroundStyle(theme.text.secondary.resolved)
        }
    }

    private var headerTrailingText: String {
        Self.headerTrailingText(isLoading: isLoading, history: history)
    }

    /// The footnote line below the grid — `nil` (nothing rendered) once real
    /// history has landed.
    private var statusFootnote: String? {
        Self.statusFootnote(isLoading: isLoading, history: history)
    }

    /// #1021 CR2 M2: never quotes a placeholder `current`/`longest` (both 0)
    /// as fact — loading and unavailable each get their own non-numeric
    /// wording instead of "Current 0 · Best 0". A plain `static func` over
    /// values (mirrors `summaryText`/`dayAccessibilityLabel` below) so
    /// `TabRootsAccessibilityTests` can pin it without rendering.
    public static func headerTrailingText(isLoading: Bool, history: StreakHistory?) -> String {
        if isLoading {
            return loadingText
        }
        guard let history else {
            return unavailableText
        }
        return summaryText(current: history.current, longest: history.longest)
    }

    /// Reuses the exact same wording as `headerTrailingText` for the same
    /// two non-ready states (no new keys beyond `loadingText`, which the
    /// header already needs) — `nil` once real history has landed.
    public static func statusFootnote(isLoading: Bool, history: StreakHistory?) -> String? {
        if isLoading { return loadingText }
        if history == nil { return unavailableText }
        return nil
    }

    public static let loadingText = String(localized: "Streak history loading", bundle: .main)
    public static let unavailableText = String(localized: "Streak history unavailable", bundle: .main)

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
