// StatsViewModel — Statistics screen data (#773, docs/v2/stats-screen-proposal.md).
//
// Reads ONLY fields that exist on `PersonalRecord` today (zero schema
// changes): `completedCount`, `bestTimeSeconds` (nilable), and
// `totalTimeSeconds` → average computed client-side as `total / count`.
//
// Fetch contract mirrors the daily hub's graceful-degrade posture
// (§How.6.1 p1): the screen renders IMMEDIATELY with empty tiles (zero
// completions, no times), then fills tile-by-tile as the async CloudKit
// reads land. Any fetch failure (offline / iCloud signed-out — CK is
// signed-out on dev sims) is funneled through `errorReporter` and degrades
// to the empty tile — the screen never blocks and never surfaces an error
// state of its own (a zero readout IS the truthful empty state here).
//
// Owner adjudications (#773, 2026-07-14) encoded in this VM's shape:
//   - Daily + Practice as two stacked sections → two tile arrays, no
//     segmented-control state.
//   - NO streak number (not even a stub — #774 adds it later).
//   - No "just-set personal best" signal: `PersonalRecord` carries no
//     "best changed at last update" flag, so the proposal's conditional
//     `status.success` per-tile accent is omitted entirely (documented
//     deviation — the screen cannot know "just-set" from existing fields).

public import Foundation
public import Persistence
public import SudokuEngine
public import Telemetry

/// One per-difficulty stat tile: completed count, best time, computed
/// average. `bestTimeSeconds == nil` until the first completion lands;
/// `averageTimeSeconds` is `nil` whenever `completedCount == 0`.
public struct StatsTile: Sendable, Equatable, Hashable, Identifiable {
    public let difficulty: Difficulty
    public let completedCount: Int
    public let bestTimeSeconds: Int?
    public let averageTimeSeconds: Int?

    public var id: String { difficulty.rawValue }

    public init(difficulty: Difficulty, completedCount: Int, bestTimeSeconds: Int?, averageTimeSeconds: Int?) {
        self.difficulty = difficulty
        self.completedCount = completedCount
        self.bestTimeSeconds = bestTimeSeconds
        self.averageTimeSeconds = averageTimeSeconds
    }

    /// Empty placeholder tile — the pre-fetch render state and the
    /// offline/signed-out degradation target.
    public static func empty(difficulty: Difficulty) -> StatsTile {
        StatsTile(difficulty: difficulty, completedCount: 0, bestTimeSeconds: nil, averageTimeSeconds: nil)
    }

    /// Maps a `PersonalRecord` into tile values. Average is computed, not
    /// stored (`totalTimeSeconds / completedCount`, integer division), and
    /// omitted while there is nothing to average.
    public static func from(record: PersonalRecord) -> StatsTile {
        StatsTile(
            difficulty: record.difficulty,
            completedCount: record.completedCount,
            bestTimeSeconds: record.bestTimeSeconds,
            averageTimeSeconds: record.completedCount > 0
                ? record.totalTimeSeconds / record.completedCount
                : nil
        )
    }
}

@MainActor
@Observable
public final class StatsViewModel {

    /// Daily-section tiles, one per difficulty in `Difficulty.allCases`
    /// order. Seeded empty so the screen renders instantly.
    public private(set) var dailyTiles: [StatsTile] = Difficulty.allCases.map(StatsTile.empty)
    /// Practice-section tiles, same shape.
    public private(set) var practiceTiles: [StatsTile] = Difficulty.allCases.map(StatsTile.empty)

    private let persistence: any PersistenceProtocol
    private let errorReporter: any ErrorReporter
    /// Optional so previews / snapshot fixtures construct without a
    /// Telemetry actor. `nil` → no screen-viewed event.
    private let telemetry: Telemetry?
    /// Idempotency latch for `.task` — same pattern as `DailyHubViewModel`.
    private var hasBootstrapped = false

    public init(
        persistence: any PersistenceProtocol,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        telemetry: Telemetry? = nil
    ) {
        self.persistence = persistence
        self.errorReporter = errorReporter
        self.telemetry = telemetry
    }

    public func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        await telemetry?.observe(.statsViewed)
        dailyTiles = await fetchTiles(mode: .daily)
        practiceTiles = await fetchTiles(mode: .practice)
    }

    /// Fetches one mode's three per-difficulty records. Each read fails
    /// soft: a thrown error (offline / signed-out CK) reports through the
    /// funnel and keeps the empty tile for that difficulty.
    private func fetchTiles(mode: Mode) async -> [StatsTile] {
        var tiles: [StatsTile] = []
        for difficulty in Difficulty.allCases {
            do {
                let record = try await persistence.fetchPersonalRecord(mode: mode, difficulty: difficulty)
                tiles.append(.from(record: record))
            } catch {
                await errorReporter.report(
                    UserFacingError.classify(error),
                    underlying: error,
                    source: "StatsViewModel.fetchPersonalRecord"
                )
                tiles.append(.empty(difficulty: difficulty))
            }
        }
        return tiles
    }
}
