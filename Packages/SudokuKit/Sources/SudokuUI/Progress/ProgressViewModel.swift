// ProgressViewModel — PROGRESS screen data (#1021 Phase D/E2; subsumes #773's
// retired Statistics screen view model for the live tab-root wiring — see
// `Live+TabRoots.swift`).
//
// Reuses the exact two data reads the issue's motivation line names, zero
// CloudKit reads added:
//   - `fetchPersonalRecord(mode:difficulty:)` for BOTH `.daily` and
//     `.practice` (6 reads total, same as the retired view model's own
//     daily-tiles+practice-tiles reads) → the 3 `PersonalBestModel` rows. A
//     "personal best per difficulty" must not silently drop daily records
//     (#1021 Phase E2 CR): best = the smaller of the two modes' best times
//     (nil only when BOTH are nil), completedCount = the two counts summed,
//     average = the two total-times summed over the two counts summed.
//   - `fetchCompletedDailyIdsByDay()` → the month streak calendar
//     (`StreakHistory`, mirrors `DailyHubViewModel+WeekWindow`'s single-fetch
//     contract — one call, not one per day).
//
// Fetch contract mirrors the daily hub / retired Stats screen's
// graceful-degrade posture: the screen renders IMMEDIATELY with an
// `isLoading` model (empty bests, no history), then fills once every fetch
// lands. A `fetchPersonalRecord` failure degrades JUST that (mode,
// difficulty) pair to `PersonalRecord.empty(...)` before merging — the
// OTHER mode's real record for that difficulty still counts, so one mode's
// CK hiccup never blanks a row that has real data in the other mode. A
// `fetchCompletedDailyIdsByDay` failure degrades `history` to `nil` (the
// screen falls back to an empty calendar + an "unavailable" footnote — see
// `ProgressScreen`). Every failure funnels through `errorReporter`; nothing
// blocks the screen.

public import Foundation
public import GameShellUI
public import Persistence
public import SudokuEngine
public import Telemetry

@MainActor
@Observable
public final class ProgressViewModel {
    public private(set) var model: ProgressModel

    private let persistence: any PersistenceProtocol
    private let errorReporter: any ErrorReporter
    /// Optional so previews / snapshot fixtures construct without a
    /// Telemetry actor. `nil` → no screen-viewed event.
    private let telemetry: Telemetry?
    private let calendar: Calendar
    private let now: () -> Date
    /// Idempotency latch for `.task` — same pattern as the retired
    /// Statistics screen's view model.
    private var hasBootstrapped = false

    public init(
        persistence: any PersistenceProtocol,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        telemetry: Telemetry? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.errorReporter = errorReporter
        self.telemetry = telemetry
        self.calendar = calendar
        self.now = now
        let today = DayKey(now(), calendar: calendar)
        self.model = ProgressModel(
            bests: Difficulty.allCases.map(Self.emptyBest),
            history: nil,
            month: today,
            monthTitle: Self.monthTitle(for: today, calendar: calendar),
            isLoading: true
        )
    }

    public func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        await telemetry?.observe(.statsViewed)
        async let bestsResult = fetchBests()
        async let historyResult = fetchHistory()
        let bests = await bestsResult
        let history = await historyResult
        model = ProgressModel(
            bests: bests,
            history: history,
            month: model.month,
            monthTitle: model.monthTitle,
            isLoading: false
        )
    }

    private func fetchBests() async -> [PersonalBestModel] {
        var bests: [PersonalBestModel] = []
        for difficulty in Difficulty.allCases {
            async let dailyTask = fetchRecord(mode: .daily, difficulty: difficulty)
            async let practiceTask = fetchRecord(mode: .practice, difficulty: difficulty)
            let daily = await dailyTask
            let practice = await practiceTask
            bests.append(Self.bestModel(difficulty: difficulty, daily: daily, practice: practice))
        }
        return bests
    }

    /// One (mode, difficulty) read. A failure reports through
    /// `errorReporter` and degrades to `.empty(...)` for JUST this mode —
    /// the caller merges it with the other mode's (possibly real) record,
    /// so a single mode's CK hiccup never wipes out the other mode's data.
    private func fetchRecord(mode: Mode, difficulty: Difficulty) async -> PersonalRecord {
        do {
            return try await persistence.fetchPersonalRecord(mode: mode, difficulty: difficulty)
        } catch {
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "ProgressViewModel.fetchPersonalRecord"
            )
            return .empty(mode: mode, difficulty: difficulty, at: now())
        }
    }

    private func fetchHistory() async -> StreakHistory? {
        do {
            let completedByDay = try await persistence.fetchCompletedDailyIdsByDay()
            let completedDays = Set(completedByDay.keys.compactMap(DayKey.key))
            return StreakHistory(completedDays: completedDays, today: DayKey(now(), calendar: calendar))
        } catch {
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "ProgressViewModel.fetchCompletedDailyIdsByDay"
            )
            return nil
        }
    }

    // MARK: - Record → row mapping

    /// Merges the daily and practice records for one difficulty into a
    /// single row: best = the smaller of the two best times (nil only when
    /// BOTH are nil — a mode with no completions never overrides a real
    /// best from the other mode), completedCount/average = the two modes'
    /// counts/totals summed.
    static func bestModel(difficulty: Difficulty, daily: PersonalRecord, practice: PersonalRecord) -> PersonalBestModel {
        let combinedBest: Int?
        switch (daily.bestTimeSeconds, practice.bestTimeSeconds) {
        case let (dailyBest?, practiceBest?): combinedBest = min(dailyBest, practiceBest)
        case let (dailyBest?, nil): combinedBest = dailyBest
        case let (nil, practiceBest?): combinedBest = practiceBest
        case (nil, nil): combinedBest = nil
        }
        let completedCount = daily.completedCount + practice.completedCount
        let totalTimeSeconds = daily.totalTimeSeconds + practice.totalTimeSeconds
        let average = completedCount > 0 ? totalTimeSeconds / completedCount : nil
        return PersonalBestModel(
            id: difficulty.rawValue,
            title: title(for: difficulty),
            pipLevel: pipLevel(for: difficulty),
            bestTimeText: combinedBest.map(timeLabel),
            footnote: footnote(completedCount: completedCount, averageTimeSeconds: average)
        )
    }

    static func emptyBest(difficulty: Difficulty) -> PersonalBestModel {
        PersonalBestModel(
            id: difficulty.rawValue,
            title: title(for: difficulty),
            pipLevel: pipLevel(for: difficulty),
            bestTimeText: nil,
            footnote: footnote(completedCount: 0, averageTimeSeconds: nil)
        )
    }

    /// `"%lld solved"` alone, or `"%lld solved · avg %@"` when an average
    /// exists — omitted (not "avg —") when there is nothing to average yet.
    static func footnote(completedCount: Int, averageTimeSeconds: Int?) -> String {
        guard let averageTimeSeconds else {
            return String(localized: "\(completedCount) solved", bundle: .main)
        }
        return String(localized: "\(completedCount) solved · avg \(timeLabel(averageTimeSeconds))", bundle: .main)
    }

    /// `m:ss` display label — same format the retired `StatsTileView` used.
    static func timeLabel(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func title(for difficulty: Difficulty) -> String {
        let key = difficulty.rawValue.capitalized
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    private static func pipLevel(for difficulty: Difficulty) -> Int {
        switch difficulty {
        case .easy: return 1
        case .medium: return 2
        case .hard: return 3
        }
    }

    static func monthTitle(for month: DayKey, calendar: Calendar) -> String {
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
