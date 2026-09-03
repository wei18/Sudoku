// ProgressViewModel — PROGRESS screen data (#1021 Phase D; subsumes #773's
// `StatsViewModel` for the live tab-root wiring — see `Live+TabRoots.swift`).
//
// Reuses the exact two data reads the issue's motivation line names, zero
// CloudKit reads added:
//   - `fetchPersonalRecord(mode: .practice, difficulty:)` → the 3
//     `PersonalBestModel` rows. PRACTICE (not Daily) backs the "best time"
//     hero: Practice is replayed at will per difficulty, so "beat your best"
//     is a meaningful, ongoing signal there; Daily is one puzzle per day and
//     is already covered by the streak calendar below.
//   - `fetchCompletedDailyIdsByDay()` → the month streak calendar
//     (`StreakHistory`, mirrors `DailyHubViewModel+WeekWindow`'s single-fetch
//     contract — one call, not one per day).
//
// Fetch contract mirrors the daily hub / retired Stats screen's
// graceful-degrade posture: the screen renders IMMEDIATELY with an
// `isLoading` model (empty bests, no history), then fills once both fetches
// land. A `fetchPersonalRecord` failure degrades that ONE difficulty's row to
// empty (best time `nil`); a `fetchCompletedDailyIdsByDay` failure degrades
// `history` to `nil` (the screen falls back to an empty calendar + an
// "unavailable" footnote — see `ProgressScreen`). Both funnel through
// `errorReporter`, neither blocks the screen.

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
    /// `StatsViewModel`.
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
            do {
                let record = try await persistence.fetchPersonalRecord(mode: .practice, difficulty: difficulty)
                bests.append(Self.bestModel(difficulty: difficulty, record: record))
            } catch {
                await errorReporter.report(
                    UserFacingError.classify(error),
                    underlying: error,
                    source: "ProgressViewModel.fetchPersonalRecord"
                )
                bests.append(Self.emptyBest(difficulty: difficulty))
            }
        }
        return bests
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

    static func bestModel(difficulty: Difficulty, record: PersonalRecord) -> PersonalBestModel {
        let average = record.completedCount > 0 ? record.totalTimeSeconds / record.completedCount : nil
        return PersonalBestModel(
            id: difficulty.rawValue,
            title: title(for: difficulty),
            pipLevel: pipLevel(for: difficulty),
            bestTimeText: record.bestTimeSeconds.map(timeLabel),
            footnote: footnote(completedCount: record.completedCount, averageTimeSeconds: average)
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
