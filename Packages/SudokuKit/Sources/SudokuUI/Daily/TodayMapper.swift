// TodayMapper — pure (DailyHubState, weekStrip, in-progress summary) →
// (TodayPresentation<DailyCardModel>, StreakHeaderModel) mapping (#1021
// Phase B, design.md §3.1).
//
// Kept free of CloudKit / `@MainActor`: `DailyHubView` hands this enum the
// VM's already-fetched state on every render (no new reads happen here) —
// testable directly and in isolation, see `TodayMapperTests`.
//
// Card status text + thumbnail rules (design.md §3.1, dispatch spec B/C):
//   - completed   → "Solved · m:ss" (`bestTimeSeconds`) or "Solved" (nil);
//                   thumbnail = clues `.given` + rest `.filled` (from
//                   `Puzzle.solution`, deterministic — no CK dependency).
//   - in progress (matches `inProgress.puzzleId`, not completed) →
//                   "In progress · m:ss" (the summary's elapsed) or
//                   "In progress"; thumbnail decoded from the summary's
//                   `boardState` payload when it parses, else clues-only.
//   - not started → "Not started · N givens"; thumbnail = clues `.given` only.
//
// `.degraded` (CK completion-overlay failure, `DailyHubViewModel.
// isPhase2Degraded`): thumbnails still render (seed-derived from the
// envelope already in hand, no CK dependency) but every card is forced to
// "not started" — design.md §3.1's "縮圖仍可畫...一律畫未開始態" rule. `.failed`
// (phase-1 failure: no envelopes fetched at all) has no puzzle data to draw
// real thumbnails from, so it renders `skeletonCardCount` all-skeleton
// placeholders instead — still `.degraded`, per the dispatch's "Phase-1
// failure → `.degraded` with skeleton thumbnails" rule.
//
// Thumbnail-building note: the in-progress `boardState`-decode below
// duplicates `SudokuAppComposition.SudokuBoardPreviewMapper.make(boardState:
// givenMask:)`'s ~15-line body verbatim rather than importing it —
// `SudokuAppComposition` depends on `SudokuUI` (Package.swift), not the
// reverse, so this pure decode can't cross that boundary. Flagged in the
// Phase B report as a deviation, not a defect.

import Foundation
internal import GameShellUI
import Persistence
import SudokuEngine

enum TodayMapper {

    /// `.failed` (phase-1 failure) has no real trio to count — 3 keeps the
    /// grid geometry identical to a normal `.loaded`/`.degraded` render.
    private static let skeletonCardCount = 3

    /// #1021 Phase B (Leader ruling): design.md §3.1's `loading` row needs
    /// grid-preserving skeleton CARDS, not a bare spinner. `DailyHubView`
    /// calls this directly for `DailyHubShellView`'s `loading:` slot (the
    /// `.idle`/`.loading` render); `present(state:...)`'s own `.failed`
    /// branch reuses the same 3 cards for its `.degraded` skeleton output.
    /// All 9×9 (Sudoku's only board shape) — `preview` carries the real
    /// dims (not `nil`) so `DailyCardContent`'s skeleton fallback sizes the
    /// grid correctly even though `isSkeleton` is what actually selects the
    /// skeleton render path.
    static func skeletonCards() -> [DailyCardModel] {
        (0..<skeletonCardCount).map(skeletonCard(index:))
    }

    static func present(
        state: DailyHubState,
        inProgress: SavedGameSummary?,
        isPhase2Degraded: Bool
    ) -> TodayPresentation<DailyCardModel> {
        switch state {
        case .idle, .loading:
            return .loading
        case .exhausted:
            return .exhausted
        case .failed:
            return .degraded(skeletonCards())
        case .loaded(let cards):
            let mapped = cards.map { cardModel(card: $0, inProgress: inProgress, forceNotStarted: isPhase2Degraded) }
            if isPhase2Degraded {
                return .degraded(mapped)
            }
            if !mapped.isEmpty, mapped.allSatisfy(\.isCompleted) {
                return .allDone(mapped)
            }
            return .loaded(mapped)
        }
    }

    /// - Parameters:
    ///   - weekStrip: the 7-day rolling window (`current`/`last7`/tap gating).
    ///   - allCompletedDays: every completed day, ever — feeds `longest`
    ///     (see `DailyHubViewModel.allCompletedDays`'s doc for why this
    ///     isn't itself window-capped).
    static func headerModel(
        weekStrip: DailyStripSnapshot,
        allCompletedDays: Set<DayKey>,
        today: DayKey
    ) -> StreakHeaderModel {
        guard !weekStrip.days.isEmpty else {
            return StreakHeaderModel(current: 0, longest: nil, last7: Array(repeating: false, count: 7), isSkeleton: true)
        }
        let longest = StreakHistory(completedDays: allCompletedDays, today: today).longest
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

    /// Mirrors the retired `DailyStripView.accessibilityLabel(for:)` — only
    /// ever read by `StreakHeaderView` for an index in `tappablePipIndices`
    /// (i.e. a completed, reviewable past day), but computed for every day
    /// so the two arrays (`last7` / `pipAccessibilityLabels`) stay
    /// index-aligned without a second pass.
    private static func pipAccessibilityLabel(for day: DailyStripDay) -> String {
        let weekday = day.date.formatted(.dateTime.weekday(.wide))
        return day.isCompleted
            ? String(localized: "\(weekday), completed", bundle: .main)
            : String(localized: "\(weekday), missed", bundle: .main)
    }

    // MARK: - Card mapping

    private static func cardModel(card: DailyCard, inProgress: SavedGameSummary?, forceNotStarted: Bool) -> DailyCardModel {
        let matchesInProgress = inProgress?.puzzleId == card.envelope.identity.puzzleId
        let isCompleted = !forceNotStarted && card.isCompleted
        let isInProgress = !forceNotStarted && !isCompleted && matchesInProgress
        return DailyCardModel(
            id: card.id,
            title: title(for: card.difficulty),
            pipLevel: pipLevel(for: card.difficulty),
            statusText: statusText(card: card, isCompleted: isCompleted, isInProgress: isInProgress, inProgress: inProgress),
            preview: thumbnail(card: card, isInProgress: isInProgress, isCompleted: isCompleted, inProgress: inProgress),
            isSkeleton: false,
            isCompleted: isCompleted,
            accessibilityIdentifier: isCompleted ? "sudoku.dailyHub.card.completed" : nil
        )
    }

    private static func skeletonCard(index: Int) -> DailyCardModel {
        DailyCardModel(
            id: "today-skeleton-\(index)",
            title: "",
            pipLevel: 0,
            statusText: "",
            preview: BoardPreview(
                columns: Board.dimension,
                rows: Board.dimension,
                cells: Array(repeating: .empty, count: Board.dimension * Board.dimension)
            ),
            isSkeleton: true,
            isCompleted: false,
            accessibilityIdentifier: nil
        )
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

    private static func statusText(
        card: DailyCard,
        isCompleted: Bool,
        isInProgress: Bool,
        inProgress: SavedGameSummary?
    ) -> String {
        if isCompleted {
            guard let best = card.bestTimeSeconds else {
                return String(localized: "Solved", bundle: .main)
            }
            return String(localized: "Solved · \(timeLabel(best))", bundle: .main)
        }
        if isInProgress, let inProgress {
            return String(localized: "In progress · \(timeLabel(inProgress.elapsedSeconds))", bundle: .main)
        }
        let givenCount = card.envelope.puzzle.clues.givenMask.filter { $0 }.count
        return String(localized: "Not started · \(givenCount) givens", bundle: .main)
    }

    private static func timeLabel(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Thumbnails

    private static func thumbnail(
        card: DailyCard,
        isInProgress: Bool,
        isCompleted: Bool,
        inProgress: SavedGameSummary?
    ) -> BoardPreview? {
        if isCompleted {
            return solvedPreview(puzzle: card.envelope.puzzle)
        }
        if isInProgress, let inProgress,
           let preview = inProgressPreview(boardState: inProgress.boardState, givenMask: card.envelope.puzzle.clues.givenMask) {
            return preview
        }
        return notStartedPreview(puzzle: card.envelope.puzzle)
    }

    private static func notStartedPreview(puzzle: Puzzle) -> BoardPreview? {
        let marks = puzzle.clues.cells.map { $0 != 0 ? CellMark.given : CellMark.empty }
        return BoardPreview(columns: Board.dimension, rows: Board.dimension, cells: marks)
    }

    private static func solvedPreview(puzzle: Puzzle) -> BoardPreview? {
        let marks = puzzle.clues.givenMask.map { $0 ? CellMark.given : CellMark.filled }
        return BoardPreview(columns: Board.dimension, rows: Board.dimension, cells: marks)
    }

    /// Duplicated from `SudokuAppComposition.SudokuBoardPreviewMapper.make`
    /// — see the file header's "Thumbnail-building note" for why this can't
    /// just import that mapper.
    private static func inProgressPreview(boardState: String?, givenMask: [Bool]) -> BoardPreview? {
        guard let boardState else { return nil }
        let columns = Board.dimension, rows = Board.dimension
        guard boardState.count == columns * rows, givenMask.count == columns * rows else { return nil }
        var cells: [CellMark] = []
        cells.reserveCapacity(columns * rows)
        for (index, character) in boardState.enumerated() {
            if character == "." {
                cells.append(.empty)
            } else if character.isNumber {
                cells.append(givenMask[index] ? .given : .filled)
            } else {
                return nil
            }
        }
        return BoardPreview(columns: columns, rows: rows, cells: cells)
    }
}
