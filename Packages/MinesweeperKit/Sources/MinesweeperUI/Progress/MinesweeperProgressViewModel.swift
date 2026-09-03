// MinesweeperProgressViewModel — PROGRESS screen data (#1021 Phase D; mirrors
// Sudoku's `ProgressViewModel`, subsuming #773's `MinesweeperStatsViewModel`
// for the live tab-root wiring — see `Live+TabRoots.swift`).
//
// Reuses the exact two data reads the issue's motivation line names, zero
// CloudKit reads added:
//   - `store.fetch(modeRaw: "practice", difficulty:)` → the 3
//     `PersonalBestModel` rows. PRACTICE (not Daily) backs the "best time"
//     hero — same rationale as Sudoku's `ProgressViewModel`: Daily is one
//     board per day and is already covered by the streak calendar below.
//   - `completionSource.fetchCompletedDailyIdsByDay()` → the month streak
//     calendar (`StreakHistory`), one read (mirrors
//     `MinesweeperDailyHubViewModel+Overlay`'s single-fetch contract).
//
// Fetch contract mirrors the daily hub / retired Stats screen's
// graceful-degrade posture: renders immediately with an `isLoading` model,
// fills once both fetches land. Failures funnel through `errorReporter` and
// degrade to an empty row / `history == nil` — never a blocking error state.

public import Foundation
public import GameShellUI
public import MinesweeperEngine
public import MinesweeperPersistence
public import Telemetry

@MainActor
@Observable
public final class MinesweeperProgressViewModel {
    public private(set) var model: ProgressModel

    private let store: MinesweeperPersonalRecordStore?
    private let completionSource: any MinesweeperDailyOverlayReading
    private let errorReporter: (any ErrorReporter)?
    /// Optional so previews / snapshot fixtures construct without a
    /// Telemetry actor. `nil` → no screen-viewed event.
    private let telemetry: Telemetry?
    private let calendar: Calendar
    private let now: () -> Date
    /// Idempotency latch for `.task` — same pattern as the hubs.
    private var hasBootstrapped = false

    public init(
        store: MinesweeperPersonalRecordStore?,
        completionSource: any MinesweeperDailyOverlayReading,
        errorReporter: (any ErrorReporter)? = nil,
        telemetry: Telemetry? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.completionSource = completionSource
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
        guard let store else { return Difficulty.allCases.map(Self.emptyBest) }
        var bests: [PersonalBestModel] = []
        for difficulty in Difficulty.allCases {
            do {
                let record = try await store.fetch(modeRaw: GameMode.practice.rawValue, difficulty: difficulty)
                bests.append(Self.bestModel(difficulty: difficulty, record: record))
            } catch {
                await errorReporter?.report(
                    UserFacingError.classify(error),
                    underlying: error,
                    source: "MinesweeperProgressViewModel.fetchPersonalRecord"
                )
                bests.append(Self.emptyBest(difficulty: difficulty))
            }
        }
        return bests
    }

    private func fetchHistory() async -> StreakHistory? {
        do {
            let completedByDay = try await completionSource.fetchCompletedDailyIdsByDay()
            let completedDays = Set(completedByDay.keys.compactMap(DayKey.key))
            return StreakHistory(completedDays: completedDays, today: DayKey(now(), calendar: calendar))
        } catch {
            await errorReporter?.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "MinesweeperProgressViewModel.fetchCompletedDailyIdsByDay"
            )
            return nil
        }
    }

    // MARK: - Record → row mapping

    static func bestModel(difficulty: Difficulty, record: MinesweeperPersonalRecord) -> PersonalBestModel {
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

    /// `"%lld cleared"` alone, or `"%lld cleared · avg %@"` when an average
    /// exists — "cleared" (not "solved") is Minesweeper's completion verb.
    static func footnote(completedCount: Int, averageTimeSeconds: Int?) -> String {
        guard let averageTimeSeconds else {
            return String(localized: "\(completedCount) cleared", bundle: .main)
        }
        return String(localized: "\(completedCount) cleared · avg \(timeLabel(averageTimeSeconds))", bundle: .main)
    }

    /// `m:ss` display label — same format the retired `MinesweeperStatsView` used.
    static func timeLabel(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func title(for difficulty: Difficulty) -> String {
        let key = nameKey(difficulty)
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    private static func nameKey(_ difficulty: Difficulty) -> String {
        switch difficulty {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .expert: return "Expert"
        }
    }

    private static func pipLevel(for difficulty: Difficulty) -> Int {
        switch difficulty {
        case .beginner: return 1
        case .intermediate: return 2
        case .expert: return 3
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
