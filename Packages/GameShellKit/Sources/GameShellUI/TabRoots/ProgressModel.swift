// ProgressModel — PROGRESS tab's composed state (#1021 Phase D, design.md
// §3.3: personal bests + a month streak calendar + the two Game Center
// entry points). A pure value the per-app `ProgressViewModel` produces from
// `PersonalRecord` reads + `fetchCompletedDailyIdsByDay()`; `ProgressScreen`
// (GameAppKit) renders it. Lives here (not GameAppKit) because it is a pure
// Sendable/Equatable value with no Persistence/GameCenter/Telemetry
// dependency of its own — same rationale as `StreakHeaderModel`/`DayKey`.

public struct ProgressModel: Sendable, Equatable {
    public let bests: [PersonalBestModel]
    /// `nil` on a `fetchCompletedDailyIdsByDay()` failure — the screen falls
    /// back to an empty calendar (no marks) + an "unavailable" footnote
    /// rather than going blank.
    public let history: StreakHistory?
    public let month: DayKey
    public let monthTitle: String
    /// Seeds `true` so the screen renders redacted-placeholder content
    /// immediately, before the async fetches land.
    public let isLoading: Bool

    public init(
        bests: [PersonalBestModel],
        history: StreakHistory?,
        month: DayKey,
        monthTitle: String,
        isLoading: Bool
    ) {
        self.bests = bests
        self.history = history
        self.month = month
        self.monthTitle = monthTitle
        self.isLoading = isLoading
    }
}
