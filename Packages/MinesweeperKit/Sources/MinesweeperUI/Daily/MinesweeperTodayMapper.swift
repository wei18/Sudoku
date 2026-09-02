// MinesweeperTodayMapper — pure (MinesweeperDailyHubState, weekStrip) →
// (TodayPresentation<DailyCardModel>, StreakHeaderModel) mapping (#1021
// Phase B, design.md §3.1). Mirrors `SudokuUI.TodayMapper` — see that file's
// header for the shared rationale, not repeated in full here.
//
// D21 (design.md §3.1): MS has NO `exhausted`/`failed` hub state —
// `dailyTrio(date:)` is synchronous and non-throwing — so `present`'s switch
// over `MinesweeperDailyHubState` is exhaustive with NO `.exhausted` case to
// map at all; `MinesweeperTodayMapperTests` asserts every state × degraded
// combination structurally can never produce `.exhausted`.
//
// Card status text (spec B): completed → "Solved · m:ss"/"Solved"; failed →
// "Failed"; not started → "Not started · R × C · M mines". MS's
// `MinesweeperDailyCard` has no "in progress" concept at all (unlike
// Sudoku's `DailyCard`) — see the KNOWN DEVIATION note below — so this
// mapper only ever distinguishes completed / failed / not-started.
//
// KNOWN DEVIATION (in-progress card, spec B): Sudoku's in-progress card
// reads `PersistenceProtocol.latestInProgress()` directly off the VM's
// existing `persistence` dependency. MS's daily VM instead depends on the
// narrow `MinesweeperDailyOverlayReading` protocol (`MinesweeperPersistence`
// target), which exposes only `fetchFailedDailyIds`/`fetchCompletedDailyIdsByDay`
// — it does NOT expose `latestInProgress()`. Widening that protocol is
// exactly the "adding a NEW protocol requirement" the dispatch's forbidden
// list rules out (Persistence protocols) — so this phase does NOT add it.
// MS's Today hub therefore has no in-progress card/status at all; every
// non-completed, non-failed card renders as "not started". Flagged in the
// Phase B report as an unconfirmed/blocked item for the Leader.
//
// KNOWN DEVIATION (solved/failed thumbnails, spec C): `MinesweeperEngine`
// defers mine placement until the FIRST reveal, salted by that reveal's
// (row, col) (`MinesweeperEngine.swift`'s "Mine placement (deferred)"
// section) — there is no seed-only mine layout to reconstruct for a board
// that either hasn't been played yet (not-started, fine — no mines to draw)
// or WAS already played elsewhere (solved/failed, where the real layout
// depends on a first click this mapper never sees). Building one would need
// a persisted per-day layout read this phase's forbidden list rules out (no
// new CloudKit reads beyond `latestInProgress()` + the by-day read, and MS
// gets neither of those for its trio's own solved/failed cards). Per the
// dispatch's own escape hatch ("if it is not pure/cheap, use `.filled` for
// all cells on solved and report the deviation"), solved AND failed both
// render as a uniform `.filled` board at the difficulty's true dimensions —
// density-only (matches the actual mine density visually not at all, but
// never fabricates a layout that didn't happen).

import Foundation
internal import GameShellUI
import MinesweeperEngine

enum MinesweeperTodayMapper {

    static func present(
        state: MinesweeperDailyHubState,
        isPhase2Degraded: Bool
    ) -> TodayPresentation<DailyCardModel> {
        switch state {
        case .idle, .loading:
            return .loading
        case .loaded(let cards):
            let mapped = cards.map { cardModel(card: $0, forceNotStarted: isPhase2Degraded) }
            if isPhase2Degraded {
                return .degraded(mapped)
            }
            if !mapped.isEmpty, mapped.allSatisfy(\.isCompleted) {
                return .allDone(mapped)
            }
            return .loaded(mapped)
        }
    }

    static func headerModel(
        weekStrip: MinesweeperDailyStripSnapshot,
        allCompletedDays: Set<DayKey>
    ) -> StreakHeaderModel {
        guard !weekStrip.days.isEmpty else {
            return StreakHeaderModel(current: 0, longest: nil, last7: Array(repeating: false, count: 7), isSkeleton: true)
        }
        let longest = StreakHistory(completedDays: allCompletedDays, today: DayKey(Date(), calendar: .current)).longest
        let tappableIndices = Set(weekStrip.days.enumerated().compactMap { index, day in
            (day.isReviewable && !day.isToday) ? index : nil
        })
        let labels = weekStrip.days.map(pipAccessibilityLabel(for:))
        return StreakHeaderModel(
            current: weekStrip.streak ?? 0,
            longest: longest > 0 ? longest : nil,
            last7: weekStrip.days.map(\.isCompleted),
            isSkeleton: false,
            tappablePipIndices: tappableIndices,
            pipAccessibilityLabels: labels
        )
    }

    private static func pipAccessibilityLabel(for day: MinesweeperDailyStripDay) -> String {
        let weekday = day.date.formatted(.dateTime.weekday(.wide))
        return day.isCompleted
            ? String(localized: "\(weekday), completed", bundle: .main)
            : String(localized: "\(weekday), missed", bundle: .main)
    }

    // MARK: - Card mapping

    private static func cardModel(card: MinesweeperDailyCard, forceNotStarted: Bool) -> DailyCardModel {
        let isCompleted = !forceNotStarted && card.isCompleted
        let isFailed = !forceNotStarted && !isCompleted && card.isFailed
        return DailyCardModel(
            id: card.id,
            title: title(for: card.difficulty),
            pipLevel: pipLevel(for: card.difficulty),
            statusText: statusText(card: card, isCompleted: isCompleted, isFailed: isFailed),
            preview: thumbnail(card: card, isCompleted: isCompleted, isFailed: isFailed),
            isSkeleton: false,
            isCompleted: isCompleted,
            accessibilityIdentifier: isCompleted ? "minesweeper.dailyHub.card.completed" : nil
        )
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

    private static func statusText(card: MinesweeperDailyCard, isCompleted: Bool, isFailed: Bool) -> String {
        if isCompleted {
            guard let best = card.bestTimeSeconds else {
                return String(localized: "Solved", bundle: .main)
            }
            return String(localized: "Solved · \(timeLabel(best))", bundle: .main)
        }
        if isFailed {
            return String(localized: "Failed", bundle: .main)
        }
        let difficulty = card.difficulty
        return String(
            localized: "Not started · \(difficulty.rows) × \(difficulty.columns) · \(difficulty.mineCount) mines",
            bundle: .main
        )
    }

    private static func timeLabel(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Thumbnails (see the file header's "solved/failed" deviation note)

    private static func thumbnail(card: MinesweeperDailyCard, isCompleted: Bool, isFailed: Bool) -> BoardPreview? {
        let difficulty = card.difficulty
        if isCompleted || isFailed {
            let marks = Array(repeating: CellMark.filled, count: difficulty.rows * difficulty.columns)
            return BoardPreview(columns: difficulty.columns, rows: difficulty.rows, cells: marks)
        }
        let marks = Array(repeating: CellMark.empty, count: difficulty.rows * difficulty.columns)
        return BoardPreview(columns: difficulty.columns, rows: difficulty.rows, cells: marks)
    }
}
