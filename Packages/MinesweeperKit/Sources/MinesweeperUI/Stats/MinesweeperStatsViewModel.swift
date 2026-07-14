// MinesweeperStatsViewModel — Statistics screen data (#773).
//
// Per-app mirror of Sudoku's `StatsViewModel` (the issue's explicit scope
// note: per-app screens, no shared cross-app Stats extraction). Reads ONLY
// fields that exist on `MinesweeperPersonalRecord` today (zero schema
// changes): `completedCount`, `bestTimeSeconds` (nilable), and
// `totalTimeSeconds` → average computed client-side as `total / count`.
// `completedCount` counts WINS for Minesweeper (only `submitWinIfWon()`
// writes) — there is no loss counter, which is why the proposal's win-rate
// tile is adjudicated OUT of v1 (#773 owner comment).
//
// Fetch contract mirrors the daily hub's graceful-degrade posture: render
// immediately with empty tiles, fill as async CloudKit reads land; failures
// (offline / iCloud signed-out) funnel through `errorReporter` and keep the
// empty tile. A `nil` store (previews / tests without persistence) renders
// permanent zeros — the same optional-seam convention as the rest of
// MinesweeperUI.
//
// Owner adjudications encoded here: two stacked sections (daily + practice
// tile arrays, no segmented control), NO streak number, NO win-rate tile,
// no "just-set personal best" accent (no such signal exists on the record).

public import Foundation
public import MinesweeperEngine
public import MinesweeperPersistence
public import Telemetry

/// One per-difficulty stat tile — mirror of Sudoku's `StatsTile`.
public struct MinesweeperStatsTile: Sendable, Equatable, Hashable, Identifiable {
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
    public static func empty(difficulty: Difficulty) -> MinesweeperStatsTile {
        MinesweeperStatsTile(difficulty: difficulty, completedCount: 0, bestTimeSeconds: nil, averageTimeSeconds: nil)
    }

    /// Maps a `MinesweeperPersonalRecord` into tile values. Average is
    /// computed, not stored, and omitted while there is nothing to average.
    public static func from(record: MinesweeperPersonalRecord) -> MinesweeperStatsTile {
        MinesweeperStatsTile(
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
public final class MinesweeperStatsViewModel {

    /// Daily-section tiles, one per difficulty in `Difficulty.allCases`
    /// order (Beginner / Intermediate / Expert). Seeded empty so the screen
    /// renders instantly.
    public private(set) var dailyTiles: [MinesweeperStatsTile] = Difficulty.allCases.map(MinesweeperStatsTile.empty)
    /// Practice-section tiles, same shape (real data since #779 — practice
    /// personal bests write for both hubs).
    public private(set) var practiceTiles: [MinesweeperStatsTile] = Difficulty.allCases.map(MinesweeperStatsTile.empty)

    private let store: MinesweeperPersonalRecordStore?
    private let errorReporter: (any ErrorReporter)?
    /// Optional so previews / snapshot fixtures construct without a
    /// Telemetry actor. `nil` → no screen-viewed event.
    private let telemetry: Telemetry?
    /// Idempotency latch for `.task` — same pattern as the hubs.
    private var hasBootstrapped = false

    public init(
        store: MinesweeperPersonalRecordStore?,
        errorReporter: (any ErrorReporter)? = nil,
        telemetry: Telemetry? = nil
    ) {
        self.store = store
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
    private func fetchTiles(mode: GameMode) async -> [MinesweeperStatsTile] {
        guard let store else { return Difficulty.allCases.map(MinesweeperStatsTile.empty) }
        var tiles: [MinesweeperStatsTile] = []
        for difficulty in Difficulty.allCases {
            do {
                let record = try await store.fetch(modeRaw: mode.rawValue, difficulty: difficulty)
                tiles.append(.from(record: record))
            } catch {
                await errorReporter?.report(
                    UserFacingError.classify(error),
                    underlying: error,
                    source: "MinesweeperStatsViewModel.fetch"
                )
                tiles.append(.empty(difficulty: difficulty))
            }
        }
        return tiles
    }
}
